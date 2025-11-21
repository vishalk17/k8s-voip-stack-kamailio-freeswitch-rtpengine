# Base Kamailio image (Debian Bookworm)
FROM ghcr.io/kamailio/kamailio:6.0.4-bookworm

# Install additional tools and modules
RUN apt-get update && apt-get install -y \
    sngrep \
    kamailio-postgres-modules \
    kamailio-extra-modules \
    && rm -rf /var/lib/apt/lists/*

# Copy Kamailio configuration files
COPY kamailio.cfg /etc/kamailio/kamailio.cfg
COPY dispatcher.list /etc/kamailio/dispatcher.list

# Validate Kamailio configuration
# If config has an error, show the error line and fail the build
RUN kamailio -c -f /etc/kamailio/kamailio.cfg || \
    ( echo "=== CONFIG ERROR ===" && \
      cat -n /etc/kamailio/kamailio.cfg | \
      grep -A5 -B5 "$(kamailio -c -f /etc/kamailio/kamailio.cfg 2>&1 \
        | grep 'line' | head -1 | sed 's/.*line \([0-9]*\).*/\1/')" && \
      exit 1 )

# Start Kamailio in foreground mode with debugging enabled
CMD ["kamailio", "-DD", "-E", "-f", "/etc/kamailio/kamailio.cfg"]
