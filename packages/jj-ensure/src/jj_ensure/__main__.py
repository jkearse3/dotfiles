"""Support invoking jj-ensure as ``python -m jj_ensure``."""

from .cli import main


raise SystemExit(main())
