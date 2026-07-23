"""Ensure Git checkouts have compatible jj workspace state.

The public interface is the ``jj-ensure`` command. Implementation details
live in :mod:`jj_ensure.cli` because the safety checks form one coordinated
workflow rather than a general-purpose library API.
"""
