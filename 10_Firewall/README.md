# Packet Filter (PF) Firewall Isolation (Extension C)

This directory documents the macOS Packet Filter (`pf`) firewall rules implemented to enforce origin service isolation across the TeamABS network architecture.

---

## 1. Security Architecture & Purpose

In production enterprise architectures, backend microservices and origin databases must never be directly exposed to arbitrary LAN workstations or end clients. Allowing unfiltered client access to origin servers bypasses:
1. **Centralized TLS Termination:** Exposing cleartext HTTP interfaces on ports `3001` and `3002`.
2. **Reverse Proxy Load Balancing & Caching:** Preventing Nginx from enforcing rate limits, request caching, and health detection.
3. **Auditability & WAF Policies:** Allowing uninspected payloads to hit backend application logic.

In Phase 2, macOS's native kernel packet filter (`pf`) is utilized to enforce strict Layer 4 ingress isolation on origin ports:
- **Mac 01 (Backend A - Port 3001):** Restricted exclusively to authorized edge reverse proxies.
- **Mac 03 (Backend B - Port 3002):** Restricted exclusively to Atharva's primary edge and local loopback.

---

## 2. PF Anchor Rules

> [!IMPORTANT]
> The `.anchor` files in this directory are modular **PF anchor rules**, designed to be attached to macOS's active ruleset via an anchor directive. They are **not** standalone replacements for the macOS system `/etc/pf.conf`.

### 2.1 Shubham's Mac Anchor ([`shubham-teamabs.anchor`](shubham-teamabs.anchor))
Deployed on **Mac 01 (`10.7.21.236`)**:
```pf
pass in quick on en0 inet proto tcp from 10.7.9.208 to 10.7.21.236 port 3001
pass in quick on en0 inet proto tcp from 10.7.16.91 to 10.7.21.236 port 3001
block in quick on en0 inet proto tcp from any to 10.7.21.236 port 3001
```

### 2.2 Bhavya's Mac Anchor ([`bhavya-teamabs.anchor`](bhavya-teamabs.anchor))
Deployed on **Mac 03 (`10.7.16.91`)**:
```pf
pass in quick on lo0 inet proto tcp from any to any port 3002
pass in quick on en0 inet proto tcp from 10.7.9.208 to 10.7.16.91 port 3002
block in quick on en0 inet proto tcp from any to 10.7.16.91 port 3002
```

---

## 3. Critical Topology Limitation: Bhavya-to-Backend-A Access

> [!WARNING]
> **Firewall Topology Limitation & The Bhavya Exception:**
> In our three-Mac topology, Bhavya (Mac 03) hosts both **Backend B** (`10.7.16.91:3002`) and the **Standby Nginx Edge** (`10.7.16.91:8080/8443`).
> 
> Because Bhavya operates as a standby reverse proxy during edge failover (Extension E), Bhavya's Nginx instance **must be able to reach Backend A** on Shubham's Mac (`10.7.21.236:3001`) to perform load balancing and failover across both backends.
> 
> Therefore, Shubham's firewall anchor contains an explicit allow rule:
> ```pf
> pass in quick on en0 inet proto tcp from 10.7.16.91 to 10.7.21.236 port 3001
> ```
> We do **not** claim that only Atharva's Mac can access every backend port; Bhavya is permitted access to Backend A specifically to fulfill the standby reverse proxy role.

---

## 4. PF Configuration & Lifecycle Management

### 4.1 Step 1: Back Up Original System Configuration
Always preserve the pristine macOS `/etc/pf.conf` before making modifications:
```bash
sudo cp /etc/pf.conf /etc/pf.conf.backup
```

### 4.2 Step 2: Install Anchor File
On **Mac 01 (Shubham)**:
```bash
sudo cp 10_Firewall/shubham-teamabs.anchor /etc/pf.anchors/teamabs.anchor
sudo chmod 644 /etc/pf.anchors/teamabs.anchor
```

On **Mac 03 (Bhavya)**:
```bash
sudo cp 10_Firewall/bhavya-teamabs.anchor /etc/pf.anchors/teamabs.anchor
sudo chmod 644 /etc/pf.anchors/teamabs.anchor
```

### 4.3 Step 3: Attach Anchor to Main `/etc/pf.conf`
Add anchor declaration and loading directives to `/etc/pf.conf`:
```pf
# Insert after existing anchor definitions:
anchor "teamabs"

# Insert at the end of /etc/pf.conf:
load anchor "teamabs" from "/etc/pf.anchors/teamabs.anchor"
```

### 4.4 Step 4: Validate Syntax & Load Rules
```bash
# Test configuration syntax without applying (dry-run)
sudo pfctl -vnf /etc/pf.conf

# Enable PF kernel engine and load configuration
sudo pfctl -ef /etc/pf.conf

# Reload only the anchor rules dynamically
sudo pfctl -a teamabs -f /etc/pf.anchors/teamabs.anchor
```

### 4.5 Step 5: Unloading / Flushing Rules
To safely unload the anchor rules without affecting the rest of the macOS system firewall:
```bash
# Flush only the teamabs anchor rules
sudo pfctl -a teamabs -F rules

# To completely disable PF (if needed during troubleshooting)
sudo pfctl -d
```

---

## 5. Verification & Testing Procedures

### 5.1 Verification Matrix

| Source Host | Destination Node | Target Port | PF Rule Evaluation | Observed Result |
|---|---|---|---|---|
| **Atharva (`10.7.9.208`)** | Mac 03 (`10.7.16.91`) | `3002` (Backend B) | **ALLOWED** | `HTTP 200 OK` (TCP connection established) |
| **Shubham (`10.7.21.236`)** | Mac 03 (`10.7.16.91`) | `3002` (Backend B) | **BLOCKED** | Connection timed out / packet dropped by PF |
| **Atharva (`10.7.9.208`)** | Mac 01 (`10.7.21.236`) | `3001` (Backend A) | **ALLOWED** | `HTTP 200 OK` (TCP connection established) |
| **Bhavya (`10.7.16.91`)** | Mac 01 (`10.7.21.236`) | `3001` (Backend A) | **ALLOWED** | `HTTP 200 OK` (Standby edge proxy route) |
| **External Client** | Mac 01 (`10.7.21.236`) | `3001` (Backend A) | **BLOCKED** | `Connection timed out` |

### 5.2 Test Commands

**1. Allowed Edge Access (from Atharva's Mac 02):**
```bash
# Query Backend A directly from edge (should succeed)
curl -i --connect-timeout 3 http://10.7.21.236:3001/api/status

# Query Backend B directly from edge (should succeed)
curl -i --connect-timeout 3 http://10.7.16.91:3002/api/status
```

**2. Blocked Direct Client Access (from Client Workstation):**
```bash
# Attempt to bypass proxy to Backend A (should hang and time out)
curl -i --connect-timeout 3 http://10.7.21.236:3001/api/status
# Output: curl: (28) Failed to connect to 10.7.21.236 port 3001: Operation timed out

# Attempt to bypass proxy to Backend B (should hang and time out)
curl -i --connect-timeout 3 http://10.7.16.91:3002/api/status
# Output: curl: (28) Failed to connect to 10.7.16.91 port 3002: Operation timed out
```

**3. Verified Proxy Access via Edge:**
```bash
# Access via Nginx edge over HTTPS (succeeds via authorized proxy connection)
curl -iv https://app.teamabs.test:8443/api/status
```

---

## 6. Troubleshooting Commands Using `pfctl`

If traffic is unexpectedly dropped or permitted, use the following diagnostic commands:

```bash
# 1. Check if PF is currently enabled
sudo pfctl -s info

# 2. View all active rules in the teamabs anchor
sudo pfctl -a teamabs -s rules

# 3. View rules with line numbers and packet evaluation counters
sudo pfctl -a teamabs -vv -s rules

# 4. Inspect current active state table entries
sudo pfctl -s state | grep 3001
sudo pfctl -s state | grep 3002

# 5. Check PF runtime statistics and dropped packet counters
sudo pfctl -s memory
```
