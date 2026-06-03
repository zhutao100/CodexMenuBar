#!/usr/bin/env bash
set -euo pipefail

# End-to-end smoke test for the codexd UDS protocol used by CodexMenuBar.
#
# This script:
# - launches `codex app-server codexd run` with a repo-local CODEX_HOME + socket path
# - publishes runtime notifications for regular and delegate turn lifecycles,
#   including a stale duplicate post-turn review completion
# - verifies a subscriber can `codexd/hello`, `codexd/snapshot`, then
#   `codexd/subscribe` with `afterSeq` and receive the replayed `codexd/event` stream
#
# Artifacts:
#   .artifacts/e2e-codexd/<run-id>/{codexd.log,result.json}
#   .artifacts/codexd-e2e.sock

usage() {
  cat <<'EOF'
End-to-end smoke test for the codexd UDS protocol used by CodexMenuBar.

Usage:
  ./scripts/e2e_codexd.sh [--use-codex-on-path]

Options:
  --use-codex-on-path   Launch the installed `codex` binary from PATH instead of
                        building/running from a local `codex` checkout.
EOF
}

USE_CODEX_ON_PATH=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --use-codex-on-path)
      USE_CODEX_ON_PATH=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[e2e_codexd] ERROR: unexpected argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Prefer `config/external-projects.local.yaml` -> external_projects->codex->local_path
# If the file or value is missing, warn and fall back to the repo parent directory.
CODEX_REPO_ROOT=""
CODEX_BIN=""
CODEX_LAUNCH_DESC=""
if [[ "${USE_CODEX_ON_PATH}" == "1" ]]; then
  if ! CODEX_BIN="$(command -v codex)"; then
    echo "[e2e_codexd] ERROR: --use-codex-on-path was set but `codex` was not found in PATH." >&2
    exit 2
  fi
  CODEX_LAUNCH_DESC="PATH codex binary (${CODEX_BIN})"
fi

CONFIG_YAML="${ROOT}/config/external-projects.local.yaml"
if [[ -z "${CODEX_BIN}" && -f "${CONFIG_YAML}" ]]; then
  # Extract the `external_projects.codex.local_path` value. Avoid non-stdlib YAML
  # deps; implement a minimal indentation-aware parser for this one value.
  VAL="$(python3 - "${CONFIG_YAML}" <<'PY'
import re
import sys

path = sys.argv[1]

def strip_quotes(s: str) -> str:
  s = s.strip()
  if len(s) >= 2 and s[0] == s[-1] and s[0] in "\"'":
    return s[1:-1]
  return s

external = False
codex = False
external_indent = -1
codex_indent = -1

for raw in open(path, encoding="utf-8"):
  line = raw.rstrip("\n").rstrip("\r")
  if not line.strip() or line.lstrip().startswith("#"):
    continue

  m = re.match(r"^(\s*)([A-Za-z0-9_-]+)\s*:\s*(.*)$", line)
  if not m:
    continue
  indent, key, rest = m.groups()
  indent_len = len(indent)
  rest = rest.strip()

  if not external:
    if key == "external_projects" and rest == "":
      external = True
      external_indent = indent_len
    continue

  if indent_len <= external_indent:
    external = False
    codex = False
    continue

  if not codex:
    if key == "codex" and rest == "":
      codex = True
      codex_indent = indent_len
    continue

  if indent_len <= codex_indent:
    codex = False
    continue

  if key == "local_path":
    print(strip_quotes(rest))
    sys.exit(0)

print("")
PY
)" || VAL=""
  if [[ -n "${VAL}" ]]; then
    if [[ "${VAL}" == "~"* ]]; then
      VAL="${VAL/#\~/$HOME}"
    fi
    CODEX_REPO_ROOT="${VAL}"
  else
    echo "[e2e_codexd] WARNING: ${CONFIG_YAML} present but external_projects.codex.local_path not found; falling back." >&2
    CODEX_REPO_ROOT="$(cd "${ROOT}/.." && pwd)"
  fi
elif [[ -z "${CODEX_BIN}" ]]; then
  echo "[e2e_codexd] WARNING: ${CONFIG_YAML} not found; falling back to repo parent." >&2
  CODEX_REPO_ROOT="$(cd "${ROOT}/.." && pwd)"
fi

if [[ -z "${CODEX_BIN}" && ! -d "${CODEX_REPO_ROOT}/codex-rs" ]]; then
  echo "[e2e_codexd] ERROR: codex-rs not found under CODEX_REPO_ROOT=${CODEX_REPO_ROOT}" >&2
  echo "[e2e_codexd] HINT: set external_projects.codex.local_path in config/external-projects.local.yaml" >&2
  exit 2
fi

if [[ -z "${CODEX_LAUNCH_DESC}" ]]; then
  CODEX_LAUNCH_DESC="local codex checkout (${CODEX_REPO_ROOT}/codex-rs)"
fi

RUN_ID="$(date -u +"%Y%m%dT%H%M%SZ")"
RUN_DIR="${ROOT}/.artifacts/e2e-codexd/${RUN_ID}"
mkdir -p "${RUN_DIR}"

CODEX_HOME="${RUN_DIR}/codex_home"
SOCKET_PATH="${ROOT}/.artifacts/codexd-e2e.sock"
CODEXD_LOG="${RUN_DIR}/codexd.log"
RESULT_JSON="${RUN_DIR}/result.json"
BRIDGE_TEST_LOG="${RUN_DIR}/menubar_bridge_prompt_test.log"

mkdir -p "${CODEX_HOME}"
mkdir -p "$(dirname "${SOCKET_PATH}")"
rm -f "${SOCKET_PATH}"

cleanup() {
  if [[ -n "${CODEXD_PID:-}" ]]; then
    kill "${CODEXD_PID}" >/dev/null 2>&1 || true
    wait "${CODEXD_PID}" >/dev/null 2>&1 || true
  fi
  rm -f "${SOCKET_PATH}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "[e2e_codexd] runId=${RUN_ID}"
echo "[e2e_codexd] runDir=${RUN_DIR}"
echo "[e2e_codexd] codexHome=${CODEX_HOME}"
echo "[e2e_codexd] socketPath=${SOCKET_PATH}"
echo "[e2e_codexd] launcher=${CODEX_LAUNCH_DESC}"

if [[ -z "${CODEX_BIN}" ]]; then
  echo "[e2e_codexd] checking menubar bridge prompt retention..."
  if ! (
    cd "${CODEX_REPO_ROOT}/codex-rs"
    CODEX_SANDBOX_NETWORK_DISABLED="${CODEX_SANDBOX_NETWORK_DISABLED:-1}" \
      scripts/cargo-local test -p codex-tui \
      publish_event_user_message_item_prompt_preview
  ) >"${BRIDGE_TEST_LOG}" 2>&1; then
    echo "[e2e_codexd] ERROR: menubar bridge prompt retention check failed" >&2
    tail -n 80 "${BRIDGE_TEST_LOG}" >&2 || true
    exit 1
  fi
  if ! grep -Eq 'tests ok \([1-9][0-9]* passed;' "${BRIDGE_TEST_LOG}"; then
    echo "[e2e_codexd] ERROR: menubar bridge prompt retention check did not run" >&2
    tail -n 80 "${BRIDGE_TEST_LOG}" >&2 || true
    exit 1
  fi
fi

echo "[e2e_codexd] starting codexd..."
if [[ -n "${CODEX_BIN}" ]]; then
  (
    cd "${ROOT}"
    CODEX_HOME="${CODEX_HOME}" \
      RUST_LOG="${RUST_LOG:-info}" \
      "${CODEX_BIN}" app-server codexd run --socket-path "${SOCKET_PATH}"
  ) >"${CODEXD_LOG}" 2>&1 &
else
  (
    cd "${CODEX_REPO_ROOT}/codex-rs"
    CODEX_HOME="${CODEX_HOME}" \
      CODEX_SANDBOX_NETWORK_DISABLED="${CODEX_SANDBOX_NETWORK_DISABLED:-1}" \
      RUST_LOG="${RUST_LOG:-info}" \
      scripts/cargo-local run -q -p codex-cli -- app-server codexd run --socket-path "${SOCKET_PATH}"
  ) >"${CODEXD_LOG}" 2>&1 &
fi
CODEXD_PID="$!"

SOCKET_WAIT_SECS="${SOCKET_WAIT_SECS:-120}"
deadline="$((SECONDS + SOCKET_WAIT_SECS))"
while [[ ! -S "${SOCKET_PATH}" ]]; do
  if ((SECONDS >= deadline)); then
    echo "[e2e_codexd] ERROR: codexd socket did not appear within ${SOCKET_WAIT_SECS}s: ${SOCKET_PATH}" >&2
    echo "[e2e_codexd] --- codexd.log (tail) ---" >&2
    tail -n 200 "${CODEXD_LOG}" >&2 || true
    exit 1
  fi
  sleep 0.05
done

echo "[e2e_codexd] socket ready"

python3 - "${SOCKET_PATH}" "${RESULT_JSON}" <<'PY'
import json
import socket
import sys
import time

socket_path = sys.argv[1]
out_json = sys.argv[2]

def send_line(sock, obj):
  line = json.dumps(obj, separators=(",", ":")).encode("utf-8") + b"\n"
  sock.sendall(line)

def recv_line(sock, timeout_s=5.0):
  sock.settimeout(timeout_s)
  buf = bytearray()
  while True:
    b = sock.recv(1)
    if not b:
      raise RuntimeError("socket closed")
    if b == b"\n":
      break
    buf.extend(b)
  return buf.decode("utf-8", errors="strict")

def connect():
  s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
  s.connect(socket_path)
  return s

sub = connect()
send_line(sub, {"id": 1, "method": "codexd/hello", "params": {}})
send_line(sub, {"id": 2, "method": "codexd/snapshot", "params": {}})

hello = None
snapshot = None
events = []
subscribe_response = None

def fail(msg):
  raise SystemExit(msg)

def handle_line(raw):
  global hello, snapshot, subscribe_response
  obj = json.loads(raw)
  if "method" in obj:
    events.append(obj)
    return
  if obj.get("id") == 1:
    hello = obj
    return
  if obj.get("id") == 2:
    snapshot = obj
    return
  if obj.get("id") == 3:
    subscribe_response = obj
    return

while hello is None:
  handle_line(recv_line(sub))

while snapshot is None:
  handle_line(recv_line(sub))

if "result" not in hello:
  fail(f"missing hello result: {hello!r}")

hello_result = hello["result"]
if int(hello_result.get("protocolVersion", 0)) < 1:
  fail(f"unexpected protocolVersion in hello result: {hello_result!r}")
if "eventReplay" not in (hello_result.get("capabilities") or []):
  fail(f"expected eventReplay capability in hello result: {hello_result!r}")

after_seq = int(snapshot["result"]["seq"])

# Publish a small event sequence *before* subscribing so we can validate replay-by-afterSeq.
prod = connect()
runtime_id = "rt-e2e"
thread_id = "thread-e2e"
turn_id = "turn-e2e"
regular_prompt = "Regular prompt carried by the completion notification"
delegate_thread_id = "thread-e2e-review"
delegate_turn_id = "0"
delegate_turn_key = f"{delegate_thread_id}:{delegate_turn_id}"

send_line(prod, {
  "id": 1,
  "method": "codexd/runtime/register",
  "params": {
    "runtimeId": runtime_id,
    "pid": 1,
    "sessionSource": "e2e",
    "cwd": "/",
    "displayName": "e2e",
  },
})
send_line(prod, {
  "id": 2,
  "method": "codexd/runtime/updateState",
  "params": {
    "runtimeId": runtime_id,
    "activeTurns": [{
      "threadId": thread_id,
      "turnId": turn_id,
      "status": "inProgress",
      "startedAt": 1760000000,
      "model": "gpt-5-codex",
      "latestLabel": "Running e2e",
    }],
  },
})
send_line(prod, {
  "id": 3,
  "method": "codexd/runtime/event",
  "params": {
    "runtimeId": runtime_id,
    "notification": {
      "method": "turn/started",
      "params": {
        "threadId": thread_id,
        "turn": {
          "id": turn_id,
          "status": "inProgress",
        },
      },
    },
  },
})
send_line(prod, {
  "id": 4,
  "method": "codexd/runtime/event",
  "params": {
    "runtimeId": runtime_id,
    "notification": {
      "method": "turn/plan/updated",
      "params": {
        "threadId": thread_id,
        "turnId": turn_id,
        "explanation": "e2e plan",
        "plan": [
          {"step": "Inspect bridge", "status": "completed"},
          {"step": "Verify menu bar", "status": "inProgress"},
        ],
      },
    },
  },
})
send_line(prod, {
  "id": 5,
  "method": "codexd/runtime/event",
  "params": {
    "runtimeId": runtime_id,
    "notification": {
      "method": "item/started",
      "params": {
        "threadId": thread_id,
        "turnId": turn_id,
        "item": {
          "type": "fileChange",
          "id": "patch-e2e",
          "changes": [{
            "path": "Sources/App.swift",
            "kind": {"type": "update"},
            "diff": "@@ -1 +1 @@",
          }],
          "status": "inProgress",
        },
      },
    },
  },
})
send_line(prod, {
  "id": 6,
  "method": "codexd/runtime/event",
  "params": {
    "runtimeId": runtime_id,
    "notification": {
      "method": "item/completed",
      "params": {
        "threadId": thread_id,
        "turnId": turn_id,
        "item": {
          "type": "fileChange",
          "id": "patch-e2e",
          "changes": [{
            "path": "Sources/App.swift",
            "kind": {"type": "update"},
            "diff": "@@ -1 +1 @@",
          }],
          "status": "completed",
        },
      },
    },
  },
})
send_line(prod, {
  "id": 7,
  "method": "codexd/runtime/event",
  "params": {
    "runtimeId": runtime_id,
    "notification": {
      "method": "turn/completed",
      "params": {
        "threadId": thread_id,
        "turn": {
          "id": turn_id,
          "status": "completed",
          "promptPreview": regular_prompt,
        },
      },
    },
  },
})
send_line(prod, {
  "id": 8,
  "method": "codexd/runtime/event",
  "params": {
    "runtimeId": runtime_id,
    "notification": {
      "method": "turn/started",
      "params": {
        "threadId": delegate_thread_id,
        "turn": {
          "id": delegate_turn_id,
          "key": delegate_turn_key,
          "status": "inProgress",
          "scope": "delegate",
          "taskKind": "post_turn_completion_review",
          "sessionSource": "subagent_review",
          "subAgentSource": "review",
          "parentTurnId": turn_id,
          "threadName": "Post-turn review",
          "model": "gpt-5-review",
        },
      },
    },
  },
})
send_line(prod, {
  "id": 9,
  "method": "codexd/runtime/event",
  "params": {
    "runtimeId": runtime_id,
    "notification": {
      "method": "thread/tokenUsage/updated",
      "params": {
        "threadId": delegate_thread_id,
        "turnKey": delegate_turn_key,
        "tokenUsage": {
          "modelContextWindow": 128000,
          "last": {
            "inputTokens": 3400,
            "cachedInputTokens": 1300,
            "outputTokens": 520,
            "reasoningOutputTokens": 180,
            "totalTokens": 3920,
          },
          "total": {
            "inputTokens": 5500,
            "cachedInputTokens": 2200,
            "outputTokens": 940,
            "reasoningOutputTokens": 300,
            "totalTokens": 6440,
          },
        },
      },
    },
  },
})
send_line(prod, {
  "id": 10,
  "method": "codexd/runtime/event",
  "params": {
    "runtimeId": runtime_id,
    "notification": {
      "method": "turn/completed",
      "params": {
        "threadId": delegate_thread_id,
        "turn": {
          "id": delegate_turn_id,
          "key": delegate_turn_key,
          "status": "completed",
        },
      },
    },
  },
})
send_line(prod, {
  "id": 11,
  "method": "codexd/runtime/event",
  "params": {
    "runtimeId": runtime_id,
    "notification": {
      "method": "turn/completed",
      "params": {
        "turn": {
          "id": delegate_turn_id,
          "key": f"stale-{delegate_turn_key}",
          "status": "completed",
        },
      },
    },
  },
})

# Wait for the last producer ack to ensure events are applied before we subscribe.
deadline = time.time() + 5.0
acked = False
while time.time() < deadline:
  obj = json.loads(recv_line(prod, timeout_s=1.0))
  if obj.get("id") == 11:
    if "result" not in obj:
      fail(f"missing producer result: {obj!r}")
    acked = True
    break
if not acked:
  fail("timed out waiting for producer ack")
prod.close()

send_line(sub, {"id": 3, "method": "codexd/subscribe", "params": {"afterSeq": after_seq}})

deadline = time.time() + 5.0
while time.time() < deadline and (subscribe_response is None or len(events) < 10):
  handle_line(recv_line(sub, timeout_s=1.0))

sub.close()

if subscribe_response is None or "result" not in subscribe_response:
  fail(f"missing subscribe response: {subscribe_response!r}")

codexd_events = [e for e in events if e.get("method") == "codexd/event"]
if not codexd_events:
  fail(f"expected codexd/event notifications, got: {events!r}")

if len(codexd_events) < 10:
  fail(f"expected >= 10 codexd/event notifications, got {len(codexd_events)}: {codexd_events!r}")

def event_seq(e):
  try:
    return int((e.get("params") or {}).get("seq"))
  except Exception:
    return -1

seqs = [event_seq(e) for e in codexd_events]
if any(s <= after_seq for s in seqs):
  fail(f"expected all event seq values > afterSeq={after_seq}, got: {seqs!r}")
if seqs != sorted(seqs):
  fail(f"expected events in increasing seq order, got: {seqs!r}")

upserts = []
state_upsert_seen = False
delegate_upsert_seen = False
delegate_token_upsert_seen = False
delegate_token_key_only_notification_seen = False
regular_completion_prompt_seen = False
delegate_completion_seen = False
stale_duplicate_delegate_completion_seen = False
notifs = []
notif_methods = []
for e in codexd_events:
  params = e.get("params") or {}
  payload = params.get("event") or {}
  typ = payload.get("type")
  if typ == "runtimeUpsert":
    runtime = payload.get("runtime") or {}
    payload_runtime_id = runtime.get("runtimeId") or runtime.get("runtime_id")
    if payload_runtime_id != runtime_id:
      fail(f"runtimeUpsert runtimeId mismatch: {payload_runtime_id!r} != {runtime_id!r}")
    active_turns = runtime.get("activeTurns") or []
    for active_turn in active_turns:
      if (
        active_turn.get("turnId") == turn_id
        and active_turn.get("latestLabel") == "Running e2e"
        and active_turn.get("model") == "gpt-5-codex"
      ):
        state_upsert_seen = True
      if (
        active_turn.get("turnId") == delegate_turn_id
        and active_turn.get("turnKey") == delegate_turn_key
        and active_turn.get("scope") == "delegate"
        and active_turn.get("taskKind") == "post_turn_completion_review"
        and active_turn.get("parentTurnId") == turn_id
      ):
        delegate_upsert_seen = True
        token_usage = active_turn.get("tokenUsage") or {}
        last_usage = token_usage.get("last") or {}
        if last_usage.get("inputTokens") == 3400:
          delegate_token_upsert_seen = True
    upserts.append(e)
  if typ == "runtimeNotification":
    payload_runtime_id = payload.get("runtimeId") or payload.get("runtime_id")
    if payload_runtime_id != runtime_id:
      fail(f"runtimeNotification runtimeId mismatch: {payload_runtime_id!r} != {runtime_id!r}")
    notification = payload.get("notification") or {}
    notif_methods.append(notification.get("method"))
    if notification.get("method") == "turn/completed":
      notification_params = notification.get("params") or {}
      turn = notification_params.get("turn") or {}
      if (
        notification_params.get("threadId") == thread_id
        and turn.get("id") == turn_id
        and turn.get("promptPreview") == regular_prompt
      ):
        regular_completion_prompt_seen = True
      if (
        notification_params.get("threadId") == delegate_thread_id
        and turn.get("id") == delegate_turn_id
        and turn.get("key") == delegate_turn_key
      ):
        delegate_completion_seen = True
      if (
        "threadId" not in notification_params
        and turn.get("id") == delegate_turn_id
        and turn.get("key") == f"stale-{delegate_turn_key}"
      ):
        stale_duplicate_delegate_completion_seen = True
    if notification.get("method") == "thread/tokenUsage/updated":
      notification_params = notification.get("params") or {}
      if (
        notification_params.get("threadId") == delegate_thread_id
        and "turnId" not in notification_params
        and notification_params.get("turnKey") == delegate_turn_key
      ):
        delegate_token_key_only_notification_seen = True
    notifs.append(e)

if not upserts:
  fail(f"expected runtimeUpsert in {len(codexd_events)} events")
if not state_upsert_seen:
  fail("expected runtime/updateState active turn summary in runtimeUpsert events")
if not delegate_upsert_seen:
  fail("expected delegate active turn summary with turnKey in runtimeUpsert events")
if not delegate_token_upsert_seen:
  fail("expected delegate token usage to update the keyed active turn")
if not delegate_token_key_only_notification_seen:
  fail("expected delegate token usage notification to be keyed by turnKey without turnId")
if not notifs:
  fail(f"expected runtimeNotification in {len(codexd_events)} events")
if "turn/started" not in notif_methods:
  fail(f"expected turn/started notification in runtimeNotification events, got: {notif_methods!r}")
if "turn/plan/updated" not in notif_methods:
  fail(f"expected turn/plan/updated notification in runtimeNotification events, got: {notif_methods!r}")
if "item/started" not in notif_methods:
  fail(f"expected item/started notification in runtimeNotification events, got: {notif_methods!r}")
if "item/completed" not in notif_methods:
  fail(f"expected item/completed notification in runtimeNotification events, got: {notif_methods!r}")
if notif_methods.count("turn/completed") < 3:
  fail(f"expected regular, delegate, and duplicate delegate turn/completed notifications, got: {notif_methods!r}")
if not regular_completion_prompt_seen:
  fail("expected regular turn/completed notification to carry promptPreview")
if not delegate_completion_seen:
  fail("expected keyed delegate turn/completed notification")
if not stale_duplicate_delegate_completion_seen:
  fail("expected stale duplicate delegate turn/completed notification without threadId")

subscribe_seq = int(subscribe_response["result"]["seq"])
if max(seqs) > subscribe_seq:
  fail(f"expected max(event.seq) <= subscribeSeq={subscribe_seq}, got: {seqs!r}")

out = {
  "hello": hello_result,
  "snapshotSeq": after_seq,
  "subscribeSeq": subscribe_seq,
  "eventCount": len(codexd_events),
  "eventSeqs": seqs,
  "eventTypes": [e.get("params", {}).get("event", {}).get("type") for e in codexd_events],
  "runtimeNotificationMethods": notif_methods,
  "regularCompletionPromptSeen": regular_completion_prompt_seen,
}

with open(out_json, "w", encoding="utf-8") as f:
  json.dump(out, f, indent=2, sort_keys=True)

print("[e2e_codexd] PASS")
PY

echo "[e2e_codexd] wrote ${RESULT_JSON}"
echo "[e2e_codexd] PASS"
