#!/usr/bin/env bash
set -euo pipefail

# End-to-end smoke test for the codexd UDS protocol used by CodexMenuBar.
#
# This script:
# - launches `codex app-server codexd run` with a repo-local CODEX_HOME + socket path
# - publishes a small set of runtime notifications (register + turn started/completed)
# - verifies a subscriber can `codexd/snapshot`, then `codexd/subscribe` with `afterSeq`
#   and receive the replayed `codexd/event` stream
#
# Artifacts:
#   .artifacts/e2e-codexd/<run-id>/{codexd.log,result.json}
#   .artifacts/codexd-e2e.sock

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Prefer `config/external-projects.local.yaml` -> external_projects->codex->local_path
# If the file or value is missing, warn and fall back to the repo parent directory.
CODEX_REPO_ROOT=""
CONFIG_YAML="${ROOT}/config/external-projects.local.yaml"
if [[ -f "${CONFIG_YAML}" ]]; then
  # Extract the `local_path` under the `codex` section. This uses sed to limit
  # to the codex subsection and then pulls the local_path value, trimming
  # optional surrounding quotes.
  VAL=$(sed -n '/^[[:space:]]*codex:/,/^[[:space:]]*[a-zA-Z0-9_\-]\+:/p' "${CONFIG_YAML}" \
    | sed -n 's/^[[:space:]]*local_path:[[:space:]]*"\?\(.*\)"\?$/\1/p' | tr -d '\r') || VAL=""
  if [[ -n "${VAL}" ]]; then
    CODEX_REPO_ROOT="${VAL}"
  else
    echo "[e2e_codexd] WARNING: ${CONFIG_YAML} present but external_projects.codex.local_path not found; falling back." >&2
    CODEX_REPO_ROOT="$(cd "${ROOT}/.." && pwd)"
  fi
else
  echo "[e2e_codexd] WARNING: ${CONFIG_YAML} not found; falling back to repo parent." >&2
  CODEX_REPO_ROOT="$(cd "${ROOT}/.." && pwd)"
fi

RUN_ID="$(date -u +"%Y%m%dT%H%M%SZ")"
RUN_DIR="${ROOT}/.artifacts/e2e-codexd/${RUN_ID}"
mkdir -p "${RUN_DIR}"

CODEX_HOME="${RUN_DIR}/codex_home"
SOCKET_PATH="${ROOT}/.artifacts/codexd-e2e.sock"
CODEXD_LOG="${RUN_DIR}/codexd.log"
RESULT_JSON="${RUN_DIR}/result.json"

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

echo "[e2e_codexd] starting codexd..."
(
  cd "${CODEX_REPO_ROOT}/codex-rs"
  CODEX_HOME="${CODEX_HOME}" \
    RUST_LOG="${RUST_LOG:-info}" \
    cargo run -q -p codex-cli -- app-server codexd run --socket-path "${SOCKET_PATH}"
) >"${CODEXD_LOG}" 2>&1 &
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
send_line(sub, {"id": 1, "method": "codexd/snapshot", "params": {}})

snapshot = None
events = []
subscribe_response = None

def handle_line(raw):
  global snapshot, subscribe_response
  obj = json.loads(raw)
  if "method" in obj:
    events.append(obj)
    return
  if obj.get("id") == 1:
    snapshot = obj
    return
  if obj.get("id") == 2:
    subscribe_response = obj
    return

while snapshot is None:
  handle_line(recv_line(sub))

after_seq = int(snapshot["result"]["seq"])

# Publish a small event sequence *before* subscribing so we can validate replay-by-afterSeq.
prod = connect()
runtime_id = "rt-e2e"
thread_id = "thread-e2e"
turn_id = "turn-e2e"

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
  "id": 3,
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
  if obj.get("id") == 3:
    if "result" not in obj:
      fail(f"missing producer result: {obj!r}")
    acked = True
    break
if not acked:
  fail("timed out waiting for producer ack")
prod.close()

send_line(sub, {"id": 2, "method": "codexd/subscribe", "params": {"afterSeq": after_seq}})

deadline = time.time() + 5.0
while time.time() < deadline and (subscribe_response is None or len(events) < 3):
  handle_line(recv_line(sub, timeout_s=1.0))

sub.close()

def fail(msg):
  raise SystemExit(msg)

if subscribe_response is None or "result" not in subscribe_response:
  fail(f"missing subscribe response: {subscribe_response!r}")

codexd_events = [e for e in events if e.get("method") == "codexd/event"]
if not codexd_events:
  fail(f"expected codexd/event notifications, got: {events!r}")

if len(codexd_events) < 3:
  fail(f"expected >= 3 codexd/event notifications, got {len(codexd_events)}: {codexd_events!r}")

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
    upserts.append(e)
  if typ == "runtimeNotification":
    payload_runtime_id = payload.get("runtimeId") or payload.get("runtime_id")
    if payload_runtime_id != runtime_id:
      fail(f"runtimeNotification runtimeId mismatch: {payload_runtime_id!r} != {runtime_id!r}")
    notification = payload.get("notification") or {}
    notif_methods.append(notification.get("method"))
    notifs.append(e)

if not upserts:
  fail(f"expected runtimeUpsert in {len(codexd_events)} events")
if not notifs:
  fail(f"expected runtimeNotification in {len(codexd_events)} events")
if "turn/started" not in notif_methods:
  fail(f"expected turn/started notification in runtimeNotification events, got: {notif_methods!r}")
if "turn/completed" not in notif_methods:
  fail(f"expected turn/completed notification in runtimeNotification events, got: {notif_methods!r}")

subscribe_seq = int(subscribe_response["result"]["seq"])
if max(seqs) > subscribe_seq:
  fail(f"expected max(event.seq) <= subscribeSeq={subscribe_seq}, got: {seqs!r}")

out = {
  "snapshotSeq": after_seq,
  "subscribeSeq": subscribe_seq,
  "eventCount": len(codexd_events),
  "eventSeqs": seqs,
  "eventTypes": [e.get("params", {}).get("event", {}).get("type") for e in codexd_events],
  "runtimeNotificationMethods": notif_methods,
}

with open(out_json, "w", encoding="utf-8") as f:
  json.dump(out, f, indent=2, sort_keys=True)

print("[e2e_codexd] PASS")
PY

echo "[e2e_codexd] wrote ${RESULT_JSON}"
echo "[e2e_codexd] PASS"
