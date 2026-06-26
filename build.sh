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
# Build the container image
# =============================================================================
echo "==> Building container image: ${IMAGE_TAG}"
BUILD_LOG="${WORK_DIR}/build.log"

if docker build -t "${IMAGE_TAG}" "${SCRIPT_DIR}" 2>&1 | tee "${BUILD_LOG}"; then
    echo "==> Build succeeded"
else
    echo "==> Build FAILED (see ${BUILD_LOG})"
    exit 1
fi

# =============================================================================
# Run unit tests (unless --notest)
# =============================================================================
TEST_EXIT=0
if [ "${RUN_TESTS}" == "true" ]; then
    echo "==> Running container validation tests..."
    TEST_LOG="${WORK_DIR}/test_results.tap"

    if "${SCRIPT_DIR}/tests/test_container.sh" "${IMAGE_TAG}" 2>&1 | tee "${TEST_LOG}"; then
        TEST_EXIT=0
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
echo "  Image:        ${IMAGE_TAG}"
echo "  Build log:    ${BUILD_LOG}"
if [ "${RUN_TESTS}" == "true" ]; then
echo "  Test results: ${TEST_LOG}"
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
