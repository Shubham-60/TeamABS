# Task D: Edge Reverse Proxy & Load Balancer

This directory contains the Nginx reverse proxy and round-robin load balancer configuration deployed on Mac 02 (`10.7.9.208`).

---

## 1. Architectural Role

Mac 02 acts as the single public entry point for all client requests targeting `app.teamabs.test`. Clients never communicate directly with backend nodes.

- **Primary Configuration File:** [`nginx.conf`](nginx.conf)
- **Ports:**
  - `8080`: Plaintext HTTP entry point
  - `8443`: Encrypted HTTPS entry point with TLS termination

---

## 2. Upstream Definition & Load Balancing Strategy

```nginx
upstream teamabs_backends {
    server 10.7.21.236:3001;  # Backend A (Mac 01)
    server 10.7.16.91:3002;   # Backend B (Mac 03)
}
```

Nginx employs default **Round-Robin** distribution, alternating traffic sequentially between Backend A and Backend B.

### Injected Proxy Headers
Nginx decorates proxied requests to maintain client identity and protocol context:
- `Host $host`
- `X-Real-IP $remote_addr`
- `X-Forwarded-For $proxy_add_x_forwarded_for`
- `X-Forwarded-Proto $scheme`

---

## 3. Starting & Reloading Nginx

On **Mac 02**:
```bash
# Test configuration syntax
sudo nginx -t

# Start / Reload Nginx
sudo nginx -s reload
```

---

## 4. Load Balancing Verification

Execute repeated requests from a client to verify the alternating `X-Backend` header:
```bash
for i in {1..10}; do
  curl -s -D - https://app.teamabs.test:8443/api/status -o /dev/null | grep -i '^X-Backend:'
done
```
**Expected Output:**
```
X-Backend: A
X-Backend: B
X-Backend: A
X-Backend: B
...
```

---

## 5. Architectural Benefit: Why Hide Backend IPs?

1. **Security & Attack Surface Reduction:** Backends do not expose public ports or receive unfiltered client traffic.
2. **Horizontal Scalability:** Origin servers can be added or decommissioned dynamically without modifying client DNS configurations.
3. **Centralized TLS Termination:** Cryptographic overhead and certificate management are handled once at the edge.
