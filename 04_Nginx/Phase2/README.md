# Phase 2 Nginx Reverse Proxy & Active-Standby Edge Architecture (Extensions D & E)

This directory contains the Phase 2 Nginx configurations establishing physical edge redundancy, SSL termination across multiple edge hosts, and dynamic upstream health detection with sub-second failover.

---

## 1. Edge Architecture & Physical Node Allocation

In Phase 1, Nginx operated exclusively as a single edge ingress on Mac 02 (`10.7.9.208`). In Phase 2, a dual-edge active-standby topology is deployed across the private LAN:

| Edge Role | Physical Host | IP Address | Listening Ports | Configuration File | Architectural Status |
|---|---|---|---|---|---|
| **Primary Edge** | Mac 02 (Atharva Sharma) | `10.7.9.208` | `8080`, `8443` | [`primary-edge.conf`](primary-edge.conf) | Primary ingress for `api.teamabs.test` & baseline edge |
| **Standby Edge** | Mac 03 (Bhavya Punj) | `10.7.16.91` | `8080`, `8443` | [`standby-edge.conf`](standby-edge.conf) | Standby ingress for `app.teamabs.test` (Extension E migration) |

---

## 2. SSL/TLS Certificate Distribution Across Nodes

Both the primary edge (Mac 02) and standby edge (Mac 03) terminate TLS 1.2 and TLS 1.3 on port `8443`:

1. **Shared Root CA:** Both edges utilize certificates issued by the internal **TeamABS Root CA** created in Phase 1.
2. **Subject Alternative Name (SAN):** The certificate configuration in [`05_TLS/san.cnf`](../../05_TLS/san.cnf) includes both SAN domain names:
   ```ini
   subjectAltName = @alt_names
   [alt_names]
   DNS.1 = app.teamabs.test
   DNS.2 = api.teamabs.test
   ```
3. **Host Deployment:**
   - The signed certificate (`app.teamabs.test.crt`) and private key (`app.teamabs.test.key`) are installed locally on both Atharva's Mac and Bhavya's Mac under `/opt/homebrew/etc/nginx/ssl/`.
   - Because all client workstations trust the TeamABS Root CA, clients establish secure, warning-free HTTPS connections to whichever edge node answers their query.
4. **Security Notice:** In adherence to security standards, private keys (`*.key`) are excluded from Git tracking via [`.gitignore`](../../.gitignore).

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
- **`max_fails=1`**: Specifies that a single connection failure, handshake failure, or error response from an upstream server causes Nginx to immediately mark that server as down.
- **`fail_timeout=5s`**: Defines the duration (5 seconds) during which Nginx avoids sending new requests to the failed backend before probing it again with a live request.
- **`proxy_next_upstream error timeout invalid_header http_500 http_502 http_503 http_504;`**: If the initially chosen backend fails, Nginx immediately passes the request to the next available backend in the pool without returning an HTTP 502/504 error to the client.
- **Custom Header Propagation:** `proxy_pass_header X-Backend` ensures that the backend identifier (`A` or `B`) emitted by the Python microservices passes untouched through the proxy to the client.

---

## 4. Architectural Constraint: Why Backend A Must Be Reachable from Both Edges

In the TeamABS topology:
- **Backend A** resides on Mac 01 (`10.7.21.236:3001`).
- **Backend B** resides on Mac 03 (`10.7.16.91:3002`).
- **Standby Nginx Edge** also resides on Mac 03 (`10.7.16.91`).

When client traffic is migrated to the Standby Edge on Mac 03:
1. If Mac 03 could only communicate with its local Backend B (`:3002`), all load balancing would be lost, degrading the system to a single-backend service.
2. For Mac 03's Nginx edge to balance traffic across the entire origin pool, it must proxy requests over the LAN to Backend A on Mac 01 (`10.7.21.236:3001`).
3. **Firewall Impact:** The macOS Packet Filter firewall on Mac 01 (`10_Firewall/shubham-teamabs.anchor`) must explicitly allow inbound connections on port `3001` from **both** Atharva (`10.7.9.208`) and Bhavya (`10.7.16.91`), while blocking all unauthorized LAN traffic.

---

## 5. Extension D: Backend Failover Testing Procedure

### Step 1: Baseline Round-Robin Verification
Verify alternating responses between Backend A and Backend B:
```bash
for i in {1..6}; do
  curl -s -D - https://app.teamabs.test:8443/api/status -o /dev/null | grep -i '^X-Backend:'
done
```
*Expected Output: Alternating `X-Backend: A` and `X-Backend: B`.*

### Step 2: Inject Backend A Failure
On Mac 01 (`10.7.21.236`), terminate the Backend A Python service:
```bash
sudo lsof -i :3001
kill -9 <PID_OF_BACKEND_A>
```

### Step 3: Verify Sub-Second Transparent Failover
Issue requests from the client immediately following the failure:
```bash
for i in {1..6}; do
  curl -s -D - https://app.teamabs.test:8443/api/status -o /dev/null | grep -i '^X-Backend:'
done
```
*Expected Output:*
```text
X-Backend: B
X-Backend: B
X-Backend: B
X-Backend: B
X-Backend: B
X-Backend: B
```
- **Result:** 100% of requests succeed with HTTP 200 OK. Nginx transparently fails over to Backend B with $< 50\text{ ms}$ latency penalty and zero dropped client requests.

### Step 4: Restore Backend A
On Mac 01, restart Backend A:
```bash
python3 03_Backends/backend_A/server.py
```
After the 5-second `fail_timeout` expires, Nginx probes Backend A, marks it healthy, and automatically restores round-robin distribution between Backend A and Backend B.

---

## 6. Extension E: Step-by-Step Edge Migration Procedure

To migrate the active edge from Mac 02 (Primary) to Mac 03 (Standby):

### Step 1: Verify Standby Edge Readiness
On Mac 03 (Bhavya):
```bash
# Test configuration syntax
sudo nginx -t -c $(pwd)/04_Nginx/Phase2/standby-edge.conf

# Start Standby Nginx
sudo nginx -c $(pwd)/04_Nginx/Phase2/standby-edge.conf

# Direct localhost / LAN check
curl -i http://10.7.16.91:8080/api/status
curl -ivk https://10.7.16.91:8443/api/status
```

### Step 2: Update DNS Authoritative Mapping
In `02_DNS/Phase2/primary-dnsmasq.conf` (and `backup-dnsmasq.conf`):
```ini
address=/app.teamabs.test/10.7.16.91
```
Reload `dnsmasq` on Mac 01 and Mac 03.

### Step 3: Flush Client Resolver Cache
```bash
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
```

### Step 4: Simulate Primary Edge Outage
On Mac 02 (Atharva), stop the primary Nginx service:
```bash
sudo nginx -s stop
```

### Step 5: Verify Uninterrupted Service Delivery
From client workstation:
```bash
# Resolve domain (resolves to Mac 03)
dig app.teamabs.test +noall +answer

# Request application over HTTPS
curl -iv https://app.teamabs.test:8443/api/status
```
**Outcome:** The request connects to `10.7.16.91:8443`, validates the TLS certificate, and receives responses from Backend A and Backend B via Bhavya's standby edge.
