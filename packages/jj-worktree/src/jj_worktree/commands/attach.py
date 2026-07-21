from __future__ import annotations

import os
import shutil
import stat
from pathlib import Path

from ..core import managed, process, repository
from ..core.process import WorktreeError
from ..core.repository import MANAGED_ROOT_NAME


def _validate_external_worktree(target: Path, private_git: Path) -> None:
    worktrees = repository.parse_worktrees(target)
    primary = worktrees[0]
    if target == primary.path:
        raise WorktreeError("cannot attach the primary Git worktree")
    matches = [worktree for worktree in worktrees if worktree.path == target]
    if len(matches) != 1:
        raise WorktreeError("target is not uniquely registered by Git")
    if matches[0].git_dir is None:
        raise WorktreeError("target has a stale Git worktree registration")
    repository.same_file(
        matches[0].git_dir,
        private_git,
        "registered worktree does not use the discovered private Git directory",
    )
    try:
        _ = target.relative_to(primary.path.resolve(strict=True) / MANAGED_ROOT_NAME)
    except ValueError:
        pass
    except OSError as error:
        raise WorktreeError(f"could not validate the managed namespace: {error}") from error
    else:
        raise WorktreeError("cannot attach a worktree inside the managed namespace")


def attach_worktree(start: Path | None = None) -> Path:
    requested = Path(".") if start is None else start
    target = repository.git_path(requested, "rev-parse", "--show-toplevel")
    private_git = repository.git_path(target, "rev-parse", "--absolute-git-dir")
    common_git = repository.git_path(target, "rev-parse", "--git-common-dir")
    if os.path.samefile(private_git, common_git):
        raise WorktreeError("cannot attach the primary Git worktree")
    _validate_external_worktree(target, private_git)
    jj_path = target / ".jj"
    try:
        jj_mode = jj_path.lstat().st_mode
    except FileNotFoundError:
        jj_mode = None
    except OSError as error:
        raise WorktreeError(f"could not inspect pre-existing .jj: {error}") from error
    if jj_mode is not None:
        if not stat.S_ISDIR(jj_mode):
            raise WorktreeError("pre-existing .jj is not a compatible directory")
        try:
            managed.validate_attached_jj(target, private_git)
        except WorktreeError as error:
            raise WorktreeError(f"pre-existing .jj is incompatible: {error}") from error
        return target
    try:
        _ = process.checked(
            ["jj", "git", "init", f"--git-repo={private_git}", "."],
            cwd=target,
            label="jj external-worktree initialization",
        )
        managed.validate_attached_jj(target, private_git)
        _validate_external_worktree(target, private_git)
    except (OSError, WorktreeError) as error:
        cleanup_error: OSError | None = None
        try:
            if jj_path.is_symlink() or not jj_path.is_dir():
                jj_path.unlink(missing_ok=True)
            else:
                shutil.rmtree(jj_path)
        except OSError as cleanup_failure:
            cleanup_error = cleanup_failure
        suffix = f"; cleanup failed: {cleanup_error}" if cleanup_error is not None else ""
        raise WorktreeError(f"could not attach external worktree: {error}{suffix}") from error
    return target
