#!/bin/bash
# =============================================================================
# mailcow-failover-local.sh
# Run this ON THE VIE STANDBY SERVER when the primary (Dubai) is down
#
# Usage: sudo bash mailcow-failover-local.sh [failover|failback]
#   failover  - Start Mailcow locally + update DNS to VIE
#   failback  - Stop Mailcow locally + update DNS back to primary
# =============================================================================

# --- Configuration ---
CF_API_TOKEN="Wn1Am5BHNseo1o8ffuGHJjs-lOaxySHg6ZjNJIu3"
CF_ZONE_ID="90f8852b7d4854d831a96f2b5d1ea166"

MAIL_HOSTNAME="mx.bamboozlewebservices.com"
PRIMARY_IP="45.66.246.122"
STANDBY_IP="84.38.255.23"

MAILCOW_DIR="/opt/mailcow-dockerized"

PUSHOVER_API_KEY=""
PUSHOVER_USER_KEY=""

LOG_FILE="/var/log/mailcow-failover.log"
# --- End Configuration ---

log() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

notify() {
    if [ -n "$PUSHOVER_API_KEY" ] && [ -n "$PUSHOVER_USER_KEY" ]; then
        curl -s \
            --form-string "token=$PUSHOVER_API_KEY" \
            --form-string "user=$PUSHOVER_USER_KEY" \
            --form-string "message=$1" \
            https://api.pushover.net/1/messages.json > /dev/null
    fi
}

get_record_id() {
    curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records?type=A&name=${MAIL_HOSTNAME}" \
        -H "Authorization: Bearer ${CF_API_TOKEN}" \
        -H "Content-Type: application/json" \
        | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4
}

get_current_ip() {
    curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records?type=A&name=${MAIL_HOSTNAME}" \
        -H "Authorization: Bearer ${CF_API_TOKEN}" \
        -H "Content-Type: application/json" \
        | grep -o '"content":"[^"]*"' | head -1 | cut -d'"' -f4
}

update_dns() {
    local target_ip="$1"
    local record_id
    record_id=$(get_record_id)

    if [ -z "$record_id" ]; then
        log "ERROR: Could not find DNS record for ${MAIL_HOSTNAME}"
        notify "Mailcow Failover ERROR: DNS record not found in Cloudflare."
        exit 1
    fi

    log "Updating ${MAIL_HOSTNAME} -> ${target_ip} ..."

    local result
    result=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records/${record_id}" \
        -H "Authorization: Bearer ${CF_API_TOKEN}" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"A\",\"name\":\"${MAIL_HOSTNAME}\",\"content\":\"${target_ip}\",\"ttl\":60,\"proxied\":false}")

    if echo "$result" | grep -q '"success":true'; then
        log "SUCCESS: ${MAIL_HOSTNAME} now points to ${target_ip} (TTL: 60s)"
        return 0
    else
        local error
        error=$(echo "$result" | grep -o '"message":"[^"]*"' | head -1 | cut -d'"' -f4)
        log "ERROR: Cloudflare API call failed: ${error}"
        notify "Mailcow Failover ERROR: DNS update failed - ${error}"
        exit 1
    fi
}

ACTION="${1,,}"

if [ "$ACTION" != "failover" ] && [ "$ACTION" != "failback" ]; then
    echo "Usage: $0 [failover|failback]"
    echo "  failover  - Start Mailcow locally + switch DNS to VIE (use when Dubai is down)"
    echo "  failback  - Stop Mailcow locally + switch DNS back to Dubai (use when Dubai is back)"
    exit 1
fi

CURRENT_IP=$(get_current_ip)
log "----------------------------------------------"
log "Action: ${ACTION^^}"
log "Current IP for ${MAIL_HOSTNAME}: ${CURRENT_IP}"

if [ "$ACTION" = "failover" ]; then
    if [ "$CURRENT_IP" = "$STANDBY_IP" ]; then
        log "Already pointing to VIE (${STANDBY_IP}). No change made."
        exit 0
    fi
    log "Starting Mailcow containers locally on VIE..."
    cd "$MAILCOW_DIR" && docker-compose up -d
    log "Waiting for containers to initialize..."
    sleep 20
    update_dns "$STANDBY_IP"
    notify "Mailcow FAILOVER complete: Dubai is down. VIE (${STANDBY_IP}) is now active. DNS updated."
    log "FAILOVER complete. VIE is now handling mail."

elif [ "$ACTION" = "failback" ]; then
    if [ "$CURRENT_IP" = "$PRIMARY_IP" ]; then
        log "Already pointing to primary (${PRIMARY_IP}). No change made."
        exit 0
    fi
    update_dns "$PRIMARY_IP"
    log "Stopping Mailcow containers locally on VIE..."
    cd "$MAILCOW_DIR" && docker-compose down
    notify "Mailcow FAILBACK complete: Dubai is back. DNS pointing to primary (${PRIMARY_IP}). VIE stopped."
    log "FAILBACK complete. Remember to run a fresh sync from Dubai."
fi

log "----------------------------------------------"
