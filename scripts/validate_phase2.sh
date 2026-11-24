#!/usr/bin/env bash
# TeamABS Phase 2 — Non-Disruptive Local Validation Script
# Performs read-only syntax, compilation, and configuration checks.
# This script does NOT stop/restart services, modify network state, or touch private keys.

set -uo pipefail

BOLD="\033[1m"
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
BLUE="\033[34m"
RESET="\033[0m"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

echo -e "${BOLD}${BLUE}======================================================${RESET}"
echo -e "${BOLD}${BLUE}   TeamABS Phase 2 — Local Technical Validation Tool   ${RESET}"
echo -e "${BOLD}${BLUE}======================================================${RESET}"
echo -e "Repository Root: ${REPO_ROOT}\n"

PASS_COUNT=0
SKIP_COUNT=0
FAIL_COUNT=0

log_pass() {
    echo -e "  [${GREEN}PASS${RESET}] $1"
    ((PASS_COUNT++))
}

log_skip() {
    echo -e "  [${YELLOW}SKIP${RESET}] $1 ($2)"
    ((SKIP_COUNT++))
}

log_fail() {
    echo -e "  [${RED}FAIL${RESET}] $1 ($2)"
    ((FAIL_COUNT++))
}

# ---------------------------------------------------------
# Check 1: Required File Presence
# ---------------------------------------------------------
echo -e "${BOLD}1. Verifying Core File Inventory...${RESET}"
REQUIRED_FILES=(
    "02_DNS/Phase2/primary-dnsmasq.conf"
    "02_DNS/Phase2/backup-dnsmasq.conf"
    "02_DNS/Phase2/README.md"
    "03_Backends/backend_A/server.py"
    "03_Backends/Backend_B/server.py"
    "04_Nginx/Phase2/primary-edge.conf"
    "04_Nginx/Phase2/standby-edge.conf"
    "04_Nginx/Phase2/README.md"
    "05_TLS/san.cnf"
    "05_TLS/README.md"
    "10_Firewall/shubham-teamabs.anchor"
    "10_Firewall/bhavya-teamabs.anchor"
    "10_Firewall/README.md"
    "README.md"
)

ALL_FILES_EXIST=true
for f in "${REQUIRED_FILES[@]}"; do
    if [[ ! -f "$f" ]]; then
        log_fail "File Missing: $f" "File not found in repository"
        ALL_FILES_EXIST=false
    fi
done
if $ALL_FILES_EXIST; then
    log_pass "All core Phase 2 configuration and source files are present"
fi

# ---------------------------------------------------------
# Check 2: Python Backend Syntax
# ---------------------------------------------------------
echo -e "\n${BOLD}2. Validating Python Microservices Syntax...${RESET}"
if command -v python3 >/dev/null 2>&1; then
    if python3 -m py_compile 03_Backends/backend_A/server.py 03_Backends/Backend_B/server.py 2>/dev/null; then
        log_pass "Python backend syntax compiled cleanly (Backend A & B)"
    else
        log_fail "Python backend compilation failed" "Check server.py syntax"
    fi
else
    log_skip "Python syntax compilation" "python3 executable not found in PATH"
fi

# ---------------------------------------------------------
# Check 3: dnsmasq Configuration Syntax
# ---------------------------------------------------------
echo -e "\n${BOLD}3. Validating dnsmasq Configuration Syntax...${RESET}"
DNSMASQ_BIN=""
for candidate in "dnsmasq" "/opt/homebrew/sbin/dnsmasq" "/opt/homebrew/opt/dnsmasq/sbin/dnsmasq"; do
    if command -v "$candidate" >/dev/null 2>&1 || [[ -x "$candidate" ]]; then
        DNSMASQ_BIN="$candidate"
        break
    fi
done

if [[ -n "$DNSMASQ_BIN" ]]; then
    if "$DNSMASQ_BIN" --test -C 02_DNS/Phase2/primary-dnsmasq.conf >/dev/null 2>&1; then
        log_pass "primary-dnsmasq.conf syntax valid"
    else
        log_fail "primary-dnsmasq.conf syntax check failed" "Check configuration"
    fi

    if "$DNSMASQ_BIN" --test -C 02_DNS/Phase2/backup-dnsmasq.conf >/dev/null 2>&1; then
        log_pass "backup-dnsmasq.conf syntax valid"
    else
        log_fail "backup-dnsmasq.conf syntax check failed" "Check configuration"
    fi
else
    log_skip "dnsmasq syntax check" "dnsmasq binary not installed on this node (normal on edge nodes)"
fi

# ---------------------------------------------------------
# Check 4: Nginx Syntax
# ---------------------------------------------------------
echo -e "\n${BOLD}4. Validating Nginx Edge Configuration...${RESET}"
NGINX_BIN=""
for candidate in "nginx" "/opt/homebrew/bin/nginx"; do
    if command -v "$candidate" >/dev/null 2>&1 || [[ -x "$candidate" ]]; then
        NGINX_BIN="$candidate"
        break
    fi
done

if [[ -n "$NGINX_BIN" ]]; then
    if "$NGINX_BIN" -t >/dev/null 2>&1; then
        log_pass "Local Nginx global configuration syntax valid (nginx -t)"
    else
        log_fail "Local Nginx configuration check failed" "Inspect /opt/homebrew/etc/nginx/nginx.conf"
    fi
else
    log_skip "Nginx global syntax check" "nginx not installed on this node (normal on Mac 01 DNS node)"
fi

# ---------------------------------------------------------
# Check 5: OpenSSL SAN Configuration Syntax
# ---------------------------------------------------------
echo -e "\n${BOLD}5. Validating OpenSSL SAN Configuration...${RESET}"
if command -v openssl >/dev/null 2>&1; then
    if grep -q "DNS.1 = app.teamabs.test" 05_TLS/san.cnf && grep -q "DNS.2 = api.teamabs.test" 05_TLS/san.cnf; then
        log_pass "san.cnf contains dual SAN entries (app.teamabs.test and api.teamabs.test)"
    else
        log_fail "san.cnf SAN entries incomplete" "Expected both app and api entries"
    fi
else
    log_skip "OpenSSL configuration check" "openssl binary not found"
fi

# ---------------------------------------------------------
# Check 6: Markdown Documentation Relative Links
# ---------------------------------------------------------
echo -e "\n${BOLD}6. Validating Markdown Relative Links...${RESET}"
if command -v python3 >/dev/null 2>&1; then
    BROKEN_LINKS=$(python3 -c "
import os, sys, re
link_pattern = re.compile(r'\[([^\]]+)\]\(([^)]+)\)')
md_files = []
for root, dirs, files in os.walk('.'):
    if '.git' in root: continue
    for f in files:
        if f.endswith('.md'): md_files.append(os.path.join(root, f))
errors = 0
for md in md_files:
    dir_path = os.path.dirname(md)
    with open(md, 'r', encoding='utf-8') as f: content = f.read()
    for text, target in link_pattern.findall(content):
        if target.startswith(('http://', 'https://', '#', 'mailto:')): continue
        clean = target.split('#')[0]
        if not clean: continue
        resolved = os.path.normpath(os.path.join(dir_path, clean))
        if not os.path.exists(resolved):
            errors += 1
print(errors)
")
    if [[ "$BROKEN_LINKS" == "0" ]]; then
        log_pass "All relative markdown documentation links resolve successfully (0 broken links)"
    else
        log_fail "Markdown link validation failed" "${BROKEN_LINKS} broken relative links found"
    fi
else
    log_skip "Markdown link validation" "python3 not found"
fi

# ---------------------------------------------------------
# Summary
# ---------------------------------------------------------
echo -e "\n${BOLD}${BLUE}======================================================${RESET}"
echo -e "${BOLD}Validation Summary:${RESET} ${GREEN}${PASS_COUNT} Passed${RESET} | ${YELLOW}${SKIP_COUNT} Skipped${RESET} | ${RED}${FAIL_COUNT} Failed${RESET}"
echo -e "${BOLD}${BLUE}======================================================${RESET}"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
    exit 1
fi
exit 0
