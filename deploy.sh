#!/bin/bash

export KUBE_NAMESPACE=${KUBE_NAMESPACE}
export KUBE_SERVER=${KUBE_SERVER}

POISE_RANGES=62.25.109.196/32,52.209.62.128/25
GOVWIFI_RANGES=167.98.162.0/25,167.98.158.128/25
ACPTUNNEL_RANGES=52.56.221.216/32,18.130.11.142/32,18.130.6.5/32

log()
{
    if [[ $1 == ---* ]] ; then
        echo -e "\033[34m $1 \033[39m"
    elif [[ $1 == \[error\]* ]] ; then
        echo -e "\033[31m $1 \033[39m"
    else
        echo $1
    fi
}

if [[ -z ${VERSION} ]] ; then
    export VERSION=${IMAGE_VERSION}
fi

if [[ -z ${VERSION} ]] ; then
    log "[error] No version set!"
    exit 78
fi


if [[ ${ENVIRONMENT} == "pr" ]] ; then
    log "--- PRODUCTION PRODUCTION PRODUCTION"
    log "--- deploying ${VERSION} to pr namespace, using PTTG_RPS_PR drone secret"
    export KUBE_TOKEN=${PTTG_RPS_PR}
    export CA_URL="https://raw.githubusercontent.com/UKHomeOffice/acp-ca/master/acp-prod.crt"
    if [[ -z ${NOTIFY_RECIPIENT_PROD} ]] ; then
        log "[error] Deploying to production but NOTIFY_RECIPIENT_PROD not set"
        exit 78
    fi
    export NOTIFY_RECIPIENT=$NOTIFY_RECIPIENT_PROD
else
    export WHITELIST="${POISE_RANGES},${GOVWIFI_RANGES},${ACPTUNNEL_RANGES}"
    echo Using WHITELIST=$WHITELIST

    export CA_URL="https://raw.githubusercontent.com/UKHomeOffice/acp-ca/master/acp-notprod.crt"
    if [[ ${ENVIRONMENT} == "test" ]] ; then
        log "--- deploying ${VERSION} to test namespace, using PTTG_RPS_TEST drone secret"
        export KUBE_TOKEN=${PTTG_RPS_TEST}
    else
        log "--- deploying ${VERSION} to dev namespace, using PTTG_RPS_DEV drone secret"
        export KUBE_TOKEN=${PTTG_RPS_DEV}
    fi
    if [[ -z ${NOTIFY_RECIPIENT_NOTPROD} ]] ; then
        log "--- no NOTIFY_RECIPIENT set"
        log "--- using GOV.UK Notify integration test email"
        log "--- emails will pretend to send but won't show up on GOV.UK Notify dashboard"
        export NOTIFY_RECIPIENT_NOTPROD="simulate-delivered@notifications.service.gov.uk"
    fi
    export NOTIFY_RECIPIENT=$NOTIFY_RECIPIENT_NOTPROD
fi

log "--- emails are going to be sent to $NOTIFY_RECIPIENT"

if [[ -z ${KUBE_TOKEN} ]] ; then
    log "[error] Failed to find a value for KUBE_TOKEN - exiting"
    exit 78
elif [ ${#KUBE_TOKEN} -ne 36 ] ; then
    log "[error] Kubernetes token wrong length (expected 36, got ${#KUBE_TOKEN})"
    exit 78
fi

log "--- downloading certificate authority for Kubernetes API"
export KUBE_CERTIFICATE_AUTHORITY=/tmp/cert.crt
if ! wget --quiet $CA_URL -O $KUBE_CERTIFICATE_AUTHORITY; then
    log "[error] faled to download certificate authority!"
    exit 1
fi

if [ "${ENVIRONMENT}" == "pr" ] ; then
    export DNS_PREFIX=
    export KC_REALM=pttg-production
    export PROD_OR_NOTPROD=prod
    export DOMAIN_NAME=www.european-temporary-leave-to-remain-enquiries.service.gov.uk
else
    export DNS_PREFIX=${ENVIRONMENT}.notprod.
    export KC_REALM=pttg-qa
    export PROD_OR_NOTPROD=notprod
    export DOMAIN_NAME=enquiry-euro-tlr.${DNS_PREFIX}pttg.homeoffice.gov.uk


    if [[ -z ${BASIC_AUTH} ]] ; then
        log "[warn] BASIC_AUTH not set -- you might not be able to access ingress"
    fi

fi

    log "--- DOMAIN_NAME is $DOMAIN_NAME"

cd kd || exit 1

if [ -z "$DRY_RUN" ] ; then
  export KD_ARGS=""
else
  export KD_ARGS="--dryrun"
fi

log "--- deploying redis..."
if ! kd $KD_ARGS \
        -f redis/network-policy.yaml \
        -f redis/secret.yaml \
        -f redis/deployment.yaml \
        -f redis/deployment.yaml \
        -f redis/service.yaml; then
    log "[error] cannot deploy redis"
    exit 1
fi

log "--- Finished!"

log "--- deploying pttg-euro-tlr-enquiry-form"
if ! kd $KD_ARGS \
       -f pttg-euro-tlr-enquiry-form/network-policy.yaml \
       -f pttg-euro-tlr-enquiry-form/ingress.yaml \
       -f pttg-euro-tlr-enquiry-form/secret.yaml \
       -f pttg-euro-tlr-enquiry-form/deployment.yaml \
       -f pttg-euro-tlr-enquiry-form/service.yaml; then
   log "[error] cannot deploy deploying pttg-euro-tlr-enquiry-form"
   exit 1
fi
log "--- Finished!"
