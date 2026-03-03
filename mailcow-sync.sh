#!/bin/bash

# --- Configuration ---
TARGET_SERVER="84.38.255.23"
TARGET_USER="ubuntu"
MAILCOW_DIR="/opt/mailcow-dockerized"
DOCKER_VOLUMES="/var/lib/docker/volumes"
EXCLUDES="--exclude rspamd-vol-1 --exclude backingFsBlockDev --exclude metadata.db"
SSH_PORT=22
SSH_KEY="/root/.ssh/id_ed25519_mailcow"
PUSHOVER_API_KEY=""
PUSHOVER_USER_KEY=""
LOG_FILE="/var/log/sync_mailcow.log"

RSYNC_ERR_LOG="/tmp/sync_mailcow_rsync_error.log"

# --- Functions ---
send_pushover_notification() {
    if [ -n "$PUSHOVER_API_KEY" ] && [ -n "$PUSHOVER_USER_KEY" ]; then
        curl -s \
            --form-string "token=$PUSHOVER_API_KEY" \
            --form-string "user=$PUSHOVER_USER_KEY" \
            --form-string "message=$1" \
            https://api.pushover.net/1/messages.json > /dev/null
    else
        log "Pushover keys not set, skipping notification."
    fi
}

log() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

handle_error() {
    local exit_code=$?
    local last_command="$1"
    log "ERROR: Command '$last_command' failed with exit code $exit_code."
    if [[ -s "$RSYNC_ERR_LOG" ]]; then
        local specific_error=$(head -n 5 "$RSYNC_ERR_LOG")
        log "Specific Error Details: $specific_error"
        send_pushover_notification "Mailcow Sync Error: '$last_command' failed. Details: $specific_error"
    else
        log "No specific rsync error details captured in $RSYNC_ERR_LOG."
        send_pushover_notification "Mailcow Sync Error: '$last_command' failed (Exit Code: $exit_code)."
    fi
    rm -f "$RSYNC_ERR_LOG"
    exit 1
}

trap 'handle_error "$BASH_COMMAND"' ERR

# --- Main ---
if [ ! -f "$SSH_KEY" ]; then
    log "ERROR: SSH Key file not found at $SSH_KEY"
    send_pushover_notification "Mailcow Sync Error: SSH Key file not found at $SSH_KEY"
    exit 1
fi
chmod 600 "$SSH_KEY"

log "Starting Mailcow synchronization process..."

log "Stopping Docker on the backup server..."
ssh -i "$SSH_KEY" -p "$SSH_PORT" "$TARGET_USER@$TARGET_SERVER" "sudo systemctl stop docker.service || true"

log "Waiting for Docker to stop..."
sleep 10

log "Syncing $MAILCOW_DIR..."
rsync -aHhP --numeric-ids --delete \
    -e "ssh -i $SSH_KEY -p $SSH_PORT" \
    --rsync-path="sudo rsync" \
    "$MAILCOW_DIR/" "$TARGET_USER@$TARGET_SERVER:$MAILCOW_DIR/"

log "Syncing $DOCKER_VOLUMES..."
> "$RSYNC_ERR_LOG"
rsync -aHhP --numeric-ids --delete \
    -e "ssh -i $SSH_KEY -p $SSH_PORT" \
    --rsync-path="sudo rsync" \
    $EXCLUDES \
    "$DOCKER_VOLUMES/" "$TARGET_USER@$TARGET_SERVER:$DOCKER_VOLUMES/" 2>"$RSYNC_ERR_LOG"

rm -f "$RSYNC_ERR_LOG"
log "Synchronization completed successfully!"

log "Starting Docker on the backup server..."
ssh -i "$SSH_KEY" -p "$SSH_PORT" "$TARGET_USER@$TARGET_SERVER" "sudo systemctl start docker.service"

log "Waiting for Docker to initialize..."
sleep 15

log "Pulling latest Mailcow images on backup server..."
ssh -i "$SSH_KEY" -p "$SSH_PORT" "$TARGET_USER@$TARGET_SERVER" "cd '$MAILCOW_DIR' && sudo docker-compose pull"

log "Starting Mailcow stack briefly to verify..."
ssh -i "$SSH_KEY" -p "$SSH_PORT" "$TARGET_USER@$TARGET_SERVER" "cd '$MAILCOW_DIR' && sudo docker-compose up -d"

log "Waiting for containers to come up..."
sleep 20

log "Stopping Mailcow containers - standby mode (not accepting mail)..."
ssh -i "$SSH_KEY" -p "$SSH_PORT" "$TARGET_USER@$TARGET_SERVER" "cd '$MAILCOW_DIR' && sudo docker-compose down"

log "Backup server is now in standby - Docker stopped, data synced, ready for failover."
