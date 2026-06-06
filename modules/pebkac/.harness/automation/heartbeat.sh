#!/bin/bash
# PEBKAC Harness Heartbeat
# Check session health and checkpoint age.

SCRIPT="${BASH_SOURCE[0]}"
AUTOMATION_DIR="$(cd "$(dirname "$SCRIPT")" && pwd)"
HARNESS_DIR="$(dirname "$AUTOMATION_DIR")"

if [ -n "${HARNESS_DIR_OVERRIDE:-}" ]; then
  HARNESS_DIR="$HARNESS_DIR_OVERRIDE"
fi

STATE_DIR="${HARNESS_DIR}/state"
mkdir -p "$STATE_DIR" 2>/dev/null || true

VAULT_CONFIG="${HARNESS_DIR}/vault/config.yaml"
if [ -f "$VAULT_CONFIG" ]; then
  echo "[heartbeat] Vault config: OK"
elif [ -f "${HARNESS_DIR}/config.yaml" ]; then
  echo "[heartbeat] Vault config: not configured"
else
  echo "[heartbeat] Vault config: MISSING"
fi

LATEST="${HARNESS_DIR}/checkpoints/latest.json"
if [ -f "$LATEST" ]; then
  MTIME=$(stat -f %m "$LATEST" 2>/dev/null || stat -c %Y "$LATEST" 2>/dev/null || echo 0)
  AGE=$(( $(date +%s) - MTIME ))
  if [ "$AGE" -gt 3600 ]; then
    echo "[heartbeat] Checkpoint: STALE (${AGE}s old)"
  else
    echo "[heartbeat] Checkpoint: OK (${AGE}s old)"
  fi
else
  echo "[heartbeat] Checkpoint: NONE"
fi

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "${STATE_DIR}/last-heartbeat.txt"
echo "[heartbeat] $(date -u +%Y-%m-%dT%H:%M:%SZ) complete"
