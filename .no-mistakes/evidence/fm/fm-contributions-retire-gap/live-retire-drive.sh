#!/usr/bin/env bash
# Live drive of fm-contributions.sh retire in a disposable lab home against real GitHub.
set -u
W=/home/stephen/.no-mistakes/worktrees/b7f93037c9f2/01M46P135B2CEVF9R2M0YQYY0K
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX"); "$W/bin/fm-lab-home.sh" create "$LAB" >/dev/null; mkdir -p "$LAB/tmux"
trap 'rm -rf "$LAB"' EXIT
U=https://github.com/kunchenguid/fm-retire-probe-deleted-xyz/pull/1
run() { echo "\$ $*"; env -u TMUX -u NO_MISTAKES_GATE -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE TMUX_TMPDIR="$LAB/tmux" FM_HOME="$LAB" "$@"; echo "[exit $?]"; }
cov() { run bash -c "'$W/bin/fm-bearings-snapshot.sh' --json | jq -c '.contributions | {known,checked,complete,proven_clear}'"; }
printf '# Backlog\n\n## Queued\n- [ ] gone - Filed %s (repo: sample) (kind: ship)\n' "$U" > "$LAB/data/backlog.md"
echo "== S1: gone repo raises unavailable check and holds coverage incomplete"
run "$W/bin/fm-contributions.sh" poll
run jq -c '.records[0]|{url,error,retired}' "$LAB/data/gone/contributions.json"
cov
echo "== S3 adversarial: bad actor / empty reason / unrecorded pair / missing reason"
run "$W/bin/fm-contributions.sh" retire gone "$U" robot 'repo deleted'
run "$W/bin/fm-contributions.sh" retire gone "$U" captain ''
run "$W/bin/fm-contributions.sh" retire gone "$U" captain
run "$W/bin/fm-contributions.sh" retire other "$U" captain 'repo deleted'
echo "== S2: retire with provenance"
run "$W/bin/fm-contributions.sh" retire gone "$U" captain 'repository deleted upstream (kunchenguid/firstmate#6641)'
run jq -c '.records[0]|{url,retired}' "$LAB/data/gone/contributions.json"
echo "== S2: retire again keeps first provenance"
run "$W/bin/fm-contributions.sh" retire gone "$U" fleet 'second reason'
run jq -c '.records[0].retired' "$LAB/data/gone/contributions.json"
echo "== S2: poll after retire is silent; backlog link still present; coverage complete"
grep -c "$U" "$LAB/data/backlog.md"
run "$W/bin/fm-contributions.sh" poll
cov
echo "== S4 adversarial: retire refused while a pending signal is unacknowledged"
mkdir -p "$LAB/data/sig"; U2=https://github.com/kunchenguid/fm-retire-probe-deleted-xyz/pull/2
printf -- '- [ ] sig - Filed %s (repo: sample) (kind: ship)\n' "$U2" >> "$LAB/data/backlog.md"
run "$W/bin/fm-contributions.sh" poll
jq '.records[0].pending=[{token:"comment:1:x",type:"comment"}]' "$LAB/data/sig/contributions.json" > "$LAB/t" && mv "$LAB/t" "$LAB/data/sig/contributions.json"
run "$W/bin/fm-contributions.sh" retire sig "$U2" fleet 'repo deleted'
run jq -c '.records[0]|{retired,pending:(.pending|length)}' "$LAB/data/sig/contributions.json"
