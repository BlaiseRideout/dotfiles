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

# Base URL of the router. $LLAMA_URL points the tools at a remote router (e.g. the desktop over the tailnet);
# unset, they talk to the local service.
llama_base() { if [[ -n ${LLAMA_URL:-} ]]; then echo "${LLAMA_URL%/}"; else echo "http://127.0.0.1:$(llama_port "$@")"; fi; }

# GET /models as JSON. $1 = max seconds (default 5). Fails if the router is not answering.
llama_models() { llama_curl -fsS -m "${1:-5}" "$(llama_base)/models"; }

# Reads /models JSON on stdin; prints the id of the model that is already resident: the loaded one, else a
# sleeping one (idle >240 s, woken by the next request). Prints nothing if none is.
llama_resident_id() {
  jq -r '([.data[] | select(.status.value == "loaded")] + [.data[] | select(.status.value == "sleeping")])[0].id // empty'
}

# Model rows from the router's /models JSON on stdin: id <TAB> state <TAB> ctx (ctx-size from the preset, else
# the model's max). Already-resident models sort first so the top (default) entry avoids a model reload.
llama_model_rows() {
  jq -r '.data | sort_by({loaded: 0, sleeping: 1}[.status.value // ""] // 2) | .[] |
    (.status.args // []) as $a |
    [.id, (.status.value // "?"),
     (( [range(0; $a|length) | select($a[.]=="--ctx-size") | $a[.+1]] | first) // .context_length // 8192 | tostring)] | @tsv'
}

# llama_choose PROMPT ITEM...  → prints the chosen item (fzf, else bash select); returns 1 without a tty or choice
llama_choose() {
  local prompt=$1; shift
  [[ -r /dev/tty ]] || { echo "interactive choice '$prompt' needs a tty" >&2; return 1; }
  if command -v fzf >/dev/null; then
    # fzf reads the list from the pipe and draws on /dev/tty by itself
    printf '%s\n' "$@" | fzf --prompt="$prompt > " --height=~40% --reverse --no-multi \
      --delimiter=$'\t' --tabstop=4
  else
    local PS3="$prompt # " item
    select item in "$@"; do [[ -n ${item:-} ]] && { echo "$item"; break; }; done </dev/tty
  fi
}

# Where the router's API key lives (see `llama-key`). Never commit it, never put it on a command line.
LLAMA_KEY_FILE=${LLAMA_KEY_FILE:-${XDG_STATE_HOME:-$HOME/.local/state}/llama-serve/api-key}

# curl to the router with its API key. The header goes in through a --config pipe, not argv, so it never shows up
# in `ps`. Falls back to plain curl if there is no key file. Use it only for the router, never for other hosts.
llama_curl() {
  if [[ -r $LLAMA_KEY_FILE ]]; then
    curl --config <(printf 'header = "Authorization: Bearer %s"\n' "$(<"$LLAMA_KEY_FILE")") "$@"
  else
    curl "$@"
  fi
}
