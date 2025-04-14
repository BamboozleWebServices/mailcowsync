# Mailcow Sync Script

A Bash script designed to synchronize a primary Mailcow mail server instance to a secondary backup/standby server, enabling quicker recovery and providing a high-availability strategy.

This script automates the process of mirroring Mailcow's configuration and critical data volumes using `rsync` over SSH. It includes features like automatic Docker/Compose installation on the backup server, error handling, and notifications.

**For a detailed step-by-step explanation of how the script works, the reasoning behind its design, setup instructions, configuration details, usage examples, failover strategies, and personal experience, please read the full blog post:**

**[Effortless Mailcow Sync-Failover: My Real-Time Backup Method](https://hostbor.com/mailcow-servers-in-sync/)**

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
    * `rsync`, `curl`, `ssh` client installed on the primary server. (`sudo apt update && sudo apt install -y rsync curl ssh`).
    * `rsync` installed on the backup server (`sudo apt update && sudo apt install -y rsync`).

## Quick Setup Overview

1.  **Download/Clone Script:** Get the `mailcow-sync.sh` script onto your **primary** Mailcow server.
    ```bash
    git clone https://github.com/hostbor/mailcowsync.git
    cd mailcowsync
    # Consider moving mailcow-sync.sh to /usr/local/sbin/ or /root/
    ```
2.  **Configure Script:** Edit `mailcow-sync.sh` and replace all placeholders (like `<your-backup-server-ip-or-hostname>`, `<your-ssh-port>`, `<path-to-your-ssh-private-key>`, Pushover keys, etc.) in the Configuration section with your actual values. Review default paths and exclusions.
3.  **Set Up SSH Keys:** Ensure passwordless SSH key authentication is working from your primary server to the backup server using the specified user and key.
4.  **Set Permissions:** Make the script executable: `chmod +x /path/to/your/mailcow-sync.sh`.

**➡️ For detailed installation steps, configuration guidance, and SSH key setup instructions, please refer to the [full blog post](https://hostbor.com/mailcow-servers-in-sync/).**

## Basic Usage

### Manual Execution

Run the script manually (usually as root or with `sudo`):

```bash
sudo /path/to/your/mailcow-sync.sh
```

Check the log file (`/var/log/sync_mailcow.log` by default) for progress and errors.

### Automated Execution (Cron)

Set up a cron job (`sudo crontab -e`) to run the script automatically on your desired schedule (e.g., daily, twice daily).

➡️ See the full blog post for detailed cron job examples and scheduling recommendations.

## License

This project is licensed under the MIT License - see the LICENSE file for details
