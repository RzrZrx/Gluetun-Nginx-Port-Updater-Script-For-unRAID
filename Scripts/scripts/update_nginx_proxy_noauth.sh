#!/bin/sh

# Script to proxy Gluetun's forwarded port to an internal Nginx port using socat.
#
# Created by:     Unraid user Zerax (Reddit: u/Snowbreath, GitHub: RzrZrx)
# Repository:     https://github.com/RzrZrx/Gluetun-Nginx-Port-Updater-Script-For-unRAID
# Version:        1.1.0 (No-Auth Version)
# Last Updated:   2025-04-23 (Formatted header, no-auth cleanup)
# Description:    Runs via Gluetun's UP_COMMAND. Starts a socat proxy to forward
#                 Gluetun's dynamic VPN port to a static internal Nginx port.
#                 Does NOT require API authentication (country lookup removed).
# Notes:          This script is intended to be called by Gluetun itself.
#                 Requires Nginx container to use Gluetun's network stack.

# --- START USER CONFIGURATION ---

# The internal port Nginx is listening on (inside the shared network namespace)
NGINX_INTERNAL_PORT=80

# File where Gluetun writes the public IP (Default: /gluetun/ip)
GLUETUN_IP_FILE="/gluetun/ip"

# --- END USER CONFIGURATION ---

# --- SCRIPT INTERNALS ---
# (Generally no need to modify below this line)

# A tag/comment to help identify the socat process (used with pgrep/pkill)
SOCAT_TAG="gluetun_nginx_proxy_noauth" # Slightly different tag just in case

# ANSI Color Codes
COLOR_GREEN='\033[1;32m' # Bold Green
COLOR_RESET='\033[0m'    # Reset colors

echo "--- Nginx Port Proxy Script v1.1.0 (No-Auth) ---"

# --- Dependency Checks ---
# Check for socat (essential)
if ! command -v socat > /dev/null 2>&1; then
    echo "socat not found. Installing..."
    if command -v apk > /dev/null 2>&1; then
        apk add --no-cache socat
        if ! command -v socat > /dev/null 2>&1; then
             echo "Error: Failed to install socat. Cannot proceed."
             exit 1
        fi
    else
        echo "Error: 'apk' not found. Cannot install socat."
        exit 1
    fi
else
     echo "socat is already installed."
fi
echo "Dependencies checked."
# --- End Dependency Checks ---

# Check for port argument
if [ -z "$1" ]; then
    echo "Error: No forwarded port argument received from Gluetun."
    exit 1
fi

FORWARDED_PORT="$1"
echo "Received forwarded port: $FORWARDED_PORT"

# Validate the port
if ! echo "$FORWARDED_PORT" | grep -qE '^[0-9]+$'; then
    echo "Error: Invalid port number received: [$FORWARDED_PORT]"
    exit 1
fi

# --- Get Public IP ---
PUBLIC_IP=""
if [ -f "$GLUETUN_IP_FILE" ]; then
    PUBLIC_IP=$(cat "$GLUETUN_IP_FILE")
    if ! echo "$PUBLIC_IP" | grep -qE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}'; then
        echo "Warning: Content of $GLUETUN_IP_FILE doesn't look like an IPv4 address: [$PUBLIC_IP]. URL will not be displayed."
        PUBLIC_IP=""
    else
         echo "Fetched Public IP: $PUBLIC_IP from $GLUETUN_IP_FILE"
    fi
else
    echo "Warning: Public IP file not found at $GLUETUN_IP_FILE. URL will not be displayed."
fi
# --- End Get Public IP ---

# --- Country lookup removed in this version ---

# Kill any previous socat instance managed by this script
echo "Checking for existing socat proxy process..."
# Use pgrep -f to find the process by command line pattern
PID=$(pgrep -f "socat TCP-LISTEN:[0-9]*,bind=0.0.0.0,fork TCP:127.0.0.1:${NGINX_INTERNAL_PORT}")
if [ -n "$PID" ]; then
    echo "Found existing socat process(es) (PID(s): $PID). Stopping them..."
    echo "$PID" | xargs kill -TERM > /dev/null 2>&1
    sleep 1
    PID_RECHECK=$(pgrep -f "socat TCP-LISTEN:[0-9]*,bind=0.0.0.0,fork TCP:127.0.0.1:${NGINX_INTERNAL_PORT}")
     if [ -n "$PID_RECHECK" ]; then
        echo "Process(es) $PID_RECHECK did not terminate gracefully. Sending SIGKILL..."
        echo "$PID_RECHECK" | xargs kill -KILL > /dev/null 2>&1
     fi
     echo "Stopped existing socat process(es)."
else
    echo "No existing socat proxy process found."
fi

# Start the new socat process in the background
echo "Starting new socat proxy: $FORWARDED_PORT -> 127.0.0.1:$NGINX_INTERNAL_PORT"
socat TCP-LISTEN:"$FORWARDED_PORT",bind=0.0.0.0,fork TCP:127.0.0.1:"$NGINX_INTERNAL_PORT" &
SOCAT_PID=$!
sleep 1

if kill -0 $SOCAT_PID > /dev/null 2>&1; then
    echo "socat process started successfully (PID: $SOCAT_PID)."
    echo "Proxying external port $FORWARDED_PORT to internal Nginx port $NGINX_INTERNAL_PORT."

    # Display the URL if IP was found
    if [ -n "$PUBLIC_IP" ]; then
        URL="http://${PUBLIC_IP}:${FORWARDED_PORT}/"
        # Use echo -e to enable color codes
        echo -e "${COLOR_GREEN}---------------------------------------------------------------------${COLOR_RESET}"
        echo -e "${COLOR_GREEN}Nginx should now be accessible via VPN at: ${URL}${COLOR_RESET}"
        echo -e "${COLOR_GREEN}---------------------------------------------------------------------${COLOR_RESET}"
    else
        echo "Note: Could not determine public IP, cannot display full URL."
    fi
    exit 0
else
    echo "Error: Failed to start socat process."
    exit 1
fi