# TeamABS Project Documentation Index

This directory contains the formal technical documentation, engineering reports, and specification indices for the TeamABS Computer Networks project across both Phase 1 and Phase 2.

---

## Deliverables & Documentation Index

| Deliverable | Phase | File Format | Scope / Description | Status / Link |
|---|---|---|---|---|
| **Phase 1 Formal Report** | Phase 1 | PDF (36 Pages) | Original historical 36-page report covering Tasks A through H | [`documentation.pdf`](documentation.pdf) |
| **Phase 2 Technical Report** | Phase 2 | Markdown / PDF | Comprehensive formal technical engineering report covering Extensions A through E | *Phase 2 documentation deliverable* |

---

## Phase 2 Report Structure Overview

The Phase 2 engineering report is structured into 20 formal technical sections:

1. **Title Page & Engineering Roles:** Inventory of nodes, IP addresses, and responsibilities for Shubham, Atharva, and Bhavya.
2. **Abstract:** Summary of multi-tier resilience, active-passive failover, and OS caching dynamics.
3. **Introduction:** Architectural motivations for decoupling DNS, reverse proxying, and origin microservices.
4. **Phase 1 Architecture Summary:** Baseline establishment of private LAN, PKI, caching, and round-robin Nginx.
5. **Phase 2 Objectives:** Fault-injection goals across Extensions A through E.
6. **Updated Network Topology:** Comprehensive physical/logical network map, listening ports, and DNS mappings.
7. **Team Member Responsibilities:** Detailed task distribution.
8. **Extension A — Backup DNS Architecture & Failover:** Active-passive `dnsmasq` resolvers and client resolver ordering.
9. **Extension B — DNS TTL and Record Modification:** 30-second TTL configuration, propagation, and client cache invalidation analysis.
10. **Extension C — Firewall Isolation (PF):** Origin perimeter protection, anchor definitions, and the Bhavya standby edge exception.
11. **Extension D — Backend High Availability:** Dynamic health detection (`max_fails=1 fail_timeout=5s`) and transparent rerouting.
12. **Extension E — Edge Reverse Proxy Migration:** Standby Nginx deployment, TLS certificate mirroring, and edge failover.
13. **Testing Methodology:** Multi-tier verification procedures across Layers 3, 4, and 7.
14. **Test Results Matrix:** Comprehensive test status across all evaluated scenarios.
15. **Limitations and Deviations:** Transparent documentation of client-side DNS caching behavior and topology constraints.
16. **Troubleshooting Observations:** Practical macOS networking, PF anchor management, and Nginx error-handling insights.
17. **Security Considerations:** Origin isolation, attack surface reduction, and TLS credential hygiene.
18. **Learning Outcomes:** Practical insights gained in distributed network systems.
19. **Conclusion:** Final engineering assessment of system availability and defense.
20. **References & Evidence Index:** Direct mappings to repository configurations, evidence logs, and slide plans.
