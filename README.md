# Mailcow Sync Script

A Bash script designed to synchronize a primary Mailcow mail server instance to a secondary backup/standby server, enabling quicker recovery and providing a high-availability strategy.

This script automates the process of mirroring Mailcow's configuration and critical data volumes using `rsync` over SSH. It includes features like automatic Docker/Compose installation on the backup server, error handling, and notifications.

**For a detailed step-by-step explanation of how the script works, the reasoning behind its design, setup instructions, configuration details, usage examples, failover strategies, and personal experience, please read the full blog post:**

**[Effortless Mailcow Sync-Failover: My Real-Time Backup Method](https://hostbor.com/mailcow-servers-in-sync/)**

---

## Bamboozle Web Services Notes

This fork is maintained by [Bamboozle Web Services](https://bamboozle.me) for use across our hosting infrastructure.

### MailChannels Integration

Our Mailcow deployments use **MailChannels** as a front-end relay for both **inbound and outbound** mail routing. This has an important implication for failover:

> **No DNS changes are required during failover.**
>
> Because MailChannels handles all mail delivery routing (inbound via MX/routing rules, outbound via relay), switching from the primary Mailcow server to the standby server only requires the Mailcow instance itself to be active — not a DNS update to MX or A records. Mail will continue to flow through MailChannels regardless of which Mailcow backend is active.
>
> **Failover steps in our environment:**
> 1. Confirm the primary Mailcow server is down or being taken offline.
> 2. 2. The standby server (already synced and running Mailcow containers) is immediately ready.
>    3. 3. Update internal routing or load balancer to point Mailcow traffic to the standby IP — **no public DNS change needed**.
>       4. 4. Notify the team via the configured Pushover alert channel.
>         
>          5. This significantly reduces recovery time compared to waiting for DNS propagation.
>         
>          6. ---
>         
>          7. ## Features
>
> * **Automated Server Mirroring:** Synchronizes the primary Mailcow server to a secondary server.
> * * **Configuration Sync:** Mirrors the Mailcow configuration directory (default: `/opt/mailcow-dockerized`).
>   * * **Data Volume Sync:** Mirrors essential Docker volumes (default: `/var/lib/docker/volumes`), ensuring mail data, databases, etc., are replicated.
>     * * **"Zero-Prep" Backup Server:** Automatically installs Docker and the correct Docker Compose version on the backup server during the first run if they are not present (Tested on Ubuntu/Debian).
>       * * **Efficient Transfers:** Uses `rsync` with optimized flags (`-aHhP --numeric-ids --delete`) to transfer only changed data and preserve permissions/ownership accurately.
>         * * **Configurable Exclusions:** Allows specific Docker volumes (like `rspamd-vol-1` by default) to be excluded, useful for architecture differences or ignoring unrelated containers.
>           * * **Robust Error Handling:** Implements `trap` to catch errors, logs detailed messages (including the failed command), and stops the script immediately upon failure.
>             * * **Notifications:** Optional error notifications via Pushover (easily adaptable to Email or Telegram).
>               * * **Automation Ready:** Designed to be run automatically via Cron for scheduled synchronization.
>                
>                 * ---
>                
>                 * ## Prerequisites
>                
>                 * * **Primary Server:** A running Mailcow installation. SSH access with a dedicated key pair. `rsync` installed.
> * **Backup Server:** A fresh server (Ubuntu/Debian recommended) with SSH access configured for the primary server's key. The script handles Docker/Compose installation automatically.
> * * **Network:** The primary server must be able to reach the backup server via SSH on the configured port.
>  
>   * ---
>  
>   * ## Setup
>  
>   * ### 1. Generate a Dedicated SSH Key (on Primary Server)
>
>   * ```bash
>     ssh-keygen -t ed25519 -f /root/.ssh/id_ed25519_mailcow -C "mailcow-sync"
>     ssh-copy-id -i /root/.ssh/id_ed25519_mailcow.pub -p <SSH_PORT> root@<BACKUP_SERVER_IP>
>     ```
>
> Test connectivity:
>
> ```bash
> ssh -i /root/.ssh/id_ed25519_mailcow -p <SSH_PORT> root@<BACKUP_SERVER_IP> "echo Connection successful"
> ```
>
> ### 2. Configure the Script
>
> Copy `mailcow-sync.sh` to your primary server (e.g., `/root/mailcow-sync.sh`) and edit the configuration section at the top:
>
> ```bash
> TARGET_SERVER=""        # Backup server IP or hostname
> TARGET_USER="root"
> MAILCOW_DIR="/opt/mailcow-dockerized"
> DOCKER_VOLUMES="/var/lib/docker/volumes"
> EXCLUDES="--exclude rspamd-vol-1"
> SSH_PORT=22             # Your SSH port
> SSH_KEY="/root/.ssh/id_ed25519_mailcow"
> PUSHOVER_API_KEY=""     # Optional
> PUSHOVER_USER_KEY=""    # Optional
> LOG_FILE="/var/log/sync_mailcow.log"
> ```
>
> ### 3. Make Executable
>
> ```bash
> chmod +x /root/mailcow-sync.sh
> ```
>
> ### 4. Schedule via Cron
>
> Run twice daily (recommended):
>
> ```bash
> 0 2,14 * * * /root/mailcow-sync.sh > /dev/null 2>&1
> ```
>
> ---
>
> ## Firewall
>
> Allow SSH from the primary server only on the backup:
>
> ```bash
> ufw allow from <PRIMARY_SERVER_IP> to any port <SSH_PORT> proto tcp
> ```
>
> ---
>
> ## License
>
> MIT — see [LICENSE](LICENSE). Original script by [hostbor](https://github.com/hostbor/mailcowsync).
