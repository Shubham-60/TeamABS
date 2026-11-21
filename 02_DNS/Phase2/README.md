# Phase 2 DNS Architecture & High Availability (Extensions A & B)

This directory contains the Phase 2 DNS configurations establishing redundant (primary and backup) DNS resolution and an authoritative 30-second Time-To-Live (TTL) policy for the `teamabs.test` private namespace.

---

## 1. Phase 2 DNS Topology & Node Mapping

In Phase 2, DNS resolution is upgraded from a single point of failure (Phase 1) to an active-passive redundant resolver architecture distributed across two physical nodes on the private LAN (`10.7.0.0/19`):

| Role | Host Node | IP Address | Port | Interface | Config File |
|---|---|---|---|---|---|
| **Primary DNS** | Mac 01 (Shubham) | `10.7.21.236` | `53` | `en0` | [`primary-dnsmasq.conf`](primary-dnsmasq.conf) |
| **Backup DNS** | Mac 03 (Bhavya) | `10.7.16.91` | `53` | `en0` | [`backup-dnsmasq.conf`](backup-dnsmasq.conf) |

### Restored Phase 2 DNS Records

```text
app.teamabs.test -> 10.7.16.91  (Mac 03 Standby Nginx Edge)
api.teamabs.test -> 10.7.9.208   (Mac 02 Primary Nginx Edge)
TTL = 30 seconds
```

### Architectural Rationale for Node Mappings
- **Why `api.teamabs.test` points to `10.7.9.208`:** Mac 02 (Atharva) serves as the Primary Nginx Edge Gateway, executing active reverse proxying, TLS termination (`:8443`), and dynamic upstream load balancing across Backend A (`:3001`) and Backend B (`:3002`).
- **Why `app.teamabs.test` points to `10.7.16.91`:** Mac 03 (Bhavya) hosts the Standby Nginx Edge Gateway deployed in Extension E. Routing `app.teamabs.test` to `10.7.16.91` demonstrates multi-edge deployment and active traffic redirection to the secondary physical edge node while `api.teamabs.test` continues through the primary edge.
- **Phase 1 vs. Phase 2 Difference:** In Phase 1, both domains mapped exclusively to Mac 02 (`10.7.9.208`). The original Phase 1 single-resolver configuration is preserved separately in [`02_DNS/dnsmasq.conf`](../dnsmasq.conf).

---

## 2. Configuration Analysis & TTL Policy

### 2.1 Primary DNS Configuration ([`primary-dnsmasq.conf`](primary-dnsmasq.conf))
- **Listen Address:** `10.7.21.236` explicitly bound to the physical Wi-Fi interface (`en0`).
- **Port:** Standard UDP/TCP port `53`.
- **Authoritative TTL (`local-ttl=30`):** Sets the Time-To-Live for local DNS answers to exactly 30 seconds.
- **Forwarders:** Upstream queries outside `teamabs.test` forward to Cloudflare (`1.1.1.1`) and Google (`8.8.8.8`).

### 2.2 Backup DNS Configuration ([`backup-dnsmasq.conf`](backup-dnsmasq.conf))
- **Listen Address:** `10.7.16.91` bound to `en0`.
- **Mirror Records:** Maintains identical authoritative mappings as the primary resolver to guarantee consistent namespace resolution regardless of which resolver answers.

### 2.3 Why `local-ttl=30` is Used
In production architectures, DNS TTL involves a fundamental trade-off:
1. **Low TTL (e.g. 30 seconds):** Minimizes cache staleness, enabling rapid disaster recovery, dynamic failover, and edge migrations (Extension B and Extension E). If a node fails or an IP changes, client caches expire within 30 seconds.
2. **High TTL (e.g. 86400 seconds / 24 hours):** Maximizes caching efficiency and reduces recursive resolver query loads, but prevents rapid operational traffic steering.
3. **Phase 2 Choice:** `local-ttl=30` is ideal for high-availability private infrastructure: it demonstrates rapid record propagation during maintenance and tests without overwhelming the local `dnsmasq` instances.

---

## 3. Service Lifecycle Management

### 3.1 Starting `dnsmasq`
On **Mac 01 (Primary DNS — Shubham)**:
```bash
sudo dnsmasq -C 02_DNS/Phase2/primary-dnsmasq.conf -d
```

On **Mac 03 (Backup DNS — Bhavya)**:
```bash
sudo dnsmasq -C 02_DNS/Phase2/backup-dnsmasq.conf -d
```
*(The `-d` flag keeps dnsmasq in foreground debug mode to log all incoming queries in real time. Omit `-d` to daemonize).*

### 3.2 Stopping `dnsmasq` and Verifying Port Release
To stop the resolver on either machine:
```bash
sudo killall dnsmasq
# Or targeted process termination:
sudo pkill -f dnsmasq
```

Verify that port `53` is completely released:
```bash
sudo lsof -nP -iUDP:53 -iTCP:53
```
*(No output indicates port 53 is fully released).*

---

## 4. Client Resolver Ordering & System Inspection

For client nodes to leverage automatic primary-to-backup failover, both resolvers must be configured in order of preference:

```bash
# 1. Set primary (10.7.21.236) and backup (10.7.16.91) on macOS client
sudo networksetup -setdnsservers Wi-Fi 10.7.21.236 10.7.16.91

# 2. Verify configured resolvers
networksetup -getdnsservers Wi-Fi
```

Expected output:
```text
10.7.21.236
10.7.16.91
```

### Verification via `scutil --dns`
Inspect the operating system resolver hierarchy:
```bash
scutil --dns
```
Expected excerpt:
```text
resolver #1
  nameserver[0] : 10.7.21.236
  nameserver[1] : 10.7.16.91
  if_index : 14 (en0)
  flags    : Scoped, Request A records
  reach    : 0x00020002 (Reachable,Directly Reachable Address)
```

---

## 5. Resolution Verification Commands

### 5.1 Querying Specific Resolvers with `dig`
```bash
# Test Primary Resolver explicitly
dig @10.7.21.236 app.teamabs.test +noall +answer
# Output: app.teamabs.test. 30 IN A 10.7.16.91

dig @10.7.21.236 api.teamabs.test +noall +answer
# Output: api.teamabs.test. 30 IN A 10.7.9.208

# Test Backup Resolver explicitly
dig @10.7.16.91 app.teamabs.test +noall +answer
# Output: app.teamabs.test. 30 IN A 10.7.16.91

dig @10.7.16.91 api.teamabs.test +noall +answer
# Output: api.teamabs.test. 30 IN A 10.7.9.208
```

### 5.2 Querying System Resolver
```bash
dig app.teamabs.test +noall +answer
```

---

## 6. Extension A: Primary DNS Failure & Failover Test Procedure

1. **Verify Baseline State:**
   Ensure both resolvers are running. Verify client resolves `app.teamabs.test` via primary `10.7.21.236`.
2. **Inject Primary DNS Failure:**
   On Mac 01 (`10.7.21.236`), kill the `dnsmasq` process:
   ```bash
   sudo killall dnsmasq
   ```
3. **Verify Failover from Client:**
   Execute a resolution from client:
   ```bash
   dig app.teamabs.test +noall +answer
   ```
   **Observation:** The client queries the primary, encounters timeout/unreachability, and falls back to the backup resolver (`10.7.16.91`), which returns `10.7.16.91` with TTL 30.
4. **End-to-End Application Validation:**
   ```bash
   curl -i http://app.teamabs.test:8080/api/status
   ```
   HTTP 200 OK is received through the standby edge without client interruption.
5. **Restore Primary Resolver:**
   On Mac 01, restart `dnsmasq`:
   ```bash
   sudo dnsmasq -C 02_DNS/Phase2/primary-dnsmasq.conf -d
   ```
   Resolution immediately resumes using the restored primary resolver.

---

## 7. Extension B: DNS TTL Dynamics & macOS Resolver Limitation

### Configured TTL Verification
Executing `dig @10.7.21.236 app.teamabs.test` confirms:
```text
;; ANSWER SECTION:
app.teamabs.test.    30    IN    A    10.7.16.91
```

### Client Cache Invalidation
To purge local macOS client DNS cache:
```bash
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
```

### Observed macOS Resolver Limitation
> [!WARNING]
> **macOS DNS Cache Dynamics:**
> In macOS, `mDNSResponder` handles both unicast DNS and Multicast DNS (Bonjour). When multiple resolvers are configured (`scutil --dns`), macOS does not always execute strict serial waterfall fallbacks or hold cached records until the exact second of TTL expiration.
> - Under certain network conditions, macOS races queries across configured resolvers or revalidates records proactively.
> - When server records are updated, standard system queries may retrieve the newly advertised record immediately rather than demonstrating stale cache retention for the remaining TTL window.
> - This is a documented design characteristic of the Apple Darwin unicast resolution stack and does not reflect a defect in `dnsmasq` or the network configuration.
