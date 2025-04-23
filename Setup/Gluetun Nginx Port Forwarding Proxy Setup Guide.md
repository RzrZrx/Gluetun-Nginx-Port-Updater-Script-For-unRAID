# Gluetun Nginx Port Forwarding Proxy Setup Guide

This guide explains how to set up automatic proxying for Nginx running behind a Gluetun VPN connection with dynamic port forwarding (e.g., using PIA). Instead of constantly changing Nginx's listening port, this setup uses a script (`update_nginx_proxy.sh`) executed by Gluetun to run a `socat` proxy. The proxy listens on the dynamic forwarded port provided by Gluetun and forwards traffic to Nginx listening on a standard, static internal port (like 80).

**Script Version:** v1.1.1 (Auth)

**Script Link:** [update_nginx_proxy.sh on GitHub](https://github.com/RzrZrx/Gluetun-qBittorrent-Port-Updater-Script-For-unRAID/blob/main/Script/update_nginx_proxy.sh)

---

## Benefits

- **Static Nginx Configuration:** No need to update Nginx when VPN port changes.
- **Automation:** Gluetun triggers the proxy update automatically.
- **Centralized Logic:** All dynamic logic is inside the Gluetun container.
- **User Feedback:** Script logs public URL and VPN country.

---

## Prerequisites

### 1. Gluetun Container
- Running `qmcgaw/gluetun` with port forwarding enabled.
- Note container name (e.g., `GluetunVPN-nginx`).

### 2. Nginx Container
- A working Nginx container (e.g., `lscr.io/linuxserver/nginx`).
- Configuration files must be accessible.

### 3. Network Configuration
- Nginx must share Gluetun's network namespace:
  - Set **Network Type:** `None`
  - Add extra param: `--network=container:GluetunVPN-nginx`

### 4. Gluetun Control Server Auth (Optional)
- Enable control server and authentication to fetch VPN country info.

---

## Setup Steps

### 1. Create Script Directory (on Host)
```bash
mkdir -p /mnt/user/appdata/gluetun-nginx/scripts/
```
(Adjust path as needed)

### 2. Download and Configure the Script
Update user configuration section in `update_nginx_proxy.sh`:
```bash
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
GLUETUN_USERNAME="your_gluetun_control_user"      # <--- CHANGE THIS to your Gluetun control user
GLUETUN_PASSWORD="your_gluetun_control_password"  # <--- CHANGE THIS to your Gluetun control password

# --- END USER CONFIGURATION ---
```
Save to:
```
/mnt/user/appdata/gluetun-nginx/scripts/update_nginx_proxy.sh
```

### 3. Make the Script Executable
```bash
chmod +x /mnt/user/appdata/gluetun-nginx/scripts/update_nginx_proxy.sh
```

### 4. Configure Nginx to Listen Internally
Edit `default.conf`:
```nginx
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    root /config/www;
    index index.html index.htm;
    server_name _;
    location / {
        autoindex on;
    }
}
```

### 5. Configure Gluetun Control Server Auth (If Using Auth)
Create/edit `/mnt/user/appdata/gluetun-nginx/auth/config.toml`:
```toml
# Gluetun Control Server Authentication Configuration
# File: /mnt/user/appdata/gluetun-nginx/auth/config.toml

[[roles]]
# Name of the role, can be descriptive
name = "nginx_proxy_script"

# List of API routes this role is allowed to access
# Format: "HTTP-METHOD /path"
routes = [
  "GET /v1/openvpn/portforwarded",  # Included for completeness / potential future use
  "GET /v1/publicip/ip"             # REQUIRED for the script to fetch country info
]

# Authentication method and credentials for this role
auth = "basic"
username = "your_username"  # Replace with your username
password = "your_password"  # Replace with your password

# You could add other roles below if needed for different users/scripts
# [[roles]]
# name = "another_role"
# ...
```

### 6. Configure Gluetun Container (Docker Settings)
#### A. Mount Script Directory
- Container Path: `/gluetun/scripts`
- Host Path: `/mnt/user/appdata/gluetun-nginx/scripts/`

#### B. Mount Auth Config Directory (If Using Auth)
- Container Path: `/gluetun/auth`
- Host Path: `/mnt/user/appdata/gluetun-nginx/auth/`

#### C. Environment Variables
```env
VPN_PORT_FORWARDING=on
VPN_PORT_FORWARDING_UP_COMMAND=/gluetun/scripts/update_nginx_proxy.sh {{PORTS}}
PORT_FORWARD_ONLY=true
HTTP_CONTROL_SERVER_LOG=on
LOG_LEVEL=info
```

#### D. Apply Changes
- Save and restart the container.

---

## Verification

Check Gluetun logs for script output:
```
INFO [port forwarding] Received forwarded port: <port>
INFO [port forwarding] Fetched Public IP: <ip>
INFO [port forwarding] Fetched Country: <Country>
INFO [port forwarding] Starting new socat proxy...
INFO [port forwarding] Proxying external port <port> to internal Nginx port 80.
INFO [port forwarding] ---------------------------------------------------------------------
INFO [port forwarding] Nginx should now be accessible via VPN at:
INFO [port forwarding] (VPN Country: <Country>
INFO [port forwarding] URL: http://<ip>:<port>/
INFO [port forwarding] ---------------------------------------------------------------------
```


Access the URL from outside your network.

---

## How It Works

1. Gluetun connects and gets a forwarded port.
2. It runs `update_nginx_proxy.sh {{PORTS}}`.
3. The script:
   - Validates the port.
   - Reads IP from `/gluetun/ip`.
   - Gets VPN country (if auth enabled).
   - Stops any previous `socat` process.
   - Starts new `socat` listener on the forwarded port.

---

## Troubleshooting / Notes

**Nginx Not Accessible:**
- Confirm correct IP/port in logs.
- Check if Nginx listens on defined internal port.
- Ensure Nginx uses Gluetun's network stack.
- Verify `socat` is running.

**Country Not Fetched:**
- Confirm credentials match in script and config.toml.
- Check API access via curl manually.

**Gluetun Fails to Start:**
- Look for errors validating `config.toml`.

**Script Version:**
- Update `SCRIPT_VERSION` inside script if modified.

