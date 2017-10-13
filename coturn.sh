#!/bin/bash

# Discover public and private IP for this instance
[ -n "$PUBLIC_IPV4" ] || PUBLIC_IPV4="$(curl -4 https://icanhazip.com/)"
[ -n "$PUBLIC_IPV4" ] || PUBLIC_IPV4="$(curl -qs ipinfo.io/ip)" || exit 1
[ -n "$PRIVATE_IPV4" ] || PRIVATE_IPV4=$(ifconfig | awk '/inet addr/{print substr($2,6)}' | grep -v 127.0.0.1 | tail -n1)
[ -n "$PRIVATE_IPV4" ] || PRIVATE_IPV4="$(ip addr show eth0 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1 | head -n1)" || exit 1

# Yes, this does work. See: https://github.com/ianblenke/aws-6to4-docker-ipv6
#IPV6="$(ip -6 addr show eth0 scope global | grep inet6 | awk '{print $2}')"

PORT=${PORT:-3478}
ALT_PORT=${PORT:-3479}

TLS_PORT=${TLS:-5349}
TLS_ALT_PORT=${PORT:-5350}

MIN_PORT=${MIN_PORT:-49152}
MAX_PORT=${MAX_PORT:-65535}

TURNSERVER_CONFIG=/etc/turnserver.conf

cat <<EOF > ${TURNSERVER_CONFIG}-template
# https://github.com/coturn/coturn/blob/master/examples/etc/turnserver.conf
listening-port=${PORT}
alt-listening-port=${ALT_PORT}
min-port=${MIN_PORT}
max-port=${MAX_PORT}
EOF

if [ "${PUBLIC_IPV4}" != "${PRIVATE_IPV4}" ]; then
  echo "external-ip=${PUBLIC_IPV4}/${PRIVATE_IPV4}" >> ${TURNSERVER_CONFIG}-template
else
  echo "external-ip=${PUBLIC_IPV4}" >> ${TURNSERVER_CONFIG}-template
fi

if [ -n "${JSON_CONFIG}" ]; then
  echo "${JSON_CONFIG}" | jq -r '.config[]' >> ${TURNSERVER_CONFIG}-template
fi

if [ -n "$SSL_CERTIFICATE" ]; then
  echo "$SSL_CA_CHAIN" > /etc/turn_server_cert.pem
  echo "$SSL_CERTIFICATE" >> /etc/turn_server_cert.pem
  echo "$SSL_PRIVATE_KEY" > /etc/turn_server_pkey.pem

  cat <<EOT >> ${TURNSERVER_CONFIG}-template
tls-listening-port=${TLS_PORT}
alt-tls-listening-port=${TLS_ALT_PORT}
cert=/etc/turn_server_cert.pem
pkey=/etc/turn_server_pkey.pem
EOT

fi

# Allow for ${VARIABLE} substitution using envsubst from gettext
envsubst < ${TURNSERVER_CONFIG}-template > ${TURNSERVER_CONFIG}

exec /usr/local/bin/turnserver "$@"
