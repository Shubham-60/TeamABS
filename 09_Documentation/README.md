# Computer Networks Project Documentation (Phase 1)

**Team Name:** TeamABS  
**Team Members & Roles:**
- **Shubham Aggarwal** (Mac 01): Private DNS Server (`dnsmasq`), Test Client, Backend Service A
- **Atharva Sharma** (Mac 02): Nginx Edge, Reverse Proxy, Load Balancer, TLS/HTTPS Termination
- **Bhavya Punj** (Mac 03): Backend Service B

---

## Executive Summary & Deliverables

This repository implements an end-to-end distributed system across three physical Mac systems on a private local network (`10.7.0.0/19`).

The implementation covers all phases specified in the project specification:
1. **Task A: Private LAN Establishment** — Static network configuration, ARP resolution, and inter-node reachability.
2. **Task B: Private DNS Infrastructure** — `dnsmasq` deployment on Mac 01 resolving `app.teamabs.test` and `api.teamabs.test` to the edge proxy.
3. **Task C: Backend Microservices** — Python REST services for Backend A (Port 3001) and Backend B (Port 3002) emitting customized headers.
4. **Task D: Edge Reverse Proxy & Load Balancing** — Nginx configuration implementing Round-Robin balancing and proxy header propagation.
5. **Task E: Custom PKI & TLS Termination** — Private Root CA creation, SAN certificate issuance, trust store installation, and TLS 1.2 termination on port 8443.
6. **Task F: HTTP Caching Semantics** — Implementation of `Cache-Control: max-age=60`, `ETag: "teamabs-v1"`, and conditional `304 Not Modified` handling.
7. **Task G: Full-Stack Wireshark Protocol Verification** — Packet capture analysis across DNS (UDP 53), TCP 3-way handshake, TLS 1.2 handshake, and cleartext internal proxy traffic.
8. **Task H: Systematic Fault-Injection Testing** — 5 controlled failure scenarios validating network isolation, directory mapping, backend redundancy, and transport port semantics.

---

## Directory Reference Map

- [01_Architecture/](../01_Architecture/): Physical network topology diagrams and IP address inventories.
- [02_DNS/](../02_DNS/): `dnsmasq.conf` DNS configuration and resolution setup.
- [03_Backends/](../03_Backends/): Source code for Backend A (`backend_A/server.py`) and Backend B (`Backend_B/server.py`).
- [04_Nginx/](../04_Nginx/): Reverse proxy and round-robin load balancer configuration (`nginx.conf`).
- [05_TLS/](../05_TLS/): SSL configuration (`nginx_tls.conf`), SAN configuration (`san.cnf`), and certificate management commands.
- [06_Caching/](../06_Caching/): Header logs and conditional validation outputs (`cache_headers.txt`).
- [07_Wireshark/](../07_Wireshark/): Wireshark packet capture analysis, filter reference, and protocol flow documentation.
- [08_Failures/](../08_Failures/): Failure injection scenarios, observations, and networking root-cause analysis.
- [documentation.pdf](documentation.pdf): Complete 36-page formal PDF report.
