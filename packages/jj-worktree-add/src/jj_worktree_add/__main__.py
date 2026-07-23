"""Support invoking jj-worktree-add as ``python -m jj_worktree_add``."""

from .cli import main


raise SystemExit(main())
