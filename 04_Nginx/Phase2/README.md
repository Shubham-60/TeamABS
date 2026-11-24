# Phase 2 Nginx Reverse Proxy & Active-Standby Edge Architecture (Extensions D & E)

This directory contains the Phase 2 Nginx configurations establishing physical edge redundancy, dual-domain SSL termination across multiple edge hosts, and dynamic upstream health detection with failover.

---

## 1. Edge Architecture & Physical Node Allocation

In Phase 1, Nginx operated exclusively as a single edge ingress on Mac 02 (`10.7.9.208`). In Phase 2, a dual-edge active-standby topology is deployed across the private LAN (`10.7.0.0/19`):

| Edge Role | Physical Host | IP Address | Listening Ports | Configuration File | Architectural Status |
|---|---|---|---|---|---|
| **Primary Edge** | Mac 02 (Atharva Sharma) | `10.7.9.208` | `8080`, `8443` | [`primary-edge.conf`](primary-edge.conf) | Primary edge ingress for both `app.teamabs.test` and `api.teamabs.test` |
| **Standby Edge** | Mac 03 (Bhavya Punj) | `10.7.16.91` | `8080`, `8443` | [`standby-edge.conf`](standby-edge.conf) | Standby failover ingress (tested during Extension E migration) |

---

## 2. SSL/TLS Certificate Distribution Across Nodes

Both the primary edge (Mac 02) and standby edge (Mac 03) terminate TLS on port `8443` for both project domains:

1. **Shared Root CA:** Both edges utilize certificates issued by the internal **TeamABS Root CA** (`cn-ca-v2.crt`).
2. **Dual-Domain SAN:** Both certificates contain Subject Alternative Names for both virtual hosts:
   - `DNS:app.teamabs.test`
   - `DNS:api.teamabs.test`
3. **Key Isolation & Host Deployment:**
   - **Atharva (Primary):** Certificate installed at `/opt/homebrew/etc/nginx/ssl/app.teamabs.test.crt` with Atharva's private key.
   - **Bhavya (Standby):** Generated a local CSR using Bhavya's own independent private key. Only the CSR was transferred for signing; the signed certificate was returned and installed at `/opt/homebrew/etc/nginx/ssl/app.teamabs.test.crt`.
   - **No private keys were ever transferred across nodes.**
4. **Keychain Trust:** The TeamABS CA was installed in the macOS System Keychain on both client and edge nodes, allowing trusted connections without `-k`.

---

## 3. Upstream Configuration & Dynamic Health Checks (Extension D)

Both edge configurations define an upstream pool pointing to both backend microservices:

```nginx
upstream teamabs_backends {
    server 10.7.21.236:3001 max_fails=1 fail_timeout=5s;
    server 10.7.16.91:3002 max_fails=1 fail_timeout=5s;
}
```

### Upstream Directives & Behavioral Mechanics
- **`max_fails=1`**: If a connection attempt or transmission to an upstream server fails once (e.g. TCP connection refused), Nginx marks that backend as unavailable.
- **`fail_timeout=5s`**: The duration (5 seconds) during which Nginx avoids routing new requests to the failed backend before probing it again with a live request.
- **Upstream Failover Directives (`proxy_next_upstream`):** The repository template includes `proxy_next_upstream error timeout invalid_header http_500 http_502 http_503 http_504;` and `proxy_next_upstream_tries 2;`. In the live primary deployment, `max_fails=1 fail_timeout=5s` provided the core dynamic health detection; these directives serve as complementary hardening for transparent request retries.
- **Custom Header Preservation:** `proxy_pass_header X-Backend` ensures that the backend identifier (`A` or `B`) emitted by the Python microservices passes untouched through the proxy to the client.

---

## 4. Architectural Constraint: Why Backend A Must Be Reachable from Both Edges

In the TeamABS topology:
- **Backend A** resides on Mac 01 (`10.7.21.236:3001`).
- **Backend B** resides on Mac 03 (`10.7.16.91:3002`).
- **Standby Nginx Edge** also resides on Mac 03 (`10.7.16.91`).

When client traffic is migrated to the Standby Edge on Mac 03:
1. If Mac 03 could only communicate with its local Backend B (`:3002`), all load balancing would be lost, degrading the system to a single-backend service.
2. For Mac 03's Nginx edge to balance traffic across the entire origin pool, it must proxy requests over the LAN to Backend A on Mac 01 (`10.7.21.236:3001`).
3. **Firewall Requirement:** The macOS Packet Filter firewall on Mac 01 ([`10_Firewall/shubham-teamabs.anchor`](../../10_Firewall/shubham-teamabs.anchor)) must explicitly allow inbound connections on port `3001` from **both** Atharva (`10.7.9.208`) and Bhavya (`10.7.16.91`).

---

## 5. Extension D: Backend Failover Testing Procedure

### Step 1: Baseline Verification
Send requests through the edge to verify upstream reachability:
```bash
curl -i https://app.teamabs.test:8443/api/status
```

### Step 2: Inject Backend A Failure
On Mac 01 (`10.7.21.236`), terminate the Backend A Python service (`Ctrl+C` or kill process on port 3001):
```bash
sudo lsof -i :3001
kill -9 <PID_OF_BACKEND_A>
```

### Step 3: Verify Failover to Backend B
Issue requests from the client immediately following the failure:
```bash
for i in {1..6}; do
  curl -s -D - https://app.teamabs.test:8443/api/status -o /dev/null | grep -i '^X-Backend:'
done
```
*Observed Output:*
```text
X-Backend: B
X-Backend: B
X-Backend: B
X-Backend: B
X-Backend: B
X-Backend: B
```
- **Observed Result:** Requests continued to receive HTTP 200 OK responses, served exclusively by Backend B while Backend A was offline.

### Step 4: Restore Backend A
On Mac 01, restart Backend A:
```bash
python3 03_Backends/backend_A/server.py
```
After the 5-second `fail_timeout` window, Nginx probed Backend A with a live request, marked it healthy, and resumed normal upstream routing.

---

## 6. Extension E: Step-by-Step Edge Migration & Testing Procedure

### Step 1: Deploy Standby Edge Configuration
On Mac 03 (Bhavya):
```bash
# 1. Copy standby configuration to Homebrew servers directory
sudo cp 04_Nginx/Phase2/standby-edge.conf /opt/homebrew/etc/nginx/servers/teamabs.conf

# 2. Test global Nginx configuration syntax
sudo /opt/homebrew/bin/nginx -t

# 3. Start Nginx (or reload if already running)
sudo /opt/homebrew/bin/nginx
# Or if already active:
sudo /opt/homebrew/bin/nginx -s reload

# 4. Verify standby listeners directly via curl --resolve
curl -i --resolve app.teamabs.test:8080:10.7.16.91 http://app.teamabs.test:8080/api/status
curl -iv --resolve app.teamabs.test:8443:10.7.16.91 https://app.teamabs.test:8443/api/status
```

> [!CAUTION]
> **Homebrew Servers Include Directory Rule (Backup Trap):**
> The main Homebrew configuration (`/opt/homebrew/etc/nginx/nginx.conf`) includes all files matching `servers/*;`.
> **Never store backup files (such as `teamabs.conf.backup`) inside `/opt/homebrew/etc/nginx/servers/`.**
> Storing a backup file inside that directory previously caused Nginx to parse two identical `upstream teamabs_backends` blocks, triggering a fatal duplicate upstream error. Store backups outside in the home directory (`~/teamabs.conf.backup`).

### Step 2: Temporary DNS Change (Migration Trigger)
In `dnsmasq.conf` on both DNS servers (Shubham and Bhavya), temporarily alter the `app.teamabs.test` record to point to the Standby Edge:
```ini
address=/app.teamabs.test/10.7.16.91
address=/api.teamabs.test/10.7.9.208
```
Reload `dnsmasq` on both servers.

### Step 3: Observed Client Migration Dynamics
During the Extension E test, a polling loop was executed on Atharva's Mac using `curl` while logging `remote_ip` and `http_code`. The actual recorded transition:

| Observed Timestamp | Client Remote IP | HTTP Status | Notes |
|---|---|---|---|
| `10:18:21` | `10.7.9.208` | `200` | Traffic served by Primary Edge |
| `10:18:26` | `10.7.9.208` | `200` | Traffic served by Primary Edge |
| `10:18:33` | `10.7.9.208` | `200` | Traffic served by Primary Edge |
| `10:18:39` | `10.7.9.208` | `200` | Traffic served by Primary Edge |
| `10:18:44` | `10.7.9.208` | `200` | Traffic served by Primary Edge |
| `10:18:50` | `10.7.9.208` | `200` | Traffic served by Primary Edge |
| `10:18:55` | `10.7.9.208` | `200` | Traffic served by Primary Edge |
| `10:19:00` | `10.7.16.91` | `200` | **Transition observed: Standby Edge now answering** |
| `10:19:09` onward | `10.7.16.91` | `200` | Traffic continuously served by Standby Edge |

- **Empirical Takeaway:** The client initially continued reaching the primary edge (`10.7.9.208`) and subsequently reached the standby edge (`10.7.16.91`). All recorded requests during the polling loop succeeded with HTTP 200. The observed transition occurred between 10:18:55 and 10:19:00 (approx. 35–40 seconds after record update; do not claim exact 30.0-second switchover).

### Step 4: Final Restoration of Normal DNS State
Following the test, both DNS configuration files on Mac 01 and Mac 03 were restored to the normal production mapping:
```ini
address=/app.teamabs.test/10.7.9.208
address=/api.teamabs.test/10.7.9.208
```
A final validation confirmed `remote_ip=10.7.9.208 http=200`.
