#!/bin/bash
# =============================================================================
# mailcow-failover.sh
# Cloudflare DNS failover script for Mailcow with MailChannels
#
# Usage: ./mailcow-failover.sh [failover|failback]
#   failover  - Point DNS to the standby (VIE) server
#   failback  - Point DNS back to the primary server
#
# What this does NOT touch:
#   - MX records (MailChannels handles all mail flow)
#   - SPF/DKIM/DMARC records
#
# What this DOES update:
#   - The single A record used for webmail, IMAP, POP3, SMTP submission
#     (e.g. mail.yourdomain.com)
# =============================================================================

# --- Configuration ---
CF_API_TOKEN=""               # Cloudflare API token (DNS Edit permission)
CF_ZONE_ID=""                 # Cloudflare Zone ID (found in domain Overview page)

MAIL_HOSTNAME="mail.yourdomain.com"   # The single hostname used for all client access

PRIMARY_IP=""                 # Primary Mailcow server IP
STANDBY_IP=""                 # Standby (VIE) Mailcow server IP

# Pushover notifications (optional - leave empty to disable)
PUSHOVER_API_KEY=""
PUSHOVER_USER_KEY=""

LOG_FILE="/var/log/mailcow-failover.log"
# --- End Configuration ---

# --- Functions ---
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
                                                                                                                                                            notify "Mailcow Failover ERROR: DNS record for ${MAIL_HOSTNAME} not found in Cloudflare."
                                                                                                                                                                    exit 1
                                                                                                                                                                        fi
                                                                                                                                                                        
                                                                                                                                                                            log "Updating ${MAIL_HOSTNAME} (record ID: ${record_id}) -> ${target_ip} ..."
                                                                                                                                                                            
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
                                                                                                                                                                                                                                                                                
                                                                                                                                                                                                                                                                                validate_config() {
                                                                                                                                                                                                                                                                                    local errors=0
                                                                                                                                                                                                                                                                                        [ -z "$CF_API_TOKEN" ]    && log "ERROR: CF_API_TOKEN is not set"    && errors=$((errors+1))
                                                                                                                                                                                                                                                                                            [ -z "$CF_ZONE_ID" ]      && log "ERROR: CF_ZONE_ID is not set"      && errors=$((errors+1))
                                                                                                                                                                                                                                                                                                [ -z "$MAIL_HOSTNAME" ]   && log "ERROR: MAIL_HOSTNAME is not set"   && errors=$((errors+1))
                                                                                                                                                                                                                                                                                                    [ -z "$PRIMARY_IP" ]      && log "ERROR: PRIMARY_IP is not set"      && errors=$((errors+1))
                                                                                                                                                                                                                                                                                                        [ -z "$STANDBY_IP" ]      && log "ERROR: STANDBY_IP is not set"      && errors=$((errors+1))
                                                                                                                                                                                                                                                                                                            [ "$errors" -gt 0 ] && exit 1
                                                                                                                                                                                                                                                                                                            }
                                                                                                                                                                                                                                                                                                            
                                                                                                                                                                                                                                                                                                            # --- Main ---
                                                                                                                                                                                                                                                                                                            ACTION="${1,,}"   # lowercase the argument
                                                                                                                                                                                                                                                                                                            
                                                                                                                                                                                                                                                                                                            if [ "$ACTION" != "failover" ] && [ "$ACTION" != "failback" ]; then
                                                                                                                                                                                                                                                                                                                echo "Usage: $0 [failover|failback]"
                                                                                                                                                                                                                                                                                                                    echo "  failover  - Switch DNS to standby (VIE) server"
                                                                                                                                                                                                                                                                                                                        echo "  failback  - Switch DNS back to primary server"
                                                                                                                                                                                                                                                                                                                            exit 1
                                                                                                                                                                                                                                                                                                                            fi
                                                                                                                                                                                                                                                                                                                            
                                                                                                                                                                                                                                                                                                                            validate_config
                                                                                                                                                                                                                                                                                                                            
                                                                                                                                                                                                                                                                                                                            CURRENT_IP=$(get_current_ip)
                                                                                                                                                                                                                                                                                                                            log "----------------------------------------------"
                                                                                                                                                                                                                                                                                                                            log "Action: ${ACTION^^}"
                                                                                                                                                                                                                                                                                                                            log "Current IP for ${MAIL_HOSTNAME}: ${CURRENT_IP}"
                                                                                                                                                                                                                                                                                                                            
                                                                                                                                                                                                                                                                                                                            if [ "$ACTION" = "failover" ]; then
                                                                                                                                                                                                                                                                                                                                if [ "$CURRENT_IP" = "$STANDBY_IP" ]; then
                                                                                                                                                                                                                                                                                                                                        log "Already pointing to standby (${STANDBY_IP}). No change made."
                                                                                                                                                                                                                                                                                                                                                exit 0
                                                                                                                                                                                                                                                                                                                                                    fi
                                                                                                                                                                                                                                                                                                                                                        update_dns "$STANDBY_IP"
                                                                                                                                                                                                                                                                                                                                                            notify "Mailcow FAILOVER complete: ${MAIL_HOSTNAME} now points to standby server (${STANDBY_IP}). Mail flow via MailChannels unaffected."
                                                                                                                                                                                                                                                                                                                                                                log "FAILOVER complete. Mail flow via MailChannels unaffected."
                                                                                                                                                                                                                                                                                                                                                                
                                                                                                                                                                                                                                                                                                                                                                elif [ "$ACTION" = "failback" ]; then
                                                                                                                                                                                                                                                                                                                                                                    if [ "$CURRENT_IP" = "$PRIMARY_IP" ]; then
                                                                                                                                                                                                                                                                                                                                                                            log "Already pointing to primary (${PRIMARY_IP}). No change made."
                                                                                                                                                                                                                                                                                                                                                                                    exit 0
                                                                                                                                                                                                                                                                                                                                                                                        fi
                                                                                                                                                                                                                                                                                                                                                                                            update_dns "$PRIMARY_IP"
                                                                                                                                                                                                                                                                                                                                                                                                notify "Mailcow FAILBACK complete: ${MAIL_HOSTNAME} now points back to primary server (${PRIMARY_IP})."
                                                                                                                                                                                                                                                                                                                                                                                                    log "FAILBACK complete."
                                                                                                                                                                                                                                                                                                                                                                                                    fi
                                                                                                                                                                                                                                                                                                                                                                                                    
                                                                                                                                                                                                                                                                                                                                                                                                    log "----------------------------------------------"
