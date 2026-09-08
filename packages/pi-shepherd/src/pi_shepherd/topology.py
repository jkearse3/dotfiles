"""Pure health and repair proposals from durable intent and one validated snapshot."""

from .ids import alias, marker, tab_label
from .models import Health, Snapshot, Teammate


def derive(record: Teammate, snapshot: Snapshot) -> Health:
    identity_marker = marker(record.teammate_id)
    marked = [tab for tab in snapshot.tabs if identity_marker in tab.label]
    named = [
        agent for agent in snapshot.agents if agent.name == alias(record.teammate_id)
    ]
    owned = next((tab for tab in snapshot.tabs if tab.tab_id == record.tab_id), None)
    if len(marked) > 1 or len(named) > 1:
        return Health("ambiguous")
    accepted_label = tab_label(record.teammate_id, record.logical_name)
    if marked and marked[0].label != accepted_label:
        return Health("marker_conflict")
    agent = named[0] if named else None
    if agent is not None and agent.kind != record.kind:
        return Health("kind_conflict")
    if marked and agent and marked[0].tab_id != agent.tab_id:
        return Health("binding_conflict")

    if record.phase == "closed":
        return Health(
            "closed"
            if not marked and not named and owned is None
            else "closed_resource_present"
        )
    if owned is None and not marked and agent is None:
        if record.phase in ("managed", "closing"):
            return Health("absent", action="finalize_closed", automatic=True)
        return Health("creation_uncertain")
    candidate = marked[0] if marked else owned
    if candidate is None:
        return Health("binding_conflict")
    panes = [pane for pane in snapshot.panes if pane.tab_id == candidate.tab_id]
    agents = [item for item in snapshot.agents if item.tab_id == candidate.tab_id]
    if len(panes) != 1 or candidate.pane_count != 1:
        return Health("contaminated")
    pane = panes[0]
    if agent is not None:
        if (
            agent.pane_id != pane.pane_id
            or agents != [agent]
            or pane.kind not in (None, record.kind)
        ):
            return Health("contaminated")
        pane = agent
    elif agents or pane.kind is not None:
        return Health("contaminated")

    relocated = (
        candidate.tab_id != record.tab_id
        or candidate.workspace_id != record.workspace_id
    )
    if record.tab_id is None:
        if not marked or candidate.workspace_id != record.workspace_id:
            return Health("binding_conflict")
        return Health(
            "provisioning", action="bind", tab=candidate, pane=pane, automatic=True
        )
    if relocated:
        if not marked or agent is None:
            return Health("binding_conflict")
        return Health("relocated", action="accept_relocation", tab=candidate, pane=pane)
    if candidate.label != accepted_label:
        if agent is None or "pi-shepherd:" in candidate.label:
            return Health("marker_conflict")
        return Health(
            "marker_changed", action="restore_marker", tab=candidate, pane=pane
        )
    if agent is None and pane.pane_id != record.pane_id:
        return Health("binding_conflict")
    if record.phase == "closing":
        return Health("closing", action="resume_close", tab=candidate, pane=pane)
    if agent is None:
        # A provisioning crash can leave an in-flight start. Absence is not permission to replay it.
        if record.phase == "provisioning":
            return Health("launch_uncertain", tab=candidate, pane=pane)
        return Health("agent_missing", tab=candidate, pane=pane)
    if record.phase == "provisioning":
        return Health(
            "provisioning", action="promote", tab=candidate, pane=pane, automatic=True
        )
    if pane.pane_id != record.pane_id:
        return Health(
            "pane_moved",
            action="refresh_pane",
            tab=candidate,
            pane=pane,
            automatic=True,
        )
    return Health("healthy", tab=candidate, pane=pane)
