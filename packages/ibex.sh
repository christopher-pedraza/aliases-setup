# DESCRIPTION: KAUST Ibex: ssh logins (from your computer) and Slurm shortcuts (on the cluster)
# REQUIRES: ssh
#
# $USER in the aliases below is single-quoted so it expands when the command runs.

# --- Connect (run these on your own computer) ---
# Set your KAUST username once, e.g. add this to ~/.bashrc or ~/.zshrc:
#   export IBEX_USER=<your-kaust-id>
_ibex_ssh() { # <host> [ssh options...]
    if [ -z "${IBEX_USER:-}" ]; then
        echo "Set your KAUST username first: export IBEX_USER=<your-kaust-id>  (add it to ~/.bashrc or ~/.zshrc)" >&2
        return 1
    fi
    local host="$1"
    shift
    ssh "$@" "$IBEX_USER@$host"
}

ibex-cpu() {
    # DESC: SSH to the Ibex CPU login node (ilogin). Usage: ibex-cpu [ssh options]
    _ibex_ssh ilogin.ibex.kaust.edu.sa "$@"
}

ibex-gpu() {
    # DESC: SSH to the Ibex GPU login node (glogin). Usage: ibex-gpu [ssh options]
    _ibex_ssh glogin.ibex.kaust.edu.sa "$@"
}

ibex-mover() {
    # DESC: SSH to the Ibex data-mover node, for moving many files. Usage: ibex-mover [ssh options]
    _ibex_ssh mover.ibex.kaust.edu.sa "$@"
}

# --- Queue ---
alias sq='squeue --me -O "JobID:12 ,Partition:12 ,Name:24 ,State:10 ,TimeUsed:11 ,TimeLeft:11 ,NumNodes:6 ,ReasonList"' # DESC: [cyan] Your jobs in the queue (clean view)
alias sq_full='squeue --me -O "JobID:12 ,Partition:12 ,Name:24 ,State:10 ,TimeUsed:11 ,TimeLeft:11 ,NumNodes:6 ,NumCPUs:6 ,MinMemory:11 ,tres-per-node:14 ,QOS:10 ,ReasonList"' # DESC: [cyan] Your jobs with CPUs, memory, GPUs/TRES, and QOS
alias sqs='squeue --me --start --format="%.12i %.12P %.24j %.19S %R"' # DESC: [cyan] Estimated start times for your pending jobs

sqw() {
    # DESC: [cyan] Watch your queue (refreshes every 2s)
    watch -n 2 'squeue --me -O "JobID:12 ,Partition:12 ,Name:24 ,State:10 ,TimeUsed:11 ,TimeLeft:11 ,NumNodes:6 ,ReasonList"'
}

alias sjob='scontrol show job' # DESC: [cyan] Full details of a job. Usage: sjob <job_id>
alias scancelall='scancel -u $USER' # DESC: DANGER: cancel ALL your jobs, running and pending

jobwhy() {
    # DESC: [cyan] Why is a job pending? Usage: jobwhy <job_id>
    if [ -z "$1" ]; then echo "Usage: jobwhy <job_id>" >&2; return 1; fi
    scontrol show job "$1" | grep Reason
}

# --- Interactive sessions ---
alias idebug='srun --partition=debug --gpus=1 --cpus-per-task=4 --mem=16G --time=00:30:00 --pty bash' # DESC: Interactive GPU debug session (30 min)

igpu() {
    # DESC: Interactive GPU session. Usage: igpu [gpus (1)] [constraint (any)] [cores (4)] [mem (32G)] [time (02:00:00)]
    local gpus="${1:-1}"
    local constraint="${2:-}"
    local cores="${3:-4}"
    local mem="${4:-32G}"
    local time="${5:-02:00:00}"
    local gpu_req=""

    # Accepts 'any', 'none', or empty string to skip constraints
    if [ -z "$constraint" ] || [ "$constraint" = "any" ] || [ "$constraint" = "none" ]; then
        echo "Requesting GPU session: $gpus GPU(s) (any), $cores cores, $mem RAM, for $time..."
    else
        gpu_req="--constraint=$constraint"
        echo "Requesting GPU session: $gpus $constraint GPU(s), $cores cores, $mem RAM, for $time..."
    fi

    srun --job-name=interactive_gpu \
         --partition=batch \
         ${gpu_req:+"$gpu_req"} \
         --gpus="$gpus" \
         --cpus-per-task="$cores" \
         --mem="$mem" \
         --time="$time" \
         --pty bash -i
}

icpu() {
    # DESC: Interactive CPU-only session. Usage: icpu [cores (4)] [mem (16G)] [time (02:00:00)]
    local cores="${1:-4}"
    local mem="${2:-16G}"
    local time="${3:-02:00:00}"

    echo "Requesting CPU session: $cores cores, $mem RAM, for $time..."
    srun --job-name=interactive_cpu \
         --partition=batch \
         --cpus-per-task="$cores" \
         --mem="$mem" \
         --time="$time" \
         --pty bash -i
}

# --- Limits and storage ---
slimits() {
    # DESC: [cyan] Show your Slurm limits (falls back to the 'normal' QoS)
    if [ -n "$(sacctmgr -n show association user="$USER" format=Account 2>/dev/null)" ]; then
        sacctmgr show association user="$USER" format=Account,Partition,QOS,GrpTRES,MaxTRESPerJob,MaxWall,MaxJobs
    else
        sacctmgr show qos normal format=Name,MaxTRESPerJob,MaxJobs,MaxWall,GrpTRES
    fi
}

myquota() {
    # DESC: [cyan] Display home and scratch storage summary
    echo "---------------- STORAGE SUMMARY ----------------"
    printf 'HOME:    '
    quota -s | awk '/home/{getline; print $1 " used of " $3}'
    printf 'SCRATCH: '
    df -h "/ibex/user/$USER" | awk 'END{print $3 " used of " $2 " (" $5 ")"}'
    echo "-------------------------------------------------"
}

alias cdscratch='cd /ibex/user/$USER' # DESC: Jump to your Scratch directory
alias diskusage='ncdu' # DESC: [cyan] Interactive disk space explorer

# --- On a compute node ---
alias gpuwatch='watch -n 1 nvidia-smi' # DESC: [cyan] Watch GPU usage (refreshes every 1s)
alias myusage='htop -u $USER' # DESC: [cyan] CPU usage of your processes
