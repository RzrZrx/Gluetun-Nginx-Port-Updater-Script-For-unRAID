# Gluetun Nginx Port Forwarding Proxy Scripts

## Introduction

This repository provides scripts designed to solve a common challenge when running an Nginx web server behind a Gluetun VPN connection that uses dynamic port forwarding (e.g., with providers like Private Internet Access).

**The Problem:** Nginx typically requires a static port defined in its `listen` directive (e.g., `listen 80;`). However, Gluetun often receives a *dynamic* forwarded port from the VPN provider, which can change unpredictably. Manually updating the Nginx configuration and reloading it every time the port changes is impractical and error-prone.

**The Solution:** These scripts leverage Gluetun's `VPN_PORT_FORWARDING_UP_COMMAND` feature. Instead of modifying Nginx, Gluetun runs one of these scripts whenever it obtains a new forwarded port. The script then starts a lightweight `socat` proxy *inside* the Gluetun container. This `socat` process listens on the dynamic forwarded port provided by Gluetun and transparently forwards all incoming traffic to Nginx's static internal listening port (e.g., port 80). This allows your Nginx configuration to remain simple and static.

## Script Variants

Two versions of the script are provided to suit different needs:

1.  **`update_nginx_proxy.sh` (Auth Version)**
    *   **Functionality:** Sets up the `socat` proxy. Additionally, it attempts to query Gluetun's Control Server API (using **authentication**) to fetch the VPN's public IP address and country location, displaying this information in the logs for easy access verification (e.g., `URL: http://<vpn-ip>:<forwarded-port>/ (VPN Country: <Country Name>)`).
    *   **Requirements:** `socat`, `curl`, `jq` (installed automatically via `apk` if missing), configured Gluetun Control Server **authentication** (via `config.toml`), and corresponding credentials set within the script. The `config.toml` must grant access to the `GET /v1/publicip/ip` API endpoint.
    *   **Use Case:** Recommended if you want the convenience of seeing the full access URL and country in the logs and have authentication set up for Gluetun's API.

2.  **`update_nginx_proxy_noauth.sh` (No-Auth Version)**
    *   **Functionality:** Sets up the core `socat` proxy only. It attempts to read the public IP from Gluetun's IP file (`/gluetun/ip`) to display the access URL, but it **does not** query the API or display the country.
    *   **Requirements:** `socat` only (installed automatically via `apk` if missing). Does **not** require `curl`, `jq`, or Gluetun API authentication configuration.
    *   **Use Case:** Ideal for simpler setups where API authentication is not configured or needed, or if you want fewer dependencies. The core proxy functionality is identical to the Auth version.

## Key Requirement: Network Mode

For *either* script to work correctly, your **Nginx container MUST be configured to use the network stack of your Gluetun container**. This is typically done in Docker (or Unraid's template) by:

1.  Setting Nginx's Network Type to `None`.
2.  Adding an Extra Parameter like `--network=container:<Gluetun_Container_Name>` (e.g., `--network=container:gluetun-vpn`).

This allows the `socat` process inside Gluetun to reach Nginx on `127.0.0.1:<NGINX_INTERNAL_PORT>`.

---

**For detailed setup instructions, please see the project Wiki:**  
**[https://github.com/RzrZrx/Gluetun-Nginx-Port-Updater-Script-For-unRAID/wiki](https://github.com/RzrZrx/Gluetun-Nginx-Port-Updater-Script-For-unRAID/wiki)**

---

