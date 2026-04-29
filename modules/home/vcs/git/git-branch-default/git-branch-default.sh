#!/usr/bin/env bash

# Print the default remote branch name (e.g., "main").

ref=$(git symbolic-ref refs/remotes/origin/HEAD)
echo "${ref#refs/remotes/origin/}"
