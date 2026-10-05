#!/usr/bin/env bash
# Live: retired URL leaves rotation (real gh, call-logged); late owner of a retired final record is not retired.
set -u
W=/home/stephen/.no-mistakes/worktrees/b7f93037c9f2/01M46P135B2CEVF9R2M0YQYY0K
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX"); "$W/bin/fm-lab-home.sh" create "$LAB" >/dev/null; mkdir -p "$LAB/tmux" "$LAB/logbin"
trap 'rm -rf "$LAB"' EXIT
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/gh-calls"\nexec /usr/bin/gh "$@"\n' "$LAB" > "$LAB/logbin/gh"; chmod +x "$LAB/logbin/gh"
run() { echo "\$ $*"; env -u TMUX -u NO_MISTAKES_GATE -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE PATH="$LAB/logbin:$PATH" TMUX_TMPDIR="$LAB/tmux" FM_HOME="$LAB" "$@"; echo "[exit $?]"; }
cov() { run bash -c "'$W/bin/fm-bearings-snapshot.sh' --json | jq -c '.contributions | {known,checked,complete,proven_clear}'"; }
G=https://github.com/kunchenguid/fm-retire-probe-deleted-xyz/pull/1
M=https://github.com/kunchenguid/firstmate/pull/6647
printf '# Backlog\n\n## Queued\n- [ ] gone - Filed %s (repo: sample) (kind: ship)\n- [ ] alpha - Filed %s (repo: sample) (kind: ship)\n' "$G" "$M" > "$LAB/data/backlog.md"
echo "== initial poll (real GitHub)"; run "$W/bin/fm-contributions.sh" poll
echo "gh calls touching deleted repo: $(grep -c fm-retire-probe "$LAB/gh-calls")"
run jq -c '.records[0]|{url,state:.observation.state,error}' "$LAB/data/alpha/contributions.json"
echo "== acknowledge alpha pending signals (retire requires it)"
for t in $(jq -r '.records[0].pending[].token' "$LAB/data/alpha/contributions.json"); do run "$W/bin/fm-contributions.sh" ack alpha "$M" "$t" >/dev/null; done
run jq -c '.records[0].pending|length' "$LAB/data/alpha/contributions.json"
echo "== retire both: deleted-repo PR on gone, merged final PR on alpha"
run "$W/bin/fm-contributions.sh" retire gone "$G" captain 'repository deleted'
run "$W/bin/fm-contributions.sh" retire alpha "$M" fleet 'retired final record for late-owner check'
: > "$LAB/gh-calls"
for i in 1 2 3; do run "$W/bin/fm-contributions.sh" poll; done
echo "gh calls across 3 polls after retire: $(wc -l < "$LAB/gh-calls")"; cat "$LAB/gh-calls"
cov
echo "== late owner beta links the same merged URL"
printf -- '- [ ] beta - Filed %s (repo: sample) (kind: ship)\n' "$M" >> "$LAB/data/backlog.md"
: > "$LAB/gh-calls"
run "$W/bin/fm-contributions.sh" poll
echo "gh calls for late-owner settle: $(wc -l < "$LAB/gh-calls")"
run jq -c '.records[0]|{url,state:.observation.state,error,retired}' "$LAB/data/beta/contributions.json"
run jq -c '.records[0].retired' "$LAB/data/alpha/contributions.json"
cov
