#!/bin/bash
# Waybar module: llama.cpp token rate. Continuous exec — prints one JSON line a second.
#   generating  live tokens/s while a request runs (n_decoded from /slots, sampled each second)
#   last        rate of the most recent request (/metrics counters), held for LLAMA_TOKPS_HOLD seconds
#   idle        lifetime average generation rate
# Hidden unless a model is loaded. Needs llama-serve.service to run with --metrics.
# The router keeps /slots and /metrics per model, so every loaded model is sampled and summed.
export LC_ALL=C

SERVICE=llama-serve.service
HOLD=${LLAMA_TOKPS_HOLD:-15}
ICON=$''

find_port() {
    [[ -n ${LLAMA_PORT:-} ]] && { echo "$LLAMA_PORT"; return; }
    local pid p=""
    pid=$(systemctl --user show -p MainPID --value "$SERVICE" 2>/dev/null)
    [[ -n $pid && $pid != 0 ]] && p=$(ss -ltnpH 2>/dev/null |
        awk -v pat="pid=$pid," '$0 ~ pat {n=split($4,a,":"); print a[n]; exit}')
    echo "${p:-9931}"
}
# The bar shows whole tokens/s, padded with figure spaces (as wide as a digit) to two digits
# (a model is assumed to stay under 100 t/s); the tooltip keeps a decimal. Bytes rather than \u
# so it doesn't depend on the locale
int()    { local s; printf -v s '%2.0f' "$1"; printf '%s' "${s// /$'\xe2\x80\x87'}"; }
# Stand-in for the number while there isn't one (reading the prompt, no stats yet): three middle
# dots with six-per-em spaces and a trailing hair space. It's as wide as two digits once Pango has
# rounded each glyph (measured on the bar; the plain font metrics suggest otherwise), so the module
# doesn't resize, and shift everything else, when it replaces a reading
DOTS=$'\xc2\xb7\xe2\x80\x86\xc2\xb7\xe2\x80\x86\xc2\xb7\xe2\x80\x8a'
emit()   { last_json=$(jq -nc --arg text "$1" --arg tip "$2" --arg class "$3" '{text: $text, tooltip: $tip, class: $class}'); echo "$last_json"; }
hidden() { last_json=""; echo '{"text": "", "class": "hidden"}'; }

declare -A prev_n=()
PORT=$(find_port)
prev_t=$EPOCHREALTIME
active=0 last_rate="" last_at=0 idle_tok=0 idle_sec=0
last_json="" fails=0
FAILS_BEFORE_HIDING=3   # polls (2s apart) that may fail in a row before the module disappears

while :; do
    # Waybar leaves continuous scripts running when it restarts or reloads; once the parent shell is
    # gone we're reparented to init, so stop (orphaned copies each polled the server every second)
    [[ $(ps -o ppid= -p $$ 2>/dev/null | tr -d ' ') == 1 ]] && exit 0
    BASE=http://127.0.0.1:$PORT
    if ! models=$(curl -fsS -m 2 "$BASE/models" 2>/dev/null); then
        # A busy server can miss a poll; keep the last reading up on a brief failure, since hiding
        # the module shifts everything beside it
        PORT=$(find_port); prev_n=(); active=0
        if ((++fails <= FAILS_BEFORE_HIDING)) && [[ -n $last_json ]]; then echo "$last_json"; else hidden; fi
        sleep 2; continue
    fi
    fails=0
    mapfile -t loaded < <(jq -r '.data[] | select(.status.value == "loaded") | .id' <<<"$models")
    if ((${#loaded[@]} == 0)); then hidden; prev_n=(); active=0; sleep 1; continue; fi

    now=$EPOCHREALTIME
    live_tok=0 busy=0 prefill=0 mrows=()
    declare -A cur=()
    for m in "${loaded[@]}"; do
        q=$(jq -rn --arg m "$m" '$m | @uri')
        while IFS=$'\t' read -r id n; do
            [[ -n $id ]] || continue
            busy=$((busy + 1)); k="$m|$id"; cur[$k]=$n
            [[ -n ${prev_n[$k]:-} ]] && ((n >= prev_n[$k])) && live_tok=$((live_tok + n - prev_n[$k]))
            ((n == 0)) && prefill=$((prefill + 1))
        done < <(curl -fsS -m 2 "$BASE/slots?model=$q&autoload=false" 2>/dev/null |
                 jq -r '.[]? | select(.is_processing) | [.id, (.next_token[0].n_decoded? // 0)] | @tsv')
        mrows+=("$(curl -fsS -m 2 "$BASE/metrics?model=$q&autoload=false" 2>/dev/null | awk '
            $1 == "llamacpp:tokens_predicted_total"         {a = $2}
            $1 == "llamacpp:tokens_predicted_seconds_total" {b = $2}
            $1 == "llamacpp:prompt_tokens_total"            {c = $2}
            $1 == "llamacpp:prompt_seconds_total"           {d = $2}
            END {print a + 0, b + 0, c + 0, d + 0}')")
    done
    prev_n=(); for k in "${!cur[@]}"; do prev_n[$k]=${cur[$k]}; done
    unset cur

    read -r tok_total sec_total ptok psec < <(printf '%s\n' "${mrows[@]}" | awk '{a+=$1; b+=$2; c+=$3; d+=$4} END {print a, b, c, d}')
    dt=$(awk -v n="$now" -v p="$prev_t" 'BEGIN {d = n - p; print (d > 0.05 ? d : 1)}'); prev_t=$now

    avg=$(awk -v t="$tok_total" -v s="$sec_total" 'BEGIN {if (s > 0) printf "%.1f", t / s}')
    pavg=$(awk -v t="$ptok" -v s="$psec" 'BEGIN {if (s > 0) printf "%.1f", t / s}')

    if ((busy > 0)); then
        active=1
        if ((live_tok > 0)); then
            live=$(awk -v t="$live_tok" -v d="$dt" 'BEGIN {printf "%.1f", t / d}')
            text="$ICON  $(int "$live") t/s"; class=generating; now_line="now: $live t/s"
        else
            text="$ICON  $DOTS t/s"; class=prefill; now_line="now: reading the prompt"
        fi
    else
        if ((active)); then   # a request just finished: its rate is the counters' delta since we last saw it idle
            last_rate=$(awk -v t="$tok_total" -v t0="$idle_tok" -v s="$sec_total" -v s0="$idle_sec" \
                'BEGIN {if (s - s0 > 0 && t - t0 > 0) printf "%.1f", (t - t0) / (s - s0)}')
            last_at=$SECONDS; active=0
        fi
        idle_tok=$tok_total idle_sec=$sec_total
        now_line="idle"
        if [[ -n $last_rate ]] && ((SECONDS - last_at < HOLD)); then
            text="$ICON  $(int "$last_rate") t/s"; class=last
        elif [[ -n $avg ]]; then
            text="$ICON  $(int "$avg") t/s"; class=idle
        else
            text="$ICON  $DOTS t/s"; class=idle
        fi
    fi

    tip="llama.cpp: ${loaded[*]}"$'\n'"$now_line"
    [[ -n $last_rate ]] && tip+=$'\n'"last request: $last_rate t/s"
    [[ -n $avg ]]  && tip+=$'\n'"average generation: $avg t/s"
    [[ -n $pavg ]] && tip+=$'\n'"average prompt processing: $pavg t/s"
    tip+=$'\n'"busy slots: $busy"
    emit "$text" "$tip" "$class"
    sleep 1
done
