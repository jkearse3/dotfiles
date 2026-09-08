"""Freshly fenced lifecycle and repair. Never replay an uncertain external operation."""

import os
from collections.abc import Generator
from contextlib import ExitStack, contextmanager, nullcontext
from dataclasses import asdict
from pathlib import Path

from .config import PI_KIND, Config, select_launch
from .context import Context, discover
from .errors import TeamError, present, require
from .herdr import Herdr, same_binding
from .ids import alias, is_id, resolve_cwd, tab_label
from .locks import Locks
from .models import SETTLED, Health, Snapshot, Teammate
from .registry import Registry

RECREATE_GUIDANCE = (
    "No in-place restart: explicitly close this teammate, then create a fresh one "
    "with the desired launch configuration. Normal close protections apply; old completed results remain retrievable."
)


class Team:
    def __init__(
        self, registry: Registry, runtime: Herdr, locks: Locks, config: Config
    ) -> None:
        self.registry: Registry = registry
        self.runtime: Herdr = runtime
        self.locks: Locks = locks
        self.config: Config = config
        self.context: Context = discover(runtime)

    def refresh(self) -> Context:
        self.context = discover(self.runtime, compatibility=False)
        return self.context

    def resolve(self, reference: str) -> Teammate:
        context = self.refresh()
        return self.registry.resolve(
            reference, context.endpoint, context.caller.workspace_id
        )

    @contextmanager
    def locked(self, reference: str, *, topology: bool = False) -> Generator[Teammate]:
        record = self.resolve(reference)
        # One endpoint topology lock also serializes cross-workspace relocation and final-tab counting.
        with (
            self.locks.hold("topology:" + record.endpoint)
            if topology
            else nullcontext(),
            self.locks.hold(record.teammate_id),
        ):
            context = self.refresh()
            current = self.registry.resolve(
                reference, context.endpoint, context.caller.workspace_id
            )
            require(
                current.teammate_id == record.teammate_id,
                "conflict",
                "Name binding changed before lock",
            )
            yield current

    def observe(self, record: Teammate) -> tuple[Teammate, Health, Snapshot]:
        from .topology import derive

        for _ in range(4):
            current = self.registry.get(record.teammate_id)
            snapshot = self.runtime.snapshot()
            health = derive(current, snapshot)
            if not health.automatic:
                require(
                    self.registry.get(current.teammate_id).revision == current.revision,
                    "conflict",
                    "Intent changed during observation",
                )
                return current, health, snapshot
            phase = (
                "closed"
                if health.action == "finalize_closed"
                else ("managed" if health.action == "promote" else current.phase)
            )
            record = self.registry.transition(
                current,
                phase=phase,
                tab=health.tab.tab_id if health.tab else None,
                pane=health.pane.pane_id if health.pane else None,
            )
        raise TeamError(
            "conflict", "Topology did not converge within the bounded observation fence"
        )

    def healthy(
        self, record: Teammate, *, settled: bool = False
    ) -> tuple[Teammate, Health, Snapshot]:
        record, health, snapshot = self.observe(record)
        require(
            health.status == "healthy" and health.pane is not None,
            "unhealthy",
            f"Teammate health is {health.status}; inspect repair before acting",
        )
        if settled:
            require(
                health.pane is not None and health.pane.status in SETTLED,
                "not_settled",
                "Teammate must be idle or done",
            )
        return record, health, snapshot

    def view(self, record: Teammate, health: Health) -> dict[str, object]:
        request = self.registry.slot(record.teammate_id)
        return {
            **asdict(record),
            "health": health.status,
            "runtime_status": health.pane.status
            if health.pane and health.pane.kind
            else None,
            "repair_action": health.action,
            "guidance": RECREATE_GUIDANCE
            if health.status in ("agent_missing", "launch_uncertain")
            else None,
            "binding": asdict(health.pane) if health.pane else None,
            "request": None
            if request is None
            else {
                "request_id": request.request_id,
                "delivery": request.delivery,
                "request_status": (
                    "completed" if request.reply is not None else "pending"
                ),
            },
        }

    def show(self, reference: str) -> dict[str, object]:
        with self.locked(reference) as record:
            record, health, _ = self.observe(record)
            return self.view(record, health)

    def list(
        self, all_workspaces: bool, include_closed: bool
    ) -> list[dict[str, object]]:
        context = self.refresh()
        records = self.registry.list(
            context.endpoint,
            None if all_workspaces else context.caller.workspace_id,
            include_closed,
        )
        return [self.show(record.teammate_id) for record in records]

    def create(
        self, name: str, profile_name: str | None, cwd: str | None, timeout: int | None
    ) -> dict[str, object]:
        context = self.refresh()
        _ = select_launch(
            self.config, profile_name, context.caller.kind, self.runtime.environment
        )
        directory = resolve_cwd(cwd, self.runtime.environment.get("PWD", os.getcwd()))
        startup_timeout = (
            timeout if timeout is not None else self.config.startup_timeout_seconds
        )
        with (
            self.locks.hold("topology:" + context.endpoint),
            ExitStack() as creation_lock,
        ):
            context = self.refresh()
            launch = select_launch(
                self.config, profile_name, context.caller.kind, self.runtime.environment
            )
            before = context.snapshot
            record = self.registry.reserve(
                context.endpoint,
                context.caller.workspace_id,
                name,
                launch.profile.name if launch.profile is not None else None,
                PI_KIND,
                directory,
            )
            # Observers can bind provisioning intent; exclude them until startup is fenced.
            _ = creation_lock.enter_context(self.locks.hold(record.teammate_id))
            environment = launch.env + (
                ("PI_SHEPHERD_TEAMMATE_ID", record.teammate_id),
                ("XDG_STATE_HOME", str(self.registry.path.parent.parent)),
            )
            try:
                tab, pane = self.runtime.create_tab(
                    record.workspace_id,
                    directory,
                    tab_label(record.teammate_id, record.logical_name),
                    environment,
                )
                new_identity = all(t.tab_id != tab.tab_id for t in before.tabs) and all(
                    p.pane_id != pane.pane_id and p.terminal_id != pane.terminal_id
                    for p in before.panes
                )
                require(
                    new_identity
                    and tab.workspace_id == record.workspace_id
                    and pane.workspace_id == record.workspace_id
                    and pane.tab_id == tab.tab_id
                    and tab.label == tab_label(record.teammate_id, record.logical_name)
                    and tab.pane_count == 1
                    and not tab.focused
                    and not pane.focused
                    and pane.kind is None,
                    "protocol",
                    "Creation returned unsafe topology",
                )
                require(
                    pane.cwd is not None and Path(pane.cwd).samefile(directory),
                    "protocol",
                    "Creation cwd is unverified",
                )
            except (TeamError, OSError) as error:
                raise TeamError(
                    "creation_incomplete",
                    f"Creation incomplete; inspect {record.teammate_id}; never replay automatically",
                    uncertain=not isinstance(error, TeamError)
                    or error.uncertain
                    or error.code == "protocol",
                ) from error
            record = self.registry.transition(
                record, phase="provisioning", tab=tab.tab_id, pane=pane.pane_id
            )
            from .topology import derive

            preflight = derive(record, self.runtime.snapshot())
            require(
                preflight.status == "launch_uncertain"
                and preflight.pane is not None
                and preflight.pane.terminal_id == pane.terminal_id,
                "creation_incomplete",
                "Created binding changed before startup",
            )
            started = self.runtime.start(
                pane,
                alias(record.teammate_id),
                PI_KIND,
                launch.args,
                startup_timeout,
            )
            record, health, _ = self.observe(record)
            require(
                health.status == "healthy"
                and health.pane is not None
                and same_binding(started, health.pane),
                "creation_incomplete",
                "Startup binding could not be confirmed",
            )
            return self.view(record, health)

    def repair(self, reference: str, apply: bool) -> dict[str, object]:
        with self.locked(reference, topology=True) as record:
            record, health, _ = self.observe(record)
            result: dict[str, object] = {
                "teammate_id": record.teammate_id,
                "health": health.status,
                "action": health.action,
                "evidence": {
                    "revision": record.revision,
                    "tab_id": health.tab.tab_id if health.tab else None,
                    "pane_id": health.pane.pane_id if health.pane else None,
                    "marker": health.tab.label if health.tab else None,
                    "alias": health.pane.name if health.pane else None,
                },
                "applied": False,
                "guidance": RECREATE_GUIDANCE
                if health.status in ("agent_missing", "launch_uncertain")
                else None,
            }
            if not apply or health.action is None:
                return result
            # Revalidate immediately before the requested effect, under both locks.
            record, refreshed, snapshot = self.observe(record)
            require(
                refreshed == health,
                "conflict",
                "Repair evidence changed; inspect again",
            )
            require(
                health.tab is not None and health.pane is not None,
                "unhealthy",
                "Repair has no exact target",
            )
            tab, pane = present(health.tab), present(health.pane)
            if health.action == "accept_relocation":
                require(
                    is_id(reference),
                    "full_id_required",
                    "Relocation requires the full teammate ID",
                )
                _ = self.registry.transition(
                    record,
                    phase=record.phase,
                    workspace=tab.workspace_id,
                    tab=tab.tab_id,
                    pane=pane.pane_id,
                )
            elif health.action == "restore_marker":
                self.runtime.rename(
                    tab, tab_label(record.teammate_id, record.logical_name)
                )
            elif health.action == "resume_close":
                _ = self.close_bound(record, health, snapshot, force=False)
            else:
                raise TeamError("unhealthy", "No supported repair action")
            result["applied"] = True
            return result

    def close_bound(
        self, record: Teammate, health: Health, snapshot: Snapshot, force: bool
    ) -> Teammate:
        require(
            health.status in ("healthy", "agent_missing", "launch_uncertain", "closing")
            and health.tab is not None
            and health.pane is not None,
            "unhealthy",
            "Close requires an exact, uncontaminated accepted tab",
        )
        require(
            sum(tab.workspace_id == record.workspace_id for tab in snapshot.tabs) > 1,
            "final_tab",
            "Refusing to close the final workspace tab",
        )
        pane, tab = present(health.pane), present(health.tab)
        if pane.kind is None:
            require(
                self.runtime.shell_ready(pane),
                "shell_unverified",
                "Close requires positive foreground-shell evidence when the agent is missing",
            )
        slot = self.registry.slot(record.teammate_id)
        if not force:
            require(
                slot is None or slot.reply is not None,
                "pending",
                "Cancel pending work before closing",
            )
            require(
                pane.kind is None or pane.status in SETTLED,
                "not_settled",
                "Close requires a settled teammate",
            )
        if record.phase != "closing":
            record = self.registry.transition(record, phase="closing")
        self.runtime.close_tab(tab)
        record, final, _ = self.observe(record)
        require(
            final.status == "closed",
            "close_incomplete",
            "Close is unconfirmed; inspect repair, do not replay automatically",
        )
        return record

    def close(self, reference: str, force: bool) -> dict[str, object]:
        with self.locked(reference, topology=True) as record:
            record, health, snapshot = self.observe(record)
            if health.status != "closed":
                record = self.close_bound(record, health, snapshot, force)
            return {"teammate_id": record.teammate_id, "phase": record.phase}

    def forget(self, reference: str, force: bool) -> dict[str, object]:
        with self.locked(reference, topology=True) as record:
            record, health, _ = self.observe(record)
            require(
                health.status
                in {
                    "closed",
                    "healthy",
                    "agent_missing",
                    "launch_uncertain",
                    "creation_uncertain",
                    "closing",
                },
                "unhealthy",
                "Cannot forget ambiguous or malformed topology",
            )
            self.registry.forget(record, force)
            return {
                "teammate_id": record.teammate_id,
                "forgotten": True,
                "warning": "WARNING: forced forget may orphan a live tab or discard a result"
                if force
                else None,
            }
