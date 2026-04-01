#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SWIFT_VERSION="6.3"
SWIFT_RELEASE="swift-${SWIFT_VERSION}-RELEASE"
SWIFT_PLATFORM="ubuntu24.04"
SWIFT_ARCHIVE="${SWIFT_RELEASE}-${SWIFT_PLATFORM}.tar.gz"
SWIFT_BASE_URL="https://download.swift.org/swift-6.3-release/ubuntu2404/${SWIFT_RELEASE}"
SWIFT_URL="${SWIFT_BASE_URL}/${SWIFT_ARCHIVE}"
SWIFT_SIG_URL="${SWIFT_URL}.sig"
INSTALL_DIR="${HOME}/.local/swift-${SWIFT_VERSION}"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

if [[ ! -f /etc/os-release ]]; then
  echo "Unsupported host: /etc/os-release not found." >&2
  exit 1
fi

# shellcheck disable=SC1091
source /etc/os-release

if [[ "${ID:-}" != "ubuntu" || "${VERSION_ID:-}" != "24.04" ]]; then
  echo "This bootstrap only supports Ubuntu 24.04. Found ${PRETTY_NAME:-unknown}." >&2
  exit 1
fi

if ! grep -qi microsoft /proc/version; then
  echo "This bootstrap expects WSL2. '/proc/version' does not look like WSL." >&2
  exit 1
fi

if [[ "$(id -u)" -eq 0 ]]; then
  SUDO=()
else
  SUDO=(sudo)
fi

echo "Installing Swift ${SWIFT_VERSION} dependencies for Ubuntu 24.04..."
export DEBIAN_FRONTEND=noninteractive
"${SUDO[@]}" apt-get update
"${SUDO[@]}" apt-get install -y \
  binutils \
  git \
  gnupg2 \
  libc6-dev \
  libcurl4-openssl-dev \
  libedit2 \
  libgcc-13-dev \
  libncurses-dev \
  libpython3-dev \
  libsqlite3-0 \
  libstdc++-13-dev \
  libxml2-dev \
  libz3-dev \
  pkg-config \
  tzdata \
  zip \
  unzip \
  zlib1g-dev

echo "Downloading Swift ${SWIFT_VERSION} toolchain..."
python3 - <<'PY' "${SWIFT_URL}" "${TMP_DIR}/${SWIFT_ARCHIVE}" "${SWIFT_SIG_URL}" "${TMP_DIR}/${SWIFT_ARCHIVE}.sig"
import sys
import urllib.request

archive_url, archive_path, sig_url, sig_path = sys.argv[1:]
urllib.request.urlretrieve(archive_url, archive_path)
urllib.request.urlretrieve(sig_url, sig_path)
PY

echo "Importing Swift signing keys..."
chmod 700 "${TMP_DIR}"
python3 - <<'PY' "${TMP_DIR}/all-keys.asc"
import sys
import urllib.request

urllib.request.urlretrieve("https://swift.org/keys/all-keys.asc", sys.argv[1])
PY
gpg --import "${TMP_DIR}/all-keys.asc"

echo "Verifying Swift archive signature..."
gpg --verify "${TMP_DIR}/${SWIFT_ARCHIVE}.sig" "${TMP_DIR}/${SWIFT_ARCHIVE}"

echo "Extracting Swift into ${INSTALL_DIR}..."
mkdir -p "${INSTALL_DIR}"
rm -rf "${INSTALL_DIR}/usr"
tar xzf "${TMP_DIR}/${SWIFT_ARCHIVE}" -C "${TMP_DIR}"

EXTRACTED_USR_DIR=""
if [[ -d "${TMP_DIR}/usr" ]]; then
  EXTRACTED_USR_DIR="${TMP_DIR}/usr"
else
  EXTRACTED_ROOT="$(find "${TMP_DIR}" -maxdepth 1 -mindepth 1 -type d -name "${SWIFT_RELEASE}-${SWIFT_PLATFORM}*" | head -n 1 || true)"
  if [[ -n "${EXTRACTED_ROOT}" && -d "${EXTRACTED_ROOT}/usr" ]]; then
    EXTRACTED_USR_DIR="${EXTRACTED_ROOT}/usr"
  fi
fi

if [[ -z "${EXTRACTED_USR_DIR}" ]]; then
  echo "Unable to locate the extracted Swift toolchain directory." >&2
  exit 1
fi

cp -a "${EXTRACTED_USR_DIR}" "${INSTALL_DIR}/usr"

echo
echo "Bootstrap complete."
echo "Next step:"
echo "  source ./scripts/env-wsl.sh"
echo

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/env-wsl.sh"
swift --version
