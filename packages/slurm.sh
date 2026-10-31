# DESCRIPTION: Slurm cluster helpers: job history, efficiency, free nodes, follow a job's output
# REQUIRES: sinfo sacct scontrol
#
# Generic Slurm. The `ibex` package has queue shortcuts (sq, sqs, sjob, ...) and
# interactive-session aliases; these are complementary and use different names.

shist() {
    # DESC: Your jobs from the last N days (default 1) with state, exit code and run time. Usage: shist [days]
    sacct -u "${USER:-$(id -un)}" -X -S "now-${1:-1}days" \
        --format=JobID%14,JobName%26,Partition%12,State%14,ExitCode,Elapsed,Start
}

sjeff() {
    # DESC: How well a finished job used its CPU and memory. Usage: sjeff <job_id>
    if [ -z "$1" ]; then echo "Usage: sjeff <job_id>" >&2; return 1; fi
    if command -v seff >/dev/null 2>&1; then
        seff "$1"
    else
        sacct -j "$1" --format=JobID%14,State,Elapsed,AllocCPUS,TotalCPU,ReqMem,MaxRSS,MaxVMSize
    fi
}

snodes() {
    # DESC: Partitions with their state, time limit, node count, CPUs, memory and GPUs
    sinfo -o '%.16P %.6a %.11l %.6D %.9T %.6c %.9m %G'
}

sfree() {
    # DESC: Nodes that have room now (idle or mixed): CPUs allocated/idle/other/total and GPUs
    sinfo -N -t idle,mix -o '%.20N %.14P %.6t %.14C %G'
}

slog() {
    # DESC: Follow a job's output file (tail -f). Usage: slog <job_id>
    if [ -z "$1" ]; then echo "Usage: slog <job_id>" >&2; return 1; fi
    local out
    out=$(scontrol show job "$1" 2>/dev/null | awk '/^ *StdOut=/ { sub(/^ *StdOut=/, ""); print; exit }')
    if [ -z "$out" ]; then echo "slog: no such job, or Slurm no longer remembers it ($1)" >&2; return 1; fi
    if [ ! -e "$out" ]; then echo "slog: $out doesn't exist yet (job still pending?)" >&2; return 1; fi
    echo "[slog] $out" >&2
    tail -n 50 -f "$out"
}
