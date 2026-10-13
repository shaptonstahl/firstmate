#!/usr/bin/env bash
# Live check for requirement C: a real Claude Code session that started read-only
# (lock held by another live harness) is told once, via the Stop auto-arm
# rewake, that it took the lock over after the holder died.
set -u
ROOT=$1; EVID=$2
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX")
PROJECT="$LAB/project"; HOME_DIR="$LAB/fmhome"; T="$LAB/claude.jsonl"
cleanup() { [ -n "${HOLDER:-}" ] && { pkill -P "$HOLDER" 2>/dev/null; kill "$HOLDER" 2>/dev/null; }; [ -n "${KEEP_LAB:-}" ] && { echo "kept lab: $LAB"; return; }; rm -rf "$LAB"; }
trap cleanup EXIT
"$ROOT/bin/fm-lab-home.sh" create "$HOME_DIR" >/dev/null || exit 1
git clone -q "$ROOT" "$PROJECT"; cp -R "$ROOT/bin/." "$PROJECT/bin/"; cp "$ROOT/.claude/settings.json" "$PROJECT/.claude/settings.json"
printf 'project=fixture\nwindow=fixture\nbackend=tmux\n' > "$HOME_DIR/state/task.meta"
ln -s /bin/bash "$LAB/claude"
"$LAB/claude" -c "sleep 900; :" >/dev/null 2>&1 & HOLDER=$!
printf '%s\n' "$HOLDER" > "$HOME_DIR/state/.lock"; printf 'SID-PREVIOUS-HOLDER\n' > "$HOME_DIR/state/.lock-session"
printf '%s\n' "$HOLDER" > "$HOME_DIR/state/holder-pid"
cat > "$PROJECT/bin/release-holder.sh" <<'SH'
#!/usr/bin/env bash
p=$(cat "$FM_HOME/state/holder-pid"); pkill -P "$p"; kill "$p" 2>/dev/null; for _ in $(seq 50); do kill -0 "$p" 2>/dev/null || break; sleep 0.1; done
echo "previous lock holder pid $p ended"
SH
cat > "$PROJECT/bin/fm-watch-arm.sh" <<'SH'
#!/usr/bin/env bash
N=$(cat "$FM_HOME/state/arm-count" 2>/dev/null || echo 0); N=$((N+1)); echo "$N" > "$FM_HOME/state/arm-count"
echo "arm-run=$N pid=$$" >> "$FM_HOME/state/arm-ran"
if [ "$N" -ge 3 ]; then rm -f "$FM_HOME/state/task.meta"; printf 'watcher: attached pid=%s (beacon 2s)\n' "$$"; exit 0; fi
printf 'pending:downtime:fixture-generation-%s\n' "$N" > "$FM_HOME/state/.watcher-down"
touch "$FM_HOME/state/.last-watcher-beat"
printf 'watcher: started pid=%s (beacon fresh)\n' "$$"; printf 'stale: fixture-wake-%s\n' "$N"; exit 0
SH
cat > "$PROJECT/bin/fm-wake-drain.sh" <<'SH'
#!/usr/bin/env bash
N=$(cat "$FM_HOME/state/drain-count" 2>/dev/null || echo 0); N=$((N+1)); echo "$N" > "$FM_HOME/state/drain-count"
[ "$N" -ge 3 ] && rm -f "$FM_HOME/state/task.meta"; printf 'stale: fixture drained\n'
SH
chmod +x "$PROJECT"/bin/release-holder.sh "$PROJECT"/bin/fm-watch-arm.sh "$PROJECT"/bin/fm-wake-drain.sh
PROMPT='First run exactly `bin/release-holder.sh` with Bash. Then reply with exactly CYCLE0 and stop. Whenever a Stop hook feedback message wakes you, copy every line of it that starts with "firstmate fleet lock:" verbatim into your reply (or write NO-LOCK-LINE if none), run exactly `bin/fm-wake-drain.sh` once with Bash, then end your reply with ACK and stop. Never run any arm or lock command.'
( cd "$PROJECT" && env -u NO_MISTAKES_GATE -u FM_GATE_REFUSE_BYPASS -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE -u CLAUDE_CODE_SESSION_ID -u CLAUDE_PID \
  FM_HOME="$HOME_DIR" CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false CLAUDE_CODE_SEND_FEEDBACK=0 \
  claude -p "$PROMPT" --dangerously-skip-permissions --settings '{"feedbackDrafts":"off"}' --effort low --output-format stream-json --verbose ) > "$T" 2>&1
echo "claude rc=$?"
cp "$T" "$EVID/live-takeover-claude-transcript${RUN_TAG:-}.jsonl"; grep "^{" "$T" > "$T.clean"; T="$T.clean"
echo "== SessionStart digest LOCK section =="
jq -r 'select(.type=="system" and .subtype=="hook_response" and .hook_event=="SessionStart") | .stdout' "$T" | sed -n '/^LOCK/,/^BOOTSTRAP/p'
echo "== Stop hook feedback delivered to the model =="
jq -r 'select(.type=="user") | .message.content[]? | select(.type=="text") | .text' "$T" | grep -A6 'Stop hook feedback' 
echo "== model replies =="
jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="text") | .text' "$T"
echo "== notice count in feedback =="; jq -r 'select(.type=="user") | .message.content[]? | select(.type=="text") | .text' "$T" | grep -c 'firstmate fleet lock: this session now holds'
echo "== final state =="; echo "lock=$(cat $HOME_DIR/state/.lock) holder(dead)=$HOLDER pending-notice-file: $( [ -e $HOME_DIR/state/.lock-promotion-notice ] && echo present || echo absent)"; cat "$HOME_DIR/state/arm-ran"
sed -n 's/.*outcome=\([a-z-]*\).*/epoch outcome=\1/p' "$HOME_DIR/state/.claude-autoarm-epoch"
cat "$HOME_DIR/state/.supervision-host.log" 2>/dev/null
