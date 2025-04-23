#!/bin/sh

# Script to proxy Gluetun's forwarded port to an internal Nginx port using socat
#
# Created by:     Unraid user Zerax (Reddit: u/Snowbreath, GitHub: RzrZrx)
# Repository:     https://github.com/RzrZrx/Gluetun-Nginx-Port-Updater-Script-For-unRAID
# Version:        1.1.1 (Auth Version - Removed debugging logs)
# Last Updated:   2025-04-23 (Cleaned up script, added auth support)
# Description:    Runs via Gluetun's UP_COMMAND. Starts a socat proxy to forward
#                 Gluetun's dynamic VPN port to a static internal Nginx port.
#                 Optionally fetches VPN country via authenticated API call.
# Notes:          This script is intended to be called by Gluetun itself.
#                 Requires Nginx container to use Gluetun's network stack.

# --- START USER CONFIGURATION ---

# The internal port Nginx is listening on (inside the shared network namespace)
NGINX_INTERNAL_PORT=80

# File where Gluetun writes the public IP (Default: /gluetun/ip)
GLUETUN_IP_FILE="/gluetun/ip"

# Gluetun control server address
GLUETUN_CONTROL_API="http://127.0.0.1:8000"

# !! IMPORTANT !! Set these to match your Gluetun Control Server authentication
# (Must match credentials in /gluetun/auth/config.toml or env vars if used)
# Leave blank or as default values if control server auth is disabled.
GLUETUN_USERNAME="your_gluetun_control_user"  # <--- CHANGE THIS to your Gluetun control user
GLUETUN_PASSWORD="your_gluetun_control_password"  # <--- CHANGE THIS to your Gluetun control password

# --- END USER CONFIGURATION ---

# --- SCRIPT INTERNALS ---
# (Generally no need to modify below this line)

# A tag/comment to help identify the socat process (used with pgrep/pkill)
SOCAT_TAG="gluetun_nginx_proxy_auth" # Specific tag

# ANSI Color Codes
COLOR_GREEN='\033[1;32m' # Bold Green
COLOR_YELLOW='\033[1;33m' # Bold Yellow
COLOR_RESET='\033[0m'    # Reset colors

echo "--- Nginx Port Proxy Script v1.1.1 (Auth) ---"

# --- Dependency Checks ---
COMMANDS_OK=true
# Check for socat
if ! command -v socat > /dev/null 2>&1; then echo "socat not found. Installing..."; if command -v apk > /dev/null 2>&1; then apk add --no-cache socat; if ! command -v socat > /dev/null 2>&1; then echo "Error: Failed to install socat."; COMMANDS_OK=false; fi; else echo "Error: 'apk' not found. Cannot install socat."; COMMANDS_OK=false; fi; fi
# Check for jq
if ! command -v jq > /dev/null 2>&1; then echo "jq not found (needed for country lookup). Installing..."; if command -v apk > /dev/null 2>&1; then apk add --no-cache jq; if ! command -v jq > /dev/null 2>&1; then echo "Warning: Failed to install jq. Country lookup will be skipped."; fi; else echo "Warning: 'apk' not found. Cannot install jq. Country lookup will be skipped."; fi; fi
# Check for curl
if ! command -v curl > /dev/null 2>&1; then echo "curl not found (needed for country lookup). Installing..."; if command -v apk > /dev/null 2>&1; then apk add --no-cache curl; if ! command -v curl > /dev/null 2>&1; then echo "Warning: Failed to install curl. Country lookup will be skipped."; fi; else echo "Warning: 'apk' not found. Cannot install curl. Country lookup will be skipped."; fi; fi

if [ "$COMMANDS_OK" = false ]; then echo "Error: Essential dependencies missing or failed to install. Cannot proceed."; exit 1; fi
echo "Dependencies checked."
# --- End Dependency Checks ---

# Check for port argument
if [ -z "$1" ]; then echo "Error: No forwarded port argument received from Gluetun."; exit 1; fi
FORWARDED_PORT="$1"
echo "Received forwarded port: $FORWARDED_PORT"
if ! echo "$FORWARDED_PORT" | grep -qE '^[0-9]+$'; then echo "Error: Invalid port number received: [$FORWARDED_PORT]"; exit 1; fi

# --- Get Public IP ---
PUBLIC_IP=""
# Add delay before reading file (optional, but can help)
sleep 1
if [ -f "$GLUETUN_IP_FILE" ]; then
    # Read content and strip potential trailing newline/whitespace
    TEMP_IP=$(sed 's/[[:space:]]*$//' "$GLUETUN_IP_FILE") # Simplified read+strip

    # Validate the processed content
    if echo "$TEMP_IP" | grep -qE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$'; then
         PUBLIC_IP="$TEMP_IP"
         echo "Fetched Public IP: $PUBLIC_IP from $GLUETUN_IP_FILE"
    else
        echo "Warning: Content read from $GLUETUN_IP_FILE after cleanup doesn't look like an IPv4 address: [$TEMP_IP]. URL will not be displayed."
    fi
else
    echo "Warning: Public IP file not found at $GLUETUN_IP_FILE. URL will not be displayed."
fi
# --- End Get Public IP ---

# --- Get Country (Optional) ---
COUNTRY=""
USE_AUTH=false
# Check if credentials look like they've been set
if [ -n "$GLUETUN_USERNAME" ] && [ -n "$GLUETUN_PASSWORD" ] && [ "$GLUETUN_USERNAME" != "your_gluetun_api_user" ] && [ "$GLUETUN_PASSWORD" != "your_gluetun_api_password" ]; then
    USE_AUTH=true
fi

# Only attempt if curl and jq are available
if command -v curl > /dev/null 2>&1 && command -v jq > /dev/null 2>&1; then
    API_ENDPOINT_URL="\"$GLUETUN_CONTROL_API/v1/publicip/ip\""
    CURL_CMD_BASE="curl -fsS --max-time 3"

    if [ "$USE_AUTH" = true ]; then
        echo "Attempting to fetch country from Gluetun API (using auth): $API_ENDPOINT_URL"
        CURL_CMD="$CURL_CMD_BASE -u \"$GLUETUN_USERNAME:$GLUETUN_PASSWORD\" $API_ENDPOINT_URL"
    else
        echo "Attempting to fetch country from Gluetun API (no auth): $API_ENDPOINT_URL"
        CURL_CMD="$CURL_CMD_BASE $API_ENDPOINT_URL"
    fi

    # Removed Debug line for eval command
    API_RESPONSE_JSON=$(eval $CURL_CMD)
    CURL_EXIT_CODE=$?
    # Removed Debug lines for exit code and raw response

    if [ $CURL_EXIT_CODE -eq 0 ] && [ -n "$API_RESPONSE_JSON" ]; then
        COUNTRY=$(echo "$API_RESPONSE_JSON" | jq -re .country 2>/dev/null)
        JQ_EXIT_CODE=$?
        # Removed Debug line for jq exit code

        if [ $JQ_EXIT_CODE -eq 0 ] && [ -n "$COUNTRY" ]; then
             echo "Fetched Country: $COUNTRY"
        else
             # More concise warning handling
             API_IP_CHECK=$(echo "$API_RESPONSE_JSON" | jq -re .ip 2>/dev/null)
             if [ -n "$API_IP_CHECK" ]; then
                 echo "Warning: Successfully fetched IP ($API_IP_CHECK) from API, but could not parse country."
             else
                 echo "Warning: Could not parse country or IP from API response: [$API_RESPONSE_JSON]"
             fi
             COUNTRY=""
        fi
    elif [ $CURL_EXIT_CODE -eq 22 ]; then # HTTP Error
         # Simplified warning, as specific causes were handled during debugging
         echo -e "${COLOR_YELLOW}Warning: Failed to fetch country from API (HTTP error code: $CURL_EXIT_CODE). Check permissions/credentials.${COLOR_RESET}"
    elif [ $CURL_EXIT_CODE -ne 0 ]; then # Network or other error
         echo "Warning: Failed to fetch country from Gluetun API (Network/other error, code: $CURL_EXIT_CODE)."
    fi
else
     echo "Skipping country lookup (curl or jq not available)."
fi
# --- End Get Country ---

# Kill any previous socat instance managed by this script
echo "Checking for existing socat proxy process..."
PID=$(pgrep -f "socat TCP-LISTEN:[0-9]*,bind=0.0.0.0,fork TCP:127.0.0.1:${NGINX_INTERNAL_PORT}")
if [ -n "$PID" ]; then echo "Found existing socat process(es) (PID(s): $PID). Stopping them..."; echo "$PID" | xargs kill -TERM > /dev/null 2>&1; sleep 1; PID_RECHECK=$(pgrep -f "socat TCP-LISTEN:[0-9]*,bind=0.0.0.0,fork TCP:127.0.0.1:${NGINX_INTERNAL_PORT}"); if [ -n "$PID_RECHECK" ]; then echo "Process(es) $PID_RECHECK did not terminate gracefully. Sending SIGKILL..."; echo "$PID_RECHECK" | xargs kill -KILL > /dev/null 2>&1; fi; echo "Stopped existing socat process(es)."; else echo "No existing socat proxy process found."; fi

# Start the new socat process in the background
echo "Starting new socat proxy: $FORWARDED_PORT -> 127.0.0.1:$NGINX_INTERNAL_PORT"
socat TCP-LISTEN:"$FORWARDED_PORT",bind=0.0.0.0,fork TCP:127.0.0.1:"$NGINX_INTERNAL_PORT" > /dev/null 2>&1 &
SOCAT_PID=$!
# Removed Debug line for SOCAT_PID capture

if ! echo "$SOCAT_PID" | grep -qE '^[0-9]+$'; then echo "Error: Failed to get valid PID for socat process. socat command likely failed immediately."; exit 1; fi
sleep 1

if kill -0 "$SOCAT_PID" > /dev/null 2>&1; then
    echo "socat process started successfully (PID: $SOCAT_PID)."
    echo "Proxying external port $FORWARDED_PORT to internal Nginx port $NGINX_INTERNAL_PORT."

    # Display the access information in the desired format
   if [ -n "$PUBLIC_IP" ]; then
    URL="http://${PUBLIC_IP}:${FORWARDED_PORT}/"
    echo -e "${COLOR_GREEN}---------------------------------------------------------------------${COLOR_RESET}"
    echo -e "${COLOR_GREEN}Nginx should now be accessible via VPN at:${COLOR_RESET}"
    if [ -n "$COUNTRY" ]; then
        echo -e "${COLOR_GREEN}(VPN Country: $COUNTRY)${COLOR_RESET}"
    fi
    echo -e "${COLOR_GREEN}${URL}${COLOR_RESET}"
    echo -e "${COLOR_GREEN}---------------------------------------------------------------------${COLOR_RESET}"
else
    echo "Note: Could not determine public IP, cannot display full URL."
fi

    exit 0
else
    echo "Error: socat process with PID [$SOCAT_PID] is not running. Failed to start."
    exit 1
fi