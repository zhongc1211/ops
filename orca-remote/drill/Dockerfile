# Linux userland for the watchdog drill (watchdog.sh needs /proc, GNU date/stat, flock, pgrep, tmux).
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends bash curl python3 procps tmux util-linux psmisc ca-certificates \
 && rm -rf /var/lib/apt/lists/*
