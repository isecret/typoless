#!/usr/bin/env bash
# verify-xcode-env.sh — 校验 CI 当前使用的 Xcode / SDK 环境是否符合预期。

set -euo pipefail

EXPECTED_XCODE_VERSION="${EXPECTED_XCODE_VERSION:-}"
EXPECTED_SDK_VERSION="${EXPECTED_SDK_VERSION:-}"

actual_xcode_version="$(xcodebuild -version | awk 'NR==1 { print $2 }')"
actual_xcode_build="$(xcodebuild -version | awk 'NR==2 { print $3 }')"
actual_sdk_version="$(xcrun --sdk macosx --show-sdk-version)"
developer_dir="${DEVELOPER_DIR:-$(xcode-select -p)}"

echo "=== Xcode Environment ==="
echo "DEVELOPER_DIR: ${developer_dir}"
echo "Xcode version: ${actual_xcode_version} (${actual_xcode_build})"
echo "macOS SDK version: ${actual_sdk_version}"
echo ""

if [ -z "${EXPECTED_XCODE_VERSION}" ]; then
    echo "error: EXPECTED_XCODE_VERSION is required"
    exit 1
fi

if [ -z "${EXPECTED_SDK_VERSION}" ]; then
    echo "error: EXPECTED_SDK_VERSION is required"
    exit 1
fi

if [ "${actual_xcode_version}" != "${EXPECTED_XCODE_VERSION}" ]; then
    echo "error: expected Xcode ${EXPECTED_XCODE_VERSION}, got ${actual_xcode_version}"
    exit 1
fi

if [ "${actual_sdk_version}" != "${EXPECTED_SDK_VERSION}" ]; then
    echo "error: expected macOS SDK ${EXPECTED_SDK_VERSION}, got ${actual_sdk_version}"
    exit 1
fi

echo "Xcode environment matches expectations."
