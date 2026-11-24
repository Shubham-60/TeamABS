# Phase 2 DNS Architecture & High Availability (Extensions A & B)

This directory contains the Phase 2 DNS configurations establishing redundant (primary and backup) DNS resolution and an authoritative 30-second Time-To-Live (TTL) policy for the `teamabs.test` private namespace.

---

## 1. Phase 2 DNS Topology & Normal Node Mapping

In Phase 2, DNS resolution is upgraded from a single point of failure (Phase 1) to an active-passive redundant resolver architecture distributed across two physical nodes on the private LAN (`10.7.0.0/19`):

| Role | Host Node | IP Address | Port | Interface | Configuration Template |
|---|---|---|---|---|---|
| **Primary DNS** | Mac 01 (Shubham Aggarwal) | `10.7.21.236` | `53` | `en0` | [`primary-dnsmasq.conf`](primary-dnsmasq.conf) |
| **Backup DNS** | Mac 03 (Bhavya Punj) | `10.7.16.91` | `53` | `en0` | [`backup-dnsmasq.conf`](backup-dnsmasq.conf) |

### Restored Normal DNS Records (Production State)

```text
app.teamabs.test -> 10.7.9.208   (Mac 02 Primary Nginx Edge)
api.teamabs.test -> 10.7.9.208   (Mac 02 Primary Nginx Edge)
TTL = 30 seconds
```

> [!IMPORTANT]
> **Distinction: Normal DNS State vs. Temporary Extension E Migration State:**
> - In normal operation across both Phase 1 and restored Phase 2, **both** `app.teamabs.test` and `api.teamabs.test` resolve to **`10.7.9.208`** (Atharva's Primary Nginx Edge).
> - During the **Extension E Edge Migration test only**, the `app.teamabs.test` record on both resolvers was temporarily modified to point to Bhavya's Standby Edge (`10.7.16.91`). Once the migration test and polling loop completed, the record was restored to `10.7.9.208`.
> - Both configuration templates in this directory reflect the final restored normal state.

---

## 2. Configuration Analysis & TTL Policy

### 2.1 Primary DNS Configuration ([`primary-dnsmasq.conf`](primary-dnsmasq.conf))
- **Listen Address:** `10.7.21.236` explicitly bound to interface `en0`.
- **Port:** Standard UDP/TCP port `53`.
- **Authoritative TTL (`local-ttl=30`):** Instructs `dnsmasq` to emit an authoritative Time-To-Live of 30 seconds on custom records.
- **Forwarders:** Upstream queries outside `teamabs.test` forward to Cloudflare (`1.1.1.1`) and Google (`8.8.8.8`).

### 2.2 Backup DNS Configuration ([`backup-dnsmasq.conf`](backup-dnsmasq.conf))
- **Listen Address:** `10.7.16.91` bound to interface `en0`.
- **Mirror Records:** Maintains identical authoritative mappings as the primary resolver to guarantee consistent namespace resolution regardless of which resolver answers.

### 2.3 Why `local-ttl=30` is Used
In production architectures, DNS TTL involves a fundamental operational balance:
1. **Low TTL (30 seconds):** Minimizes cache staleness, enabling rapid disaster recovery and traffic migration (demonstrated in Extensions B and E). If a node fails or an IP changes, client caches expire within 30 seconds.
2. **High TTL (e.g. 86400 seconds / 24 hours):** Maximizes caching efficiency and reduces recursive resolver query loads, but prevents rapid operational traffic steering.
3. **Phase 2 Choice:** `local-ttl=30` is ideal for high-availability private infrastructure: it demonstrates rapid record propagation during maintenance and tests without overwhelming the local `dnsmasq` instances.

---

## 3. Service Lifecycle Management

### 3.1 Syntax Validation
Before starting or reloading, validate the configuration syntax:
```bash
# On Mac 01 (or using explicit Homebrew path):
sudo /opt/homebrew/sbin/dnsmasq --test -C 02_DNS/Phase2/primary-dnsmasq.conf

# On Mac 03:
sudo /opt/homebrew/sbin/dnsmasq --test -C 02_DNS/Phase2/backup-dnsmasq.conf
```
*Expected Output: `dnsmasq: syntax check OK.`*

### 3.2 Starting `dnsmasq`
On **Mac 01 (Primary DNS — Shubham)**:
```bash
sudo /opt/homebrew/sbin/dnsmasq -C 02_DNS/Phase2/primary-dnsmasq.conf -d
```

On **Mac 03 (Backup DNS — Bhavya)**:
```bash
sudo /opt/homebrew/sbin/dnsmasq -C 02_DNS/Phase2/backup-dnsmasq.conf -d
```
*(The `-d` flag keeps dnsmasq in foreground debug mode to log all incoming queries in real time. Omit `-d` to run in background).*

### 3.3 Stopping `dnsmasq` and Verifying Port Release
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

## 4. Client Resolver Ordering (macOS)

For client nodes to leverage automatic primary-to-backup failover, both resolvers must be configured in order of preference:

```bash
# 1. Set primary (10.7.21.236) and backup (10.7.16.91) on macOS client
sudo networksetup -setdnsservers Wi-Fi 10.7.21.236 10.7.16.91

# 2. Verify configured resolvers on Wi-Fi service
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
Expected excerpt under `resolver #1`:
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

### 5.1 Querying Specific Resolvers with `dig` (Normal State)
```bash
# Test Primary Resolver explicitly
dig @10.7.21.236 app.teamabs.test +noall +answer
# Output: app.teamabs.test. 30 IN A 10.7.9.208

dig @10.7.21.236 api.teamabs.test +noall +answer
# Output: api.teamabs.test. 30 IN A 10.7.9.208

# Test Backup Resolver explicitly
dig @10.7.16.91 app.teamabs.test +noall +answer
# Output: app.teamabs.test. 30 IN A 10.7.9.208

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
   **Observation:** The client attempts to query the primary, times out after the resolver retry threshold, and falls back to the backup resolver (`10.7.16.91`), which returns `10.7.9.208` with TTL 30.
4. **End-to-End Application Validation:**
   ```bash
   curl -i http://app.teamabs.test:8080/api/status
   ```
   HTTP 200 OK is received without client failure.
5. **Restore Primary Resolver:**
   On Mac 01, restart `dnsmasq`:
   ```bash
   sudo /opt/homebrew/sbin/dnsmasq -C 02_DNS/Phase2/primary-dnsmasq.conf -d
   ```
   Resolution immediately resumes using the restored primary resolver.

---

## 7. Extension B: DNS TTL Dynamics & Observed Client Cache Behavior

### Configured TTL Verification
Executing `dig @10.7.21.236 app.teamabs.test` confirms:
```text
;; ANSWER SECTION:
app.teamabs.test.    30    IN    A    10.7.9.208
```

### Controlled Record Modification & Client Cache Observation
1. During Extension B, the `app.teamabs.test` record was modified to test cache invalidation:
   - Initial query: `10.7.9.208`.
   - Record modified on DNS server to `10.7.16.91`.
   - Client observed cached resolution transition recorded at `08:49:29`.
2. To manually flush local macOS client DNS cache during testing:
   ```bash
   sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
   ```
3. Following all tests, records on both servers were restored to `10.7.9.208`.
