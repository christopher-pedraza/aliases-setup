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
alias sq='squeue --me' # DESC: Your jobs in the queue
alias sqs='squeue --me --start' # DESC: Estimated start times for your pending jobs
alias sqw='watch -n 2 squeue --me' # DESC: Watch your queue (refreshes every 2s)
alias sq_clean='squeue --me --format="%.10i %.15P %.30j %.10T %.10M %.10L %.6D %R"' # DESC: Your jobs with ID, partition, name, state, time, nodes
alias sjob='scontrol show job' # DESC: Full details of a job. Usage: sjob <job_id>
alias scancelall='scancel -u $USER' # DESC: DANGER: cancel ALL your jobs, running and pending

jobwhy() {
    # DESC: Why is a job pending? Usage: jobwhy <job_id>
    if [ -z "$1" ]; then echo "Usage: jobwhy <job_id>" >&2; return 1; fi
    scontrol show job "$1" | grep Reason
}

# --- Interactive sessions ---
alias idebug='srun --partition=debug --gpus=1 --cpus-per-task=4 --mem=16G --time=00:30:00 --pty bash' # DESC: Interactive GPU debug session (30 min)
alias igpu='srun --partition=batch --gpus=1 --cpus-per-task=4 --mem=32G --time=2:00:00 --pty bash' # DESC: Interactive GPU session (2 h)
alias icpu='srun --partition=batch --cpus-per-task=4 --mem=16G --time=2:00:00 --pty bash' # DESC: Interactive CPU-only session (2 h)

# --- Limits and storage ---
slimits() {
    # DESC: Show your Slurm limits (falls back to the 'normal' QoS)
    if [ -n "$(sacctmgr -n show association user="$USER" format=Account 2>/dev/null)" ]; then
        sacctmgr show association user="$USER" format=Account,Partition,QOS,GrpTRES,MaxTRESPerJob,MaxWall,MaxJobs
    else
        sacctmgr show qos normal format=Name,MaxTRESPerJob,MaxJobs,MaxWall,GrpTRES
    fi
}

alias myquota='echo "--- HOME ---"; quota -s; echo ""; echo "--- SCRATCH ---"; df -h /ibex/user/$USER' # DESC: Home and Scratch quotas
alias cdscratch='cd /ibex/user/$USER' # DESC: Jump to your Scratch directory

# --- On a compute node ---
alias gpuwatch='watch -n 1 nvidia-smi' # DESC: Watch GPU usage (refreshes every 1s)
alias myusage='htop -u $USER' # DESC: CPU usage of your processes
