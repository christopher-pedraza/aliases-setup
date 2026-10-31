# DESCRIPTION: NVIDIA GPU helpers: usage table, who is using them, pick a free GPU
# REQUIRES: nvidia-smi

_gpu_q() { # <query-gpu fields>: CSV without header or units
    nvidia-smi --query-gpu="$1" --format=csv,noheader,nounits
}

gpus() {
    # DESC: One line per GPU: utilisation, memory and temperature
    local out
    out=$(_gpu_q index,name,utilization.gpu,memory.used,memory.total,temperature.gpu) || return
    printf '%s\n' "$out" | awk -F', *' '
        BEGIN { printf "%-4s %-26s %5s %17s %5s\n", "GPU", "NAME", "UTIL", "MEMORY (MiB)", "TEMP" }
        { printf "%-4s %-26.26s %4s%% %8s / %-6s %4sC\n", $1, $2, $3, $4, $5, $6 }'
}

gpuwho() {
    # DESC: Who is using the GPUs: GPU, PID, user, memory and command
    local map uuid pid mem idx info
    map=$(_gpu_q index,uuid) || return
    printf '%-4s %-8s %-12s %9s  %s\n' GPU PID USER 'MEM(MiB)' COMMAND
    nvidia-smi --query-compute-apps=gpu_uuid,pid,used_gpu_memory --format=csv,noheader,nounits |
        while IFS=', ' read -r uuid pid mem; do
            [ -n "$pid" ] || continue
            idx=$(printf '%s\n' "$map" | awk -F', *' -v u="$uuid" '$2 == u { print $1 }')
            info=$(ps -o user= -o args= -p "$pid" 2>/dev/null | cut -c1-90)
            printf '%-4s %-8s %-12s %9s  %s\n' "${idx:-?}" "$pid" "${info%% *}" "$mem" "${info#* }"
        done
}

gpufree() {
    # DESC: Indices of idle GPUs, comma separated. Usage: gpufree [count]  (idle = under $GPU_FREE_MB used, default 1000)
    _gpu_q index,memory.used | awk -F', *' -v max="${GPU_FREE_MB:-1000}" -v want="${1:-0}" '
        $2 + 0 < max { ids = ids (ids == "" ? "" : ",") $1; n++; if (want > 0 && n == want) exit }
        END { if (ids == "" || (want > 0 && n < want)) exit 1; print ids }'
}

gpurun() {
    # DESC: Run a command on the first idle GPU(s) via CUDA_VISIBLE_DEVICES. Usage: gpurun [-n count] <command>...
    local want=1 ids
    if [ "$1" = "-n" ]; then want=$2; shift 2 2>/dev/null; fi
    if [ $# -eq 0 ]; then echo "Usage: gpurun [-n count] <command>..." >&2; return 2; fi
    ids=$(gpufree "$want") || { echo "gpurun: fewer than $want idle GPU(s). See: gpus" >&2; return 1; }
    echo "[gpurun] CUDA_VISIBLE_DEVICES=$ids" >&2
    CUDA_VISIBLE_DEVICES=$ids "$@"
}
