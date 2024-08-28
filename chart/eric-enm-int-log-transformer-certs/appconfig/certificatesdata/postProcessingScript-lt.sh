#!/bin/bash

CREDM_DATA_XML="log-transformer-cert-request.xml"
LT_SECRET_NAME="eric-log-transformer-asymmetric-secret"
LT_TRUSTSTORE_SECRET_NAME="eric-log-transformer-trusted-external-secret"

CREDM_TLS_KEY_SECRET_NAME="eric-log-transformer-tls-secret-1"
CREDM_TLS_CRT_SECRET_NAME="eric-log-transformer-tls-secret-2"
CREDM_TRUSTED_CRT_SECRET_NAME="eric-log-transformer-tls-secret-3"

CREDM_LT_KEY_PATH="/ericsson/logtransformer/eric-enm-log-transformer.key"
CREDM_LT_CRT_PATH="/ericsson/logtransformer/eric-enm-log-transformer.crt"
CREDM_LT_TRUSTED_CRT_PATH="/ericsson/logtransformer/eric-enm-log-transformer-trust.pem"

ROLLOUT_RESTART_FLAG=0

echo "EXECUTION POST_CREDM SCRIPT for ${CREDM_DATA_XML}"
now=$(date +"%T")
echo "Current time : $now"
echo "-------------------"

echo "EXECUTION SCRIPTS IN POST_CREDM for ${CREDM_DATA_XML} at $now"

# check if lt tls secret already exists
lt_secret_exists=$(kubectl get secret -n "${NAMESPACE}" | grep -c ${LT_SECRET_NAME})
lt_truststore_secret_exists=$(kubectl get secret -n "${NAMESPACE}" | grep -c ${LT_TRUSTSTORE_SECRET_NAME})

# check if credential manager secret already exists
credm_tls_key_secret_exists=$(kubectl get secret -n "${NAMESPACE}" | grep -c ${CREDM_TLS_KEY_SECRET_NAME})
credm_tls_crt_secret_exists=$(kubectl get secret -n "${NAMESPACE}" | grep -c ${CREDM_TLS_CRT_SECRET_NAME})
credm_trust_crt_secret_exists=$(kubectl get secret -n "${NAMESPACE}" | grep -c ${CREDM_TRUSTED_CRT_SECRET_NAME})

if [[ $credm_tls_key_secret_exists == 0 && $credm_tls_crt_secret_exists == 0 && $credm_trust_crt_secret_exists ]]; then
  echo "Credential manager secret doesn't exist"
  exit 0;
fi

# read secrets data
SECRET1_KEY_LOCATION=$(kubectl get secrets/$CREDM_TLS_KEY_SECRET_NAME -n "$NAMESPACE" -ojsonpath='{.data.tlsStoreLocation}' | base64 -d)
SECRET2_CRT_LOCATION=$(kubectl get secrets/$CREDM_TLS_CRT_SECRET_NAME -n "$NAMESPACE" -ojsonpath='{.data.tlsStoreLocation}' | base64 -d)
SECRET3_TRUSTED_CRT_LOCATION=$(kubectl get secrets/$CREDM_TRUSTED_CRT_SECRET_NAME -n "$NAMESPACE" -ojsonpath='{.data.tlsStoreLocation}' | base64 -d)

echo "SECRET1_KEY_LOCATION=$SECRET1_KEY_LOCATION"
if [[ $SECRET1_KEY_LOCATION == "$CREDM_LT_KEY_PATH" ]]; then
    TLS_KEY_BASE64=$(kubectl get secret ${CREDM_TLS_KEY_SECRET_NAME} -n "${NAMESPACE}" -ojsonpath='{.data.tlsStoreData}')
fi

echo "SECRET2_CRT_LOCATION=$SECRET2_CRT_LOCATION"
if [[ $SECRET2_CRT_LOCATION == "$CREDM_LT_CRT_PATH" ]]; then
	  TLS_CRT_BASE64=$(kubectl get secret ${CREDM_TLS_CRT_SECRET_NAME} -n "${NAMESPACE}" -ojsonpath='{.data.tlsStoreData}')
fi

echo "SECRET3_TRUSTED_CRT_LOCATION=$SECRET3_TRUSTED_CRT_LOCATION"
if [[ $SECRET3_TRUSTED_CRT_LOCATION == "$CREDM_LT_TRUSTED_CRT_PATH" ]]; then
	  TRUSTED_CRT_BASE64=$(kubectl get secret ${CREDM_TRUSTED_CRT_SECRET_NAME} -n "${NAMESPACE}" -ojsonpath='{.data.tlsStoreData}')
fi

# if no secrets exist
if [[ $lt_secret_exists == 0 ]]; then
    echo "Secret doesn't exist: creating eric-log-transformer-asymmetric-secret"
    kubectl create secret generic ${LT_SECRET_NAME} -n "${NAMESPACE}" --from-literal=tls.key="" --from-literal=tls.crt=""
    kubectl patch secret ${LT_SECRET_NAME} -n "${NAMESPACE}" -p="{\"data\":{\"tls.crt\":\"${TLS_CRT_BASE64}\",\"tls.key\":\"${TLS_KEY_BASE64}\"}}" 2>/dev/null
    if [[ $? -ne 0 ]]; then
        echo "error creating ${LT_SECRET_NAME}, exiting..."
        exit 1
    fi
    ROLLOUT_RESTART_FLAG=1
    echo "Created eric-log-transformer-asymmetric-secret successfully and updated rollout restart flag"
else
    # check if key or cert have been updated and update existing tls secret's data
    echo "Secret exist: updating eric-log-transformer-asymmetric-secret"
    current_tls_key=$(kubectl get secret ${LT_SECRET_NAME} -n "${NAMESPACE}" -ojsonpath='{.data.tls\.key}')
    current_tls_cert=$(kubectl get secret ${LT_SECRET_NAME} -n "${NAMESPACE}" -ojsonpath='{.data.tls\.crt}')
    current_tls_data="${current_tls_key}${current_tls_cert}"
    if [[ $current_tls_data != "${TLS_KEY_BASE64}${TLS_CRT_BASE64}" ]]; then
        kubectl patch secret ${LT_SECRET_NAME} -n "${NAMESPACE}" -p="{\"data\":{\"tls.crt\":\"${TLS_CRT_BASE64}\",\"tls.key\":\"${TLS_KEY_BASE64}\"}}" 2>/dev/null
        if [[ $? -ne 0 ]]; then
            echo "error patching ${LT_SECRET_NAME}, exiting..."
            exit 1
        fi
        ROLLOUT_RESTART_FLAG=1
        echo "Patched eric-log-transformer-asymmetric-secret successfully and updated rollout restart flag"
    else
       echo "Secrete values remain unchanged"
    fi
fi

if [[ $lt_truststore_secret_exists == 0 ]]; then
    echo "Secret doesn't exist: creating eric-log-transformer-trusted-external-secret"
    kubectl create secret generic ${LT_TRUSTSTORE_SECRET_NAME} -n "${NAMESPACE}" --from-literal=trustedcert=""
    kubectl patch secret ${LT_TRUSTSTORE_SECRET_NAME} -n "${NAMESPACE}" -p="{\"data\":{\"trustedcert\":\"${TRUSTED_CRT_BASE64}\"}}" 2>/dev/null
    if [[ $? -ne 0 ]]; then
        echo "error creating ${SECRET_NAME}, exiting..."
        exit 1
    fi
    ROLLOUT_RESTART_FLAG=1
    echo "Created eric-log-transformer-trusted-external-secret successfully and updated rollout restart flag"
else
    # check if key or cert have been updated and update existing tls secret's data
    echo "Secret exist: updating eric-log-transformer-trusted-external-secret"
    current_trusted_cert=$(kubectl get secret ${LT_TRUSTSTORE_SECRET_NAME} -n "${NAMESPACE}" -ojsonpath='{.data.trustedcert}')
    if [[ $current_trusted_cert != "${TRUSTED_CRT_BASE64}" ]]; then
        kubectl patch secret ${LT_TRUSTSTORE_SECRET_NAME} -n "${NAMESPACE}" -p="{\"data\":{\"trustedcert\":\"${TRUSTED_CRT_BASE64}\"}}" 2>/dev/null
        if [[ $? -ne 0 ]]; then
            echo "error patching ${LT_TRUSTSTORE_SECRET_NAME}, exiting..."
            exit 1
        fi
        ROLLOUT_RESTART_FLAG=1
        echo "Patched eric-log-transformer-trusted-external-secret successfully and updated rollout restart flag"
    else
       echo "Secrete values remain unchanged"
    fi
fi

echo "ROLLOUT_RESTART_FLAG : $ROLLOUT_RESTART_FLAG"
if [[ $ROLLOUT_RESTART_FLAG == 1 ]]; then
   kubectl rollout restart deployment eric-log-transformer -n "${NAMESPACE}" 2>/dev/null
    if [[ $? -ne 0 ]]; then
      echo "error restarting eric-log-transformer, exiting..."
      exit 1
    fi
fi
exit 0