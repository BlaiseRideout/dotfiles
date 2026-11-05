# shellcheck shell=bash
# Helpers shared by the llama.cpp router tools: sbx-llama, llama-state, llama-current-model, llama-ask and
# opencode-llama-sync. Sourced, never run: `. "${LLAMA_LIB:-$HOME/.local/lib/llama.sh}"`.

LLAMA_SERVICE=${LLAMA_SERVICE:-llama-serve.service}
LLAMA_FALLBACK_PORT=9931
# Written by `llama-state save` when the service stops; read back by `llama-state restore` and llama-current-model.
LLAMA_LAST_MODEL_FILE=${XDG_STATE_HOME:-$HOME/.local/state}/llama-serve/last-model

# The router's port: $LLAMA_PORT, else the port the service's main process listens on (the unit may bind an
# arbitrary one), else 9931. An optional argument is the service's main PID (ExecStop knows it before systemd does).
llama_port() {
  [[ -n ${LLAMA_PORT:-} ]] && { echo "$LLAMA_PORT"; return; }
  local pid=${1:-} p=""
  [[ -n $pid && $pid != 0 ]] || pid=$(systemctl --user show -p MainPID --value "$LLAMA_SERVICE" 2>/dev/null)
  [[ -n $pid && $pid != 0 ]] && p=$(ss -ltnpH 2>/dev/null |
    awk -v pat="pid=$pid," '$0 ~ pat {n=split($4,a,":"); print a[n]; exit}')
  echo "${p:-$LLAMA_FALLBACK_PORT}"
}

llama_base() { echo "http://127.0.0.1:$(llama_port "$@")"; }

# GET /models as JSON. $1 = max seconds (default 5). Fails if the router is not answering.
llama_models() { curl -fsS -m "${1:-5}" "$(llama_base)/models"; }

# Reads /models JSON on stdin; prints the id of the model that is already resident: the loaded one, else a
# sleeping one (idle >240 s, woken by the next request). Prints nothing if none is.
llama_resident_id() {
  jq -r '([.data[] | select(.status.value == "loaded")] + [.data[] | select(.status.value == "sleeping")])[0].id // empty'
}
