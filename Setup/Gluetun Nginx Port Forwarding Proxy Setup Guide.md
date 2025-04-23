# Gluetun Nginx Port Forwarding Proxy Setup Guide

This guide explains how to set up automatic proxying for Nginx running behind a Gluetun VPN connection with dynamic port forwarding (e.g., using PIA). Instead of constantly changing Nginx's listening port, this setup uses a script (`update_nginx_proxy.sh`) executed by Gluetun to run a `socat` proxy. The proxy listens on the dynamic forwarded port provided by Gluetun and forwards traffic to Nginx listening on a standard, static internal port (like 80).

**Script Version:** This guide assumes you are using **v1.1.1 (Auth)** or later of the `update_nginx_proxy.sh` script.

**Script Link:** [update_nginx_proxy.sh on GitHub](https://github.com/RzrZrx/Gluetun-qBittorrent-Port-Updater-Script-For-unRAID/blob/main/Script/update_nginx_proxy.sh) *(Link needs updating if script is hosted elsewhere)*

## Benefits

*   **Static Nginx Configuration:** Your Nginx configuration (`default.conf`) listens on standard internal ports (e.g., 80) and never needs modification when the VPN port changes.
*   **Automation:** Gluetun automatically triggers the script to update the proxy when the forwarded port changes.
*   **Centralized Logic:** All dynamic port handling logic resides within the Gluetun container environment.
*   **User Feedback:** The script logs the publicly accessible URL (IP + Port) and VPN country upon successful setup.

## Prerequisites

1.  **Gluetun Container:**
    *   An instance of the `qmcgaw/gluetun` Docker container running and configured for your VPN provider (e.g., Private Internet Access).
    *   Your VPN provider must support port forwarding.
    *   Note the **exact name** of your Gluetun container (e.g., `GluetunVPN-nginx`).
2.  **Nginx Container:**
    *   An Nginx Docker container (e.g., `lscr.io/linuxserver/nginx`) running.
    *   Its configuration files should be accessible (usually via a mounted `/config` volume).
    *   Note the **exact name** of your Nginx container (e.g., `nginx`).
3.  **Network Configuration (Crucial):**
    *   Nginx **must** run using Gluetun's network stack. This allows the `socat` proxy inside Gluetun to reach Nginx via `127.0.0.1`.
    *   In Unraid's Docker settings for the **Nginx container**:
        *   Set **Network Type:** `None`
        *   Add an **Extra Parameter:** `--network=container:<Gluetun_Container_Name>` (e.g., `--network=container:GluetunVPN-nginx`).
4.  **Gluetun Control Server Authentication (Optional but Recommended):**
    *   If you want the script to display the VPN country, you need Gluetun's control server enabled and configured with authentication. The script needs credentials to access the necessary API endpoint.

## Setup Steps

### 1. Create Script Directory (on Host)
Create a directory on your host system (e.g., Unraid server) to store the script. This path will be mounted into the Gluetun container.

```bash
# Run this command in the Unraid terminal
mkdir -p /mnt/user/appdata/gluetun-nginx/scripts/