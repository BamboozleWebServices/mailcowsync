#!/bin/bash

# --- Configuration ---
# --- Replace placeholders below with your actual values ---

TARGET_SERVER="<your-backup-server-ip-or-hostname>" # Backup server's hostname or IP address
TARGET_USER="root"                                  # SSH user on the backup server (ensure this user has necessary permissions)
MAILCOW_DIR="/opt/mailcow-dockerized"               # Default Mailcow installation directory (adjust if different)
DOCKER_VOLUMES="/var/lib/docker/volumes"            # Default Docker volumes directory (adjust if different)
EXCLUDES="--exclude rspamd-vol-1"                   # Volumes to exclude from sync (add more --exclude flags if needed, e.g., --exclude plausible_event-data)
SSH_PORT=<your-ssh-port>                            # SSH port for the backup server (e.g., 22 or a custom port)
SSH_KEY="<path-to-your-ssh-private-key>"            # Full path to the SSH private key for connecting to the backup server (e.g., /root/.ssh/id_ed25519_mailcow)
PUSHOVER_API_KEY="<your-pushover-api-key>"          # Your Pushover Application API Key/Token (leave empty or comment out Pushover lines if not used)
PUSHOVER_USER_KEY="<your-pushover-user-key>"        # Your Pushover User Key (leave empty or comment out Pushover lines if not used)
LOG_FILE="/var/log/sync_mailcow.log"                # Path to the log file for this script
RSYNC_OPTS="-aHhP --numeric-ids --delete -e 'ssh -i $SSH_KEY -p $SSH_PORT'" # Default rsync options

# Temporary file for capturing rsync stderr for detailed error reporting
RSYNC_ERR_LOG="/tmp/sync_mailcow_rsync_error.log"

# --- Functions ---

# Function to send Pushover notifications (used only on errors)
# Modify or replace this function if you use a different notification method
send_pushover_notification() {
    # Check if keys are set before attempting to send
    if [ -n "$PUSHOVER_API_KEY" ] && [ -n "$PUSHOVER_USER_KEY" ]; then
        local message="$1"
        curl -s \
            --form-string "token=$PUSHOVER_API_KEY" \
            --form-string "user=$PUSHOVER_USER_KEY" \
            --form-string "message=$message" \
            https://api.pushover.net/1/messages.json > /dev/null
    else
        log "Pushover keys not set, skipping notification."
    fi
}

# Log function: Adds timestamp and writes to log file and console
log() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Error handler: Logs error, sends notification, cleans up temp file, and exits
handle_error() {
    local exit_code=$? # Capture the exit code of the failed command
    local last_command="$1"
    local error_message # Variable to hold the final message for Pushover

    log "ERROR: Command '$last_command' failed with exit code $exit_code." # Log the failed command and exit code

    # Check if the specific rsync error log file exists and has content
    if [[ -s "$RSYNC_ERR_LOG" ]]; then
        # Read the first few lines (e.g., 5) from the error file to keep the notification concise
        local specific_error=$(head -n 5 "$RSYNC_ERR_LOG")
        log "Specific Error Details: $specific_error" # Log the captured details

        # Prepare the detailed Pushover message
        error_message="Mailcow Sync Error: '$last_command' failed. Details: $specific_error"
    else
        # Prepare the generic Pushover message if no details were captured
        error_message="Mailcow Sync Error: '$last_command' failed (Exit Code: $exit_code). No specific rsync details captured."
        log "No specific rsync error details captured in $RSYNC_ERR_LOG."
    fi

    # Send the notification
    send_pushover_notification "$error_message"

    # Clean up the temporary error file
    rm -f "$RSYNC_ERR_LOG"

    exit 1 # Exit the script
}

# --- Main Script ---

# Trap errors and call the error handler
# The 'trap' command ensures that if any command fails (exits with a non-zero status),
# the 'handle_error' function is called automatically, passing the failed command ($BASH_COMMAND)
trap 'handle_error "$BASH_COMMAND"' ERR

# Ensure SSH key exists and has correct permissions
if [ ! -f "$SSH_KEY" ]; then
    log "ERROR: SSH Key file not found at $SSH_KEY"
    # Send notification even if log function fails later
    send_pushover_notification "Mailcow Sync Error: SSH Key file not found at $SSH_KEY"
    exit 1
fi
log "Setting correct permissions for SSH key..."
chmod 600 "$SSH_KEY"
if [ $? -ne 0 ]; then
    # Handle chmod failure specifically as trap might not catch it if script exits here
    log "ERROR: Failed to set permissions on SSH key $SSH_KEY"
    send_pushover_notification "Mailcow Sync Error: Failed to set permissions on SSH key $SSH_KEY"
    exit 1
fi


log "Starting Mailcow synchronization process..."

# Ensure Docker and Docker Compose are installed on the backup server
# This uses a heredoc (<<'EOF') to run multiple commands on the remote server via SSH.
# It installs Docker, enables/starts the service, installs the latest compatible Docker Compose,
# and verifies both installations. This allows the backup server to be set up automatically.
log "Ensuring Docker and Docker Compose are installed on the backup server..."
ssh -i "$SSH_KEY" -p "$SSH_PORT" "$TARGET_USER@$TARGET_SERVER" <<'EOF'
  # Install Docker using the recommended method
  echo "Checking and installing Docker if needed..."
  if ! command -v docker > /dev/null; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
  else
    echo "Docker already installed."
  fi

  # Enable and start Docker service
  echo "Ensuring Docker service is enabled and running..."
  sudo systemctl enable --now docker

  # Install the latest Docker Compose compatible with Mailcow
  echo "Checking and installing Docker Compose if needed..."
  COMPOSE_URL="https://github.com/docker/compose/releases/download/v$(curl -Ls https://www.servercow.de/docker-compose/latest.php)/docker-compose-$(uname -s)-$(uname -m)"
  COMPOSE_DEST="/usr/local/bin/docker-compose"
  if ! command -v docker-compose > /dev/null || ! docker-compose version | grep -q "$(curl -Ls https://www.servercow.de/docker-compose/latest.php)"; then
      echo "Downloading Docker Compose from $COMPOSE_URL..."
      sudo curl -L "$COMPOSE_URL" -o "$COMPOSE_DEST"
      sudo chmod +x "$COMPOSE_DEST"
  else
      echo "Docker Compose already installed and seems up-to-date for Mailcow."
  fi

  # Verify installations
  echo "Verifying installations..."
  docker --version || { echo "Docker verification failed!" >&2; exit 1; }
  docker-compose --version || { echo "Docker Compose verification failed!" >&2; exit 1; }
  echo "Docker and Docker Compose setup verified."
EOF
# Note: The trap ERR will catch failures within the SSH command itself (like connection refused)
# or if the remote script invoked by SSH exits with a non-zero status (due to the 'exit 1' in the heredoc).

# Stop Docker on the backup server before syncing volumes
log "Stopping Docker on the backup server..."
ssh -i "$SSH_KEY" -p "$SSH_PORT" "$TARGET_USER@$TARGET_SERVER" "sudo systemctl stop docker.service && docker ps -a" # docker ps -a confirms no containers are running

# Wait for a moment to ensure Docker has fully stopped
log "Waiting for Docker to stop..."
sleep 10

# Sync /opt/mailcow-dockerized directory (configurations, etc.)
log "Syncing $MAILCOW_DIR..."
# Using $RSYNC_OPTS defined above. Preserves permissions, numeric IDs, deletes extra files on target.
rsync $RSYNC_OPTS "$MAILCOW_DIR/" "$TARGET_USER@$TARGET_SERVER:$MAILCOW_DIR/"

# Sync /var/lib/docker/volumes directory (mail data, databases, etc.)
log "Syncing $DOCKER_VOLUMES..."
# Clear previous rsync error log
> "$RSYNC_ERR_LOG"
# Using $RSYNC_OPTS and $EXCLUDES defined above. Redirects stderr for detailed error reporting.
rsync $RSYNC_OPTS $EXCLUDES "$DOCKER_VOLUMES/" "$TARGET_USER@$TARGET_SERVER:$DOCKER_VOLUMES/" 2> "$RSYNC_ERR_LOG"
# Error handling for this specific rsync is done via the || and trap mechanism, using the captured stderr

# Remove the temp error log if rsync was successful (optional, handle_error also removes it on failure)
if [ $? -eq 0 ]; then
    rm -f "$RSYNC_ERR_LOG"
fi

log "Synchronization completed successfully!"

# Start Docker on the backup server
log "Starting Docker on the backup server..."
ssh -i "$SSH_KEY" -p "$SSH_PORT" "$TARGET_USER@$TARGET_SERVER" "sudo systemctl start docker.service"

# Wait for Docker to initialize properly
log "Waiting for Docker to initialize..."
sleep 15

# Pull latest Mailcow Docker images on the backup server
log "Pulling Mailcow Docker images on the backup server..."
ssh -i "$SSH_KEY" -p "$SSH_PORT" "$TARGET_USER@$TARGET_SERVER" "cd '$MAILCOW_DIR' && docker-compose pull"

# Start Mailcow containers on the backup server
log "Starting Mailcow stack on the backup server..."
ssh -i "$SSH_KEY" -p "$SSH_PORT" "$TARGET_USER@$TARGET_SERVER" "cd '$MAILCOW_DIR' && docker-compose up -d"

log "Backup server synchronization and Docker restart completed successfully!"
