#!/bin/bash
# Kamailio user creation script
# Maintainer: vishalk17

###############################################
# Usage check
###############################################
if [ $# -lt 2 ]; then
    echo "Usage: $0 <username> <password> [domain]"
    echo "Example: $0 alice alice123"
    echo "Example: $0 bob bob456 kamailio.org"
    exit 1
fi

USERNAME=$1
PASSWORD=$2
DOMAIN=${3:-kamailio}   # Default domain: kamailio

###############################################
# Detect PostgreSQL pod
###############################################
PG_POD=$(kubectl -n sip get pods -l app=postgres -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

# Fallback: if label not found, try matching name manually
if [ -z "$PG_POD" ]; then
    PG_POD=$(kubectl -n sip get pods --no-headers | awk '/postgres/{print $1}' | head -1)
fi

# Final validation
if [ -z "$PG_POD" ]; then
    echo "✗ ERROR: Could not find the PostgreSQL pod in namespace 'sip'."
    echo "Please check:"
    echo "  - PostgreSQL is deployed"
    echo "  - Namespace is correct"
    echo "  - Pod label app=postgres exists"
    exit 1
fi

echo "✓ PostgreSQL pod detected: $PG_POD"
echo ""

###############################################
# Generate HA1 and HA1B hashes
###############################################
HA1=$(echo -n "${USERNAME}:${DOMAIN}:${PASSWORD}" | md5sum | awk '{print $1}')
HA1B=$(echo -n "${USERNAME}@${DOMAIN}:${DOMAIN}:${PASSWORD}" | md5sum | awk '{print $1}')

###############################################
# Prepare SQL query
###############################################
SQL="
INSERT INTO subscriber (username, domain, password, ha1, ha1b)
VALUES ('${USERNAME}', '${DOMAIN}', '${PASSWORD}', '${HA1}', '${HA1B}')
ON CONFLICT (username, domain)
DO UPDATE SET password='${PASSWORD}', ha1='${HA1}', ha1b='${HA1B}';
"

###############################################
# Execute SQL inside container
###############################################
kubectl -n sip exec -i "$PG_POD" -- \
    psql -U kamailio -d kamailio -c "$SQL"

###############################################
# Result
###############################################
if [ $? -eq 0 ]; then
    echo ""
    echo "✓ User successfully added/updated:"
    echo "  Username : ${USERNAME}"
    echo "  Domain   : ${DOMAIN}"
    echo "  Password : ${PASSWORD}"
    echo ""
    echo "SIP Client Settings:"
    echo "  SIP Server   : localhost:5060"
    echo "  Username     : ${USERNAME}"
    echo "  Password     : ${PASSWORD}"
    echo "  Realm/Domain : ${DOMAIN}"
else
    echo "✗ ERROR: Failed to create or update the user!"
    exit 1
fi

