#!/usr/bin/env bash
set -euo pipefail

VERSION="v1.7.0"
ARCHIVE_NAME="limboai+${VERSION}.gdextension-4.6.zip"
URL="https://github.com/limbonaut/limboai/releases/download/${VERSION}/limboai%2B${VERSION}.gdextension-4.6.zip"
SHA256="d97f4d0c1f39b6a5ebc822c7798174b95f15128a4aab7b5804d2741ac3f85f98"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADDON_DIR="${PROJECT_ROOT}/addons/limboai"
TMP_DIR="$(mktemp -d)"
ARCHIVE_PATH="${TMP_DIR}/${ARCHIVE_NAME}"

cleanup() {
	rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

if [[ -d "${ADDON_DIR}" ]]; then
	installed_version=""
	if [[ -f "${ADDON_DIR}/version.txt" ]]; then
		installed_version="$(tr -d '\r\n' < "${ADDON_DIR}/version.txt")"
	fi
	if [[ "${installed_version}" == "${VERSION}" || "${installed_version}" == "${VERSION#v}" ]]; then
		printf 'LimboAI %s is already installed at %s\n' "${VERSION}" "${ADDON_DIR}"
		exit 0
	fi
	printf 'Refusing to overwrite existing %s. Remove it first if you want to reinstall.\n' "${ADDON_DIR}" >&2
	exit 1
fi

command -v curl >/dev/null 2>&1 || { printf 'curl is required.\n' >&2; exit 1; }
command -v unzip >/dev/null 2>&1 || { printf 'unzip is required.\n' >&2; exit 1; }
command -v sha256sum >/dev/null 2>&1 || { printf 'sha256sum is required.\n' >&2; exit 1; }

printf 'Downloading LimboAI %s...\n' "${VERSION}"
curl -L --fail -o "${ARCHIVE_PATH}" "${URL}"

printf '%s  %s\n' "${SHA256}" "${ARCHIVE_PATH}" | sha256sum -c -

printf 'Extracting addons/limboai...\n'
unzip -q "${ARCHIVE_PATH}" 'addons/limboai/*' -d "${PROJECT_ROOT}"

printf 'LimboAI %s installed at %s\n' "${VERSION}" "${ADDON_DIR}"
