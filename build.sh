#!/bin/bash
# =============================================================================
# Build (and optionally Test) Script for CycleCloud Container
# =============================================================================
# Builds the container image and runs validation tests by default.
# All artifacts are written to ./work (created fresh each run).
#
# Usage: ./build.sh [--notest] [image_tag]
#   --notest:   Skip running tests after build
#   image_tag:  Optional tag for the built image (default: cyclecloud:test)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_TESTS=true
IMAGE_TAG="cyclecloud:test"

# Parse arguments
for arg in "$@"; do
    case "$arg" in
        --notest)
            RUN_TESTS=false
            ;;
        *)
            IMAGE_TAG="$arg"
            ;;
    esac
done

WORK_DIR="${SCRIPT_DIR}/work"

# =============================================================================
# Prepare work directory
# =============================================================================
echo "==> Preparing work directory: ${WORK_DIR}"
rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}"

# =============================================================================
# Build the Ubuntu container image
# =============================================================================
echo "==> Building Ubuntu container image: ${IMAGE_TAG}"
BUILD_LOG="${WORK_DIR}/build.log"

if docker build -t "${IMAGE_TAG}" "${SCRIPT_DIR}" 2>&1 | tee "${BUILD_LOG}"; then
    echo "==> Ubuntu build succeeded"
else
    echo "==> Ubuntu build FAILED (see ${BUILD_LOG})"
    exit 1
fi

# =============================================================================
# Build the RHEL container image
# =============================================================================
RHEL_IMAGE_TAG="${IMAGE_TAG}-rhel"
echo "==> Building RHEL container image: ${RHEL_IMAGE_TAG}"
RHEL_BUILD_LOG="${WORK_DIR}/build_rhel.log"

if docker build -f Dockerfile.rhel -t "${RHEL_IMAGE_TAG}" "${SCRIPT_DIR}" 2>&1 | tee "${RHEL_BUILD_LOG}"; then
    echo "==> RHEL build succeeded"
else
    echo "==> RHEL build FAILED (see ${RHEL_BUILD_LOG})"
    exit 1
fi

# =============================================================================
# Run unit tests (unless --notest)
# =============================================================================
TEST_EXIT=0
if [ "${RUN_TESTS}" == "true" ]; then
    echo "==> Running Ubuntu container validation tests..."
    TEST_LOG="${WORK_DIR}/test_results.tap"

    if "${SCRIPT_DIR}/tests/test_container.sh" "${IMAGE_TAG}" ubuntu 2>&1 | tee "${TEST_LOG}"; then
        :
    else
        TEST_EXIT=$?
    fi

    echo "==> Running RHEL container validation tests..."
    RHEL_TEST_LOG="${WORK_DIR}/test_results_rhel.tap"

    if "${SCRIPT_DIR}/tests/test_container.sh" "${RHEL_IMAGE_TAG}" rhel 2>&1 | tee "${RHEL_TEST_LOG}"; then
        :
    else
        TEST_EXIT=$?
    fi
else
    echo "==> Skipping tests (--notest)"
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "==========================================="
echo "  Build & Test Complete"
echo "==========================================="
echo "  Ubuntu image: ${IMAGE_TAG}"
echo "  RHEL image:   ${RHEL_IMAGE_TAG}"
echo "  Build logs:   ${BUILD_LOG}, ${RHEL_BUILD_LOG}"
if [ "${RUN_TESTS}" == "true" ]; then
echo "  Test results: ${TEST_LOG}, ${RHEL_TEST_LOG}"
fi
echo "  Work dir:     ${WORK_DIR}"
echo "==========================================="

if [ "${RUN_TESTS}" == "true" ]; then
    if [ ${TEST_EXIT} -eq 0 ]; then
        echo "  Status: ALL TESTS PASSED"
    else
        echo "  Status: SOME TESTS FAILED (exit code: ${TEST_EXIT})"
    fi
else
    echo "  Status: BUILD ONLY (tests skipped)"
fi

exit ${TEST_EXIT}
