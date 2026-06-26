#!/bin/bash
set -e

CS_ROOT="/opt/cycle_server"

# ============================================================================
# Set defaults for all environment variables
# ============================================================================
USE_WORKLOAD_IDENTITY="${USE_WORKLOAD_IDENTITY:-false}"
CYCLECLOUD_USERNAME="${CYCLECLOUD_USERNAME:-ccadmin}"
CYCLECLOUD_PASSWORD="${CYCLECLOUD_PASSWORD:-CHANGEME}"
CYCLECLOUD_USER_PUBKEY="${CYCLECLOUD_USER_PUBKEY:-}"
CYCLECLOUD_STORAGE="${CYCLECLOUD_STORAGE:-}"
CYCLECLOUD_RESOURCE_GROUP="${CYCLECLOUD_RESOURCE_GROUP:-}"
CYCLECLOUD_WEBSERVER_MAX_HEAP_SIZE="${CYCLECLOUD_WEBSERVER_MAX_HEAP_SIZE:-4096M}"
CYCLECLOUD_WEBSERVER_PORT="${CYCLECLOUD_WEBSERVER_PORT:-8080}"
CYCLECLOUD_WEBSERVER_SSL_PORT="${CYCLECLOUD_WEBSERVER_SSL_PORT:-8443}"
CYCLECLOUD_WEBSERVER_HTTPS_ENABLED="${CYCLECLOUD_WEBSERVER_HTTPS_ENABLED:-true}"
CYCLECLOUD_WEBSERVER_CLUSTER_PORT="${CYCLECLOUD_WEBSERVER_CLUSTER_PORT:-9443}"
CYCLECLOUD_HOSTNAME="${CYCLECLOUD_HOSTNAME:-}"
CYCLECLOUD_FORCE_DELETE_VMS="${CYCLECLOUD_FORCE_DELETE_VMS:-true}"
CYCLECLOUD_FORCE_DELETE_VMSS="${CYCLECLOUD_FORCE_DELETE_VMSS:-true}"
STORAGE_MANAGED_IDENTITY="${STORAGE_MANAGED_IDENTITY:-}"
GENERATE_CS_CONFIG="${GENERATE_CS_CONFIG:-true}"
DRYRUN="${DRYRUN:-}"
NO_DEFAULT_ACCOUNT="${NO_DEFAULT_ACCOUNT:-}"
CONTAINER_DEBUG="${CONTAINER_DEBUG:-false}"
ENTRA_ENABLED="${ENTRA_ENABLED:-false}"
ENTRA_TENANT_ID="${ENTRA_TENANT_ID:-}"
ENTRA_CLIENT_ID="${ENTRA_CLIENT_ID:-}"
ENTRA_OBJECT_ID="${ENTRA_OBJECT_ID:-}"
ENTRA_AUTH_ENDPOINT="${ENTRA_AUTH_ENDPOINT:-}"
ENTRA_USERNAME="${ENTRA_USERNAME:-}"
ENTRA_UID="${ENTRA_UID:-}"

# ============================================================================
# FAIL-CLOSED SECURITY GATE: Check for default password
# ============================================================================
if [[ "${CYCLECLOUD_PASSWORD}" == "CHANGEME" ]] && [[ "${CONTAINER_DEBUG}" != "true" ]]; then
    echo "ERROR: CYCLECLOUD_PASSWORD must be changed before running in production. Set CYCLECLOUD_PASSWORD via secret or use CONTAINER_DEBUG=true for testing."
    exit 1
fi

# ============================================================================
# Initialize persistent volume on first start
# ============================================================================
if [ ! -f "${CS_ROOT}/data/ads/master.logfile" ]; then
    echo "Initializing persistent volume from stashed CycleCloud data..."
    pushd ${CS_ROOT}/data
    rm -rf ./ads
    mkdir -p ./ads
    mv /opt_cycle_server/data/ads/* ./ads/ || true
    popd
fi

# ============================================================================
# Copy stashed work directory (preserves jetpack/project versions)
# ============================================================================
if [ ! -d "${CS_ROOT}/work" ]; then
    mkdir -p ${CS_ROOT}/work
fi
if [ -d "/opt_cycle_server/work" ]; then
    cp -a /opt_cycle_server/work/* ${CS_ROOT}/work/ || true
fi

# ============================================================================
# Rotate logs
# ============================================================================
if [ -f "${CS_ROOT}/logs/catalina.err" ]; then
    mv ${CS_ROOT}/logs/catalina.err ${CS_ROOT}/logs/catalina.err.1 || true
fi
if [ -f "${CS_ROOT}/logs/catalina.out" ]; then
    mv ${CS_ROOT}/logs/catalina.out ${CS_ROOT}/logs/catalina.out.1 || true
fi

# ============================================================================
# Set up environment variables for cyclecloud_install.py
# ============================================================================
# Convert boolean-like strings to --flags for cyclecloud_install.py
if [ "${GENERATE_CS_CONFIG}" == "true" ]; then
    GENERATE_CS_CONFIG_FLAG="--generateCsConfig"
else
    GENERATE_CS_CONFIG_FLAG=""
fi

if [ "${ENTRA_ENABLED}" == "true" ]; then
    ENTRA_ENABLED_FLAG="--entraEnabled"
else
    ENTRA_ENABLED_FLAG=""
fi

ENTRA_ARGS=()
if [ "${ENTRA_ENABLED}" == "true" ]; then
    [ -n "${ENTRA_TENANT_ID}" ] && ENTRA_ARGS+=("--entraTenantId=${ENTRA_TENANT_ID}")
    [ -n "${ENTRA_CLIENT_ID}" ] && ENTRA_ARGS+=("--entraClientId=${ENTRA_CLIENT_ID}")
    [ -n "${ENTRA_OBJECT_ID}" ] && ENTRA_ARGS+=("--entraObjectId=${ENTRA_OBJECT_ID}")
    [ -n "${ENTRA_AUTH_ENDPOINT}" ] && ENTRA_ARGS+=("--entraAuthEndpoint=${ENTRA_AUTH_ENDPOINT}")
    [ -n "${ENTRA_USERNAME}" ] && ENTRA_ARGS+=("--entraUsername=${ENTRA_USERNAME}")
    [ -n "${ENTRA_UID}" ] && ENTRA_ARGS+=("--entraUID=${ENTRA_UID}")
fi

# Convert DRYRUN and NO_DEFAULT_ACCOUNT to flags
DRYRUN_FLAG=""
if [ -n "${DRYRUN}" ] && [ "${DRYRUN}" != "" ]; then
    DRYRUN_FLAG="--dryrun"
fi

# ============================================================================
# Run cyclecloud_install.py for pre-start configuration
# ============================================================================
echo "Running cyclecloud_install.py for pre-start configuration..."
python3 /cs-install/scripts/cyclecloud_install.py \
    --username="${CYCLECLOUD_USERNAME}" \
    --password="${CYCLECLOUD_PASSWORD}" \
    --publickey="${CYCLECLOUD_USER_PUBKEY}" \
    --webServerMaxHeapSize="${CYCLECLOUD_WEBSERVER_MAX_HEAP_SIZE}" \
    --webServerPort="${CYCLECLOUD_WEBSERVER_PORT}" \
    --webServerSslPort="${CYCLECLOUD_WEBSERVER_SSL_PORT}" \
    --webServerClusterPort="${CYCLECLOUD_WEBSERVER_CLUSTER_PORT}" \
    --webServerHostname="${CYCLECLOUD_HOSTNAME}" \
    ${GENERATE_CS_CONFIG_FLAG} \
    ${ENTRA_ENABLED_FLAG} \
    "${ENTRA_ARGS[@]}" \
    --forceDeleteVms="${CYCLECLOUD_FORCE_DELETE_VMS}" \
    --forceDeleteVmss="${CYCLECLOUD_FORCE_DELETE_VMSS}" \
    ${DRYRUN_FLAG}

# ============================================================================
# Start CycleCloud in foreground mode
# ============================================================================
echo "Starting CycleCloud in foreground mode..."
${CS_ROOT}/cycle_server start --foreground
EXIT_CODE=$?

# ============================================================================
# Handle exit code and CONTAINER_DEBUG flag
# ============================================================================
if [ ${EXIT_CODE} -eq 0 ]; then
    # Clean shutdown, exit normally
    echo "CycleCloud exited cleanly."
    exit 0
else
    # Non-zero exit code (error)
    if [ "${CONTAINER_DEBUG}" == "true" ]; then
        echo "CycleCloud failed (exit code: ${EXIT_CODE}). CONTAINER_DEBUG=true, sleeping indefinitely for inspection..."
        sleep infinity
    else
        echo "CycleCloud failed (exit code: ${EXIT_CODE}). Exiting with error."
        exit ${EXIT_CODE}
    fi
fi
