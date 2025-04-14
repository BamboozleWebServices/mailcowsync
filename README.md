# Mailcow Sync Script

A Bash script designed to synchronize a primary Mailcow mail server instance to a secondary backup/standby server, enabling quicker recovery and providing a high-availability strategy.

This script automates the process of mirroring Mailcow's configuration and critical data volumes using `rsync` over SSH. It includes features like automatic Docker/Compose installation on the backup server, error handling, and notifications.

**For a detailed step-by-step explanation of how the script works, the reasoning behind its design, failover strategies, and personal experience, please read the full blog post:**

**[How I Keep Two Mailcow Servers Perfectly In Sync (And You Can Too!)](https://hostbor.com/mailcow-servers-in-sync/)**

---

## Features

* **Automated Server Mirroring:** Synchronizes the primary Mailcow server to a secondary server.
* **Configuration Sync:** Mirrors the Mailcow configuration directory (default: `/opt/mailcow-dockerized`).
* **Data Volume Sync:** Mirrors essential Docker volumes (default: `/var/lib/docker/volumes`), ensuring mail data, databases, etc., are replicated.
* **"Zero-Prep" Backup Server:** Automatically installs Docker and the correct Docker Compose version on the backup server during the first run if they are not present (Tested on Ubuntu/Debian).
* **Efficient Transfers:** Uses `rsync` with optimized flags (`-aHhP --numeric-ids --delete`) to transfer only changed data and preserve permissions/ownership accurately.
* **Configurable Exclusions:** Allows specific Docker volumes (like `rspamd-vol-1` by default) to be excluded, useful for architecture differences or ignoring unrelated containers.
* **Robust Error Handling:** Implements `trap` to catch errors, logs detailed messages (including the failed command), and stops the script immediately upon failure.
* **Notifications:** Optional error notifications via Pushover (easily adaptable for other services like Email or Telegram by modifying the script function).
* **Automation Ready:** Designed to be run automatically via Cron for scheduled synchronization.

## Prerequisites

1.  **Two Servers:** A primary server running Mailcow and a secondary server intended as the backup/standby.
2.  **Operating System:** Tested primarily on recent versions of Ubuntu and Debian on both servers.
3.  **SSH Access:** Passwordless SSH key authentication must be configured from the primary server (where this script runs) to the backup server. The user specified (`TARGET_USER`, typically `root`) must be able to log in via SSH key.
4.  **Root/Sudo Privileges:** The script generally requires root privileges on the primary server to read all files and manage cron jobs (`sudo crontab`). The specified `TARGET_USER` on the backup server needs privileges to install packages (Docker/Compose), manage services (`systemctl`), and write files/directories via `rsync`.
5.  **Required Tools:**
    * `rsync` installed on both servers (`sudo apt update && sudo apt install -y rsync`).
    * `curl` installed on the primary server (for Pushover notifications and Docker Compose version check) (`sudo apt update && sudo apt install -y curl`).
    * `ssh` client installed on the primary server (usually default).

## Installation & Setup

1.  **Download/Clone Script:**
    * Clone this repository: `git clone https://github.com/hostbor/mailcowsync.git`
    * OR download the script file (`C-mailcow_sync_and_reboot_backup_nf.sh`) directly to your **primary** Mailcow server (e.g., place it in `/root/`).

2.  **Configure Script:**
    * Open the script file (`C-mailcow_sync_and_reboot_backup_nf.sh`) in a text editor.
    * Carefully edit the **Configuration** section at the top, replacing all placeholders (`<your-placeholder-name>`) with your actual values. Pay close attention to:
        * `TARGET_SERVER`: IP or hostname of your backup server.
        * `SSH_PORT`: SSH port of your backup server.
        * `SSH_KEY`: Full path to the private SSH key on the primary server used to connect to the backup server.
        * `PUSHOVER_API_KEY` & `PUSHOVER_USER_KEY`: Your Pushover keys (if using notifications). Leave blank or comment out the `send_pushover_notification` call in `handle_error` if not using Pushover.
        * Review `TARGET_USER`, `MAILCOW_DIR`, `DOCKER_VOLUMES`, `EXCLUDES`, `LOG_FILE` and adjust if your setup differs from the defaults. Add more `--exclude` flags to `EXCLUDES` if needed for other volumes.

3.  **Set Up SSH Key Authentication:**
    * If you haven't already, generate a dedicated SSH key pair on the primary server:
        ```bash
        ssh-keygen -t ed25519 -f /root/.ssh/id_ed25519_mailcow -C "mailcow-sync"
        ```
        *(Adjust the path `-f` if you configured a different `SSH_KEY` path in the script).*
    * Copy the public key to your backup server (replace placeholders):
        ```bash
        ssh-copy-id -i <path-to-your-ssh-public-key.pub> -p <your-ssh-port> <TARGET_USER>@<your-backup-server-ip-or-hostname>
        ```
        *(Example: `ssh-copy-id -i /root/.ssh/id_ed25519_mailcow.pub -p 22 root@backup.example.com`)*
    * Test the connection:
        ```bash
        ssh -i <path-to-your-ssh-private-key> -p <your-ssh-port> <TARGET_USER>@<your-backup-server-ip-or-hostname> "echo Connection successful"
        ```

4.  **Set Permissions:**
    * Make the script executable:
        ```bash
        chmod +x /path/to/your/C-mailcow_sync_and_reboot_backup_nf.sh
        ```
    * Ensure the SSH private key has secure permissions (already handled within the script by `chmod 600 "$SSH_KEY"`, but good practice to verify).

## Usage

### Manual Execution

You can run the script manually for testing or initial synchronization. It's recommended to use `sudo` or run as root due to permission requirements.

```bash
sudo /path/to/your/C-mailcow_sync_and_reboot_backup_nf.sh
Monitor the output and check the log file (/var/log/sync_mailcow.log by default) for details.Automated Execution (Cron)For regular, automated synchronization, set up a cron job.Edit the root crontab (or the crontab of the user who will run the script):sudo crontab -e
Add a line specifying the schedule and the script path. Examples:Run once daily at 2:00 AM:0 2 * * * /path/to/your/C-mailcow_sync_and_reboot_backup_nf.sh > /dev/null 2>&1
Run twice daily at 2:00 AM and 2:00 PM (14:00):0 2,14 * * * /path/to/your/C-mailcow_sync_and_reboot_backup_nf.sh > /dev/null 2>&1
Run every 6 hours:0 */6 * * * /path/to/your/C-mailcow_sync_and_reboot_backup_nf.sh > /dev/null 2>&1
Note: The > /dev/null 2>&1 part redirects standard output and standard error, preventing cron from sending emails for routine output. Errors are handled by the script's logging and notification functions.How It Works (Briefly)Error Trap: Sets up a trap to catch any command failure.Permissions: Ensures the specified SSH key has correct permissions (600).Remote Docker Setup: Connects via SSH to the backup server and runs commands within a heredoc (<<'EOF') to install/verify Docker and Docker Compose.Stop Remote Docker: Stops the Docker service on the backup server via SSH.Sync Config: Uses rsync over SSH to mirror the $MAILCOW_DIR.Sync Volumes: Uses rsync over SSH to mirror the $DOCKER_VOLUMES, applying exclusions from $EXCLUDES. Captures rsync errors for detailed reporting.Start Remote Docker: Starts the Docker service on the backup server via SSH.Pull Images: Pulls the latest Mailcow images on the backup server via docker-compose pull.Start Containers: Starts the Mailcow stack on the backup server via docker-compose up -d.Logging/Notifications: Logs steps and errors; sends Pushover alert on failure.For a full explanation, please see the blog post linked above.LicenseThis project is licensed under the MIT License - see the LICENSE file for details (Consider adding an MIT LICENSE file to your repository).ContributingContributions, issues, and feature requests are welcome.
