#!/bin/bash
# Headless Terrain Diffusion pre-gen orchestrator.
#
# Boots the Fabric 1.21.1 server with TD-MC, dispatches a Chunky pre-gen task,
# monitors the server log, and stops the server cleanly when "Task finished"
# appears. Re-runnable: Chunky resumes interrupted tasks automatically.
#
# Usage: bash run-pregen.sh [radius]   (default radius 2500 = 5000x5000)

set -euo pipefail

RADIUS="${1:-2500}"
WORKDIR="$HOME/minecraft/td-pregen/data"
JAVA_HOME="$HOME/.local/jdk/jdk-21.0.11+10"
JAVA="$JAVA_HOME/bin/java"
CONDA_ENV="$HOME/miniconda3/envs/td-pregen"

ORCH_LOG="$WORKDIR/../orchestrator.log"
SERVER_LOG="$WORKDIR/logs/latest.log"
FIFO="$WORKDIR/.server-stdin"

log() { echo "[$(date -Is)] $*" | tee -a "$ORCH_LOG"; }

cd "$WORKDIR"
mkdir -p logs
# Truncate latest.log so we never match stale content from previous runs.
: > "$SERVER_LOG"
# Clear any persisted Chunky task — otherwise the server prompts for /chunky confirm.
rm -rf "$WORKDIR/config/chunky/tasks"

# CUDA runtime libs (cudart, cuDNN) for ONNX GPU inference
if [ -d "$CONDA_ENV/lib" ]; then
  export LD_LIBRARY_PATH="$CONDA_ENV/lib:${LD_LIBRARY_PATH:-}"
  log "CUDA libs from conda env: $CONDA_ENV/lib"
else
  log "WARNING: conda env $CONDA_ENV not found; ONNX may fall back to CPU"
fi

# Ensure clean FIFO
rm -f "$FIFO"
mkfifo "$FIFO"

log "Launching Fabric server (Xmx=6G, pre-gen radius=$RADIUS)"

# Launch with FIFO as stdin
"$JAVA" -Xmx6G -jar server.jar nogui < "$FIFO" &
SERVER_PID=$!

# Open FIFO write end and keep it open for the duration
exec 3>"$FIFO"

cleanup() {
  log "Cleanup: closing server"
  echo "stop" >&3 2>/dev/null || true
  exec 3>&- 2>/dev/null || true
  rm -f "$FIFO"
  wait "$SERVER_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

log "Waiting for server ready..."
DEADLINE=$(($(date +%s) + 600))   # 10 min to come up
while ! grep -q 'Done.*For help, type' "$SERVER_LOG" 2>/dev/null; do
  sleep 5
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    log "FATAL: Server died before becoming ready. See $SERVER_LOG"
    exit 1
  fi
  if [ "$(date +%s)" -gt "$DEADLINE" ]; then
    log "FATAL: Server did not become ready within 10 minutes"
    exit 1
  fi
done
log "Server ready"

# Issue Chunky pre-gen task
log "Dispatching Chunky pre-gen: world=overworld, center=0,0, radius=$RADIUS"
{
  echo "chunky world minecraft:overworld"
  echo "chunky center 0 0"
  echo "chunky radius $RADIUS"
  echo "chunky start"
} >&3

# Monitor for completion. Chunky logs progress every minute or so.
log "Pre-gen running. Tail server log for progress: tail -f $SERVER_LOG"
LAST_PROGRESS=""
while ! grep -qE "Task (finished|completed|done)" "$SERVER_LOG" 2>/dev/null; do
  sleep 60
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    log "FATAL: Server died during pre-gen. See $SERVER_LOG"
    exit 1
  fi
  PROGRESS=$(grep -E "%|Chunks:|chunks/s|Estimated" "$SERVER_LOG" | tail -1 || true)
  if [ -n "$PROGRESS" ] && [ "$PROGRESS" != "$LAST_PROGRESS" ]; then
    log "$PROGRESS"
    LAST_PROGRESS="$PROGRESS"
  fi
done

log "Pre-gen complete. Stopping server cleanly."
echo "stop" >&3
wait "$SERVER_PID"
log "Server stopped. World ready at $WORKDIR/world/"
