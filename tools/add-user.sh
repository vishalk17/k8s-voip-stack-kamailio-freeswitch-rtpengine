#!/bin/bash
# Kamailio user creation script
# Author: https://github.com/metinagaoglu/

# Usage check
if [ $# -lt 2 ]; then
    echo "Usage: $0 <username> <password> [domain]"
    echo "Example: $0 alice alice123"
    echo "Example: $0 bob bob456 kamailio.org"
    exit 1
fi

USERNAME=$1
PASSWORD=$2
DOMAIN=${3:-kamailio}   # Default domain: kamailio

# Generate HA1 and HA1B hashes (used by Kamailio for SIP auth)
HA1=$(echo -n "${USERNAME}:${DOMAIN}:${PASSWORD}" | md5sum | awk '{print $1}')
HA1B=$(echo -n "${USERNAME}@${DOMAIN}:${DOMAIN}:${PASSWORD}" | md5sum | awk '{print $1}')

# SQL query to insert/update user
SQL="
INSERT INTO subscriber (username, domain, password, ha1, ha1b)
VALUES ('${USERNAME}', '${DOMAIN}', '${PASSWORD}', '${HA1}', '${HA1B}')
ON CONFLICT (username, domain)
DO UPDATE SET password='${PASSWORD}', ha1='${HA1}', ha1b='${HA1B}';
"

# Execute SQL inside the postgres container
docker-compose exec -T postgres \
    psql -U kamailio -d kamailio -c "$SQL"

if [ $? -eq 0 ]; then
    echo "✓ User successfully added/updated:"
    echo "  Username : ${USERNAME}"
    echo "  Domain   : ${DOMAIN}"
    echo "  Password : ${PASSWORD}"
    echo ""
    echo "SIP Client Settings:"
    echo "  SIP Server  : localhost:5060"
    echo "  Username    : ${USERNAME}"
    echo "  Password    : ${PASSWORD}"
    echo "  Realm/Domain: ${DOMAIN}"
else
    echo "✗ ERROR: Failed to create or update the user!"
    exit 1
fi
