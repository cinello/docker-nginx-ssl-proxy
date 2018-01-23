#!/bin/bash
# Copyright 2015 Google Inc. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
#you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and

proxy_config () {
  SERVER_NAME=$1
  IS_MULTI=$2
  VAR_SERVER_NAME=$(echo -n ${SERVER_NAME} | sed -e 's/\./_/g')

  PROXY_FILE=/etc/nginx/conf.d/proxy_${VAR_SERVER_NAME}.conf

  # Env says we're using SSL
  if [ -n "${ENABLE_SSL+1}" ] && [ "${ENABLE_SSL,,}" = "true" ]; then
    echo "Enabling SSL for server ${SERVER_NAME}..."
    cp /usr/src/proxy_ssl.conf ${PROXY_FILE}
  else
    # No SSL
    cp /usr/src/proxy_nossl.conf ${PROXY_FILE}
  fi

  if [ -n "${IS_MULTI+1}" ] && [ "${IS_MULTI,,}" = "true" ]; then
    VAR_SERVICE_HOST_ENV_NAME=SERVICE_HOST_ENV_NAME_${VAR_SERVER_NAME}
    SERVICE_HOST_ENV_NAME=${!VAR_SERVICE_HOST_ENV_NAME}
    VAR_SERVICE_PORT_ENV_NAME=SERVICE_PORT_ENV_NAME_${VAR_SERVER_NAME}
    SERVICE_PORT_ENV_NAME=${!VAR_SERVICE_PORT_ENV_NAME}

    VAR_ENABLE_BASIC_AUTH=ENABLE_BASIC_AUTH_${VAR_SERVER_NAME}
    if [ -n "${!VAR_ENABLE_BASIC_AUTH+1}" ] && [ "${!VAR_ENABLE_BASIC_AUTH,,}" = "true" ]; then
      echo "Basic auth for this server ${SERVER_NAME} is active"
      ENABLE_BASIC_AUTH=${!VAR_ENABLE_BASIC_AUTH}
    else
      ENABLE_BASIC_AUTH="false"
    fi

    VAR_WEB_SOCKETS=WEB_SOCKETS_${VAR_SERVER_NAME}
    if [ -n "${!VAR_WEB_SOCKETS+1}" ] && [ "${!VAR_WEB_SOCKETS,,}" = "true" ]; then
      echo "Websockets for server ${SERVER_NAME} is active"
      WEB_SOCKETS=${!VAR_WEB_SOCKETS}
    else
      WEB_SOCKETS="false"
    fi

    VAR_CLIENT_MAX_BODY_SIZE=CLIENT_MAX_BODY_SIZE_${VAR_SERVER_NAME}
    if [ -n "${!VAR_CLIENT_MAX_BODY_SIZE+1}" ]; then
      echo "client_max_boby_size for server ${SERVER_NAME} is set"
      CLIENT_MAX_BODY_SIZE=${!VAR_CLIENT_MAX_BODY_SIZE}
    else
      unset CLIENT_MAX_BODY_SIZE
    fi
  fi

  # If an htpasswd file is provided, download and configure nginx
  if [ -n "${ENABLE_BASIC_AUTH+1}" ] && [ "${ENABLE_BASIC_AUTH,,}" = "true" ]; then
    echo "Enabling basic auth for server ${SERVER_NAME}..."
    sed -i "s/#auth_basic/auth_basic/g;" ${PROXY_FILE}
  fi

  # Set a custom client_max_body_size if provided
  if [ -n "${CLIENT_MAX_BODY_SIZE+1}" ]; then
    echo "Setting client_max_body_size for server ${SERVER_NAME} to ${CLIENT_MAX_BODY_SIZE}..."
    sed -i "s/client_max_body_size .*$/client_max_body_size ${CLIENT_MAX_BODY_SIZE};/g;" ${PROXY_FILE}
  fi

  # If the SERVICE_HOST_ENV_NAME and SERVICE_PORT_ENV_NAME vars are provided,
  # they point to the env vars set by Kubernetes that contain the actual
  # target address and port. Override the default with them.
  if [ -n "${SERVICE_HOST_ENV_NAME+1}" ]; then
    TARGET_SERVICE=${!SERVICE_HOST_ENV_NAME}
  fi
  if [ -n "${SERVICE_PORT_ENV_NAME+1}" ]; then
    TARGET_SERVICE="$TARGET_SERVICE:${!SERVICE_PORT_ENV_NAME}"
  fi

  # If the CERT_SERVICE_HOST_ENV_NAME and CERT_SERVICE_PORT_ENV_NAME vars
  # are provided, they point to the env vars set by Kubernetes that contain the
  # actual target address and port of the encryption service. Override the
  # default with them.
  if [ -n "${CERT_SERVICE_HOST_ENV_NAME+1}" ]; then
    CERT_SERVICE=${!CERT_SERVICE_HOST_ENV_NAME}
  fi
  if [ -n "${CERT_SERVICE_PORT_ENV_NAME+1}" ]; then
    CERT_SERVICE="$CERT_SERVICE:${!CERT_SERVICE_PORT_ENV_NAME}"
  fi

  if [ -n "${CERT_SERVICE+1}" ]; then
      # Tell nginx the address and port of the certification service.
    echo "Activate certification service for server ${SERVER_NAME}..."
    sed -i "s/{{CERT_SERVICE}}/${CERT_SERVICE}/g;" ${PROXY_FILE}
    sed -i "s/{{CERT_SERVICE}}/${CERT_SERVICE}/g;" /etc/nginx/conf.d/default.conf
    sed -i "s/#letsencrypt# //g;" ${PROXY_FILE}
    sed -i "s/#letsencrypt# //g;" /etc/nginx/conf.d/default.conf
  fi

  if [ -n "${WEB_SOCKETS+1}" ] && [ "${WEB_SOCKETS,,}" = "true" ]; then
    echo "Activate websockets service for server ${SERVER_NAME}..."
    sed -i "s/#websockets# //g;" ${PROXY_FILE}
  fi

  # Tell nginx the address and port of the service to proxy to
  echo "Set target service for server ${SERVER_NAME} to ${TARGET_SERVICE}..."
  sed -i "s|{{TARGET_SERVICE}}|${TARGET_SERVICE}|" ${PROXY_FILE}
  if [ -n "${IS_MULTI+1}" ] && [ "${IS_MULTI,,}" = "true" ]; then
    sed -i "s|{{TARGET_SERVICE_NAME}}|target_service_${VAR_SERVER_NAME}|" ${PROXY_FILE}
  else
    sed -i "s|{{TARGET_SERVICE_NAME}}|target_service|" ${PROXY_FILE}
  fi

  # Tell nginx the name of the service
  echo "Set server name for server ${SERVER_NAME}..."
  sed -i "s/{{SERVER_NAME}}/${SERVER_NAME}/g;" ${PROXY_FILE}
}

if [ -n "${ENABLE_SSL+1}" ] && [ "${ENABLE_SSL,,}" = "true" ]; then
  echo "Enabling SSL for default configuration..."
  cp /usr/src/default_ssl.conf /etc/nginx/conf.d/default.conf
else
  # No SSL
  cp /usr/src/default_nossl.conf /etc/nginx/conf.d/default.conf
fi

if [ -n "${SERVER_NAME+1}" ]; then
  proxy_config ${SERVER_NAME} "false"
fi

for SERVER_NAME in ${SERVER_NAMES}; do
  proxy_config ${SERVER_NAME} "true"
done

echo "Starting nginx..."
nginx -g 'daemon off;'
