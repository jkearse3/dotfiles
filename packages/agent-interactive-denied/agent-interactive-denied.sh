#!/usr/bin/env bash

set -u

program=${1-}
interaction=${2-}

case "$program:$interaction" in
jj:editor)
	guidance="pass the description explicitly, for example with 'jj describe -m <message>'"
	;;
jj:diff-editor)
	guidance="make the intended file changes directly instead of launching 'jj diffedit'"
	;;
jj:merge-editor)
	guidance="resolve the conflicted files directly and continue without an interactive merge tool"
	;;
git:editor)
	guidance="pass the message explicitly, for example with 'git commit -m <message>'"
	;;
git:sequence-editor)
	guidance="use a non-interactive history-editing command"
	;;
git:askpass | ssh:askpass)
	guidance="configure non-interactive credentials before retrying"
	;;
*)
	printf 'agent-interactive-denied: unsupported context %q %q\n' "$program" "$interaction" >&2
	exit 2
	;;
esac

printf 'agent-interactive-denied: blocked %s %s in a coding-agent session; %s.\n' \
	"$program" "$interaction" "$guidance" >&2
exit 1
