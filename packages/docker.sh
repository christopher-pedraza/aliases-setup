# DESCRIPTION: Docker and Compose shortcuts
# REQUIRES: docker

alias dps='docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"' # DESC: Running containers, compact
alias dpsa='docker ps -a --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"' # DESC: All containers, compact
alias dimg='docker images' # DESC: List images
alias dclean='docker system prune' # DESC: Remove stopped containers, dangling images, unused networks
alias dcu='dc up -d' # DESC: Compose up (detached)
alias dcd='dc down' # DESC: Compose down
alias dcl='dc logs -f --tail=100' # DESC: Follow compose logs

dc() {
    # DESC: Docker Compose (v2 plugin or legacy docker-compose). Usage: dc <args>
    if docker compose version >/dev/null 2>&1; then
        docker compose "$@"
    else
        docker-compose "$@"
    fi
}

dex() {
    # DESC: Shell into a container. Usage: dex <container> [shell]
    if [ -z "$1" ]; then echo "Usage: dex <container> [shell]" >&2; return 1; fi
    docker exec -it "$1" "${2:-sh}"
}

dlogs() {
    # DESC: Follow a container's logs. Usage: dlogs <container>
    if [ -z "$1" ]; then echo "Usage: dlogs <container>" >&2; return 1; fi
    docker logs -f --tail=100 "$1"
}

dstopall() {
    # DESC: Stop every running container
    docker ps -q | while read -r id; do docker stop "$id"; done
}
