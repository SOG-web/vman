#!/bin/bash
set -e

# vman installer — downloads prebuilt binary from GitHub releases
# Usage: curl -fsSL https://raw.githubusercontent.com/SOG-web/vman/main/install.sh | bash

REPO="SOG-web/vman"
INSTALL_DIR="${VMAN_INSTALL_DIR:-/usr/local/bin}"

# Detect platform
OS="$(uname -s)"
ARCH="$(uname -m)"

case "$OS" in
    Linux)  PLATFORM="linux" ;;
    Darwin) PLATFORM="macos_arm64" ;;
    MINGW*|MSYS*|CYGWIN*) PLATFORM="windows";;
    *)      echo "error: unsupported platform: $OS"; exit 1 ;;
esac

# Detect architecture
case "$ARCH" in
    x86_64|amd64)
        if [ "$PLATFORM" = "macos_arm64" ]; then
            PLATFORM="macos_arm64"  # Rosetta on Apple Silicon
        fi
        ;;
    arm64|aarch64)
        if [ "$PLATFORM" = "linux" ]; then
            PLATFORM="linux"
            ARCH_SUFFIX="_arm64"
        else
            PLATFORM="macos_arm64"
        fi
        ;;
    *)      echo "error: unsupported architecture: $ARCH"; exit 1 ;;
esac

# Determine binary name and download URL
if [ "$PLATFORM" = "windows" ]; then
    BINARY_NAME="vman.exe"
    ARCHIVE_NAME="vman_windows.zip"
else
    BINARY_NAME="vman"
    case "$PLATFORM" in
        linux)       ARCHIVE_NAME="vman_linux.zip" ;;
        macos_arm64) ARCHIVE_NAME="vman_macos_arm64.zip" ;;
    esac
fi

# Get latest release version
echo "Finding latest release..."
LATEST=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" | grep '"tag_name"' | sed 's/.*": "\(.*\)".*/\1/')

if [ -z "$LATEST" ]; then
    echo "error: could not determine latest release"
    echo "Try installing from source instead:"
    echo "  git clone https://github.com/${REPO}"
    echo "  cd vman && v -cc clang -o vman . && sudo cp vman ${INSTALL_DIR}/vman"
    exit 1
fi

echo "Latest release: ${LATEST}"

# Download
TMP=$(mktemp -d)
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${LATEST}/${ARCHIVE_NAME}"
echo "Downloading ${DOWNLOAD_URL}..."

curl -fsSL "$DOWNLOAD_URL" -o "${TMP}/${ARCHIVE_NAME}"

# Extract
unzip -o -q "${TMP}/${ARCHIVE_NAME}" -d "${TMP}"

# Install
if [ -w "$INSTALL_DIR" ]; then
    cp "${TMP}/${BINARY_NAME}" "${INSTALL_DIR}/vman"
else
    echo "Installing to ${INSTALL_DIR} (may need sudo)..."
    sudo cp "${TMP}/${BINARY_NAME}" "${INSTALL_DIR}/vman"
fi

chmod +x "${INSTALL_DIR}/vman"

# Clean up
rm -rf "$TMP"

echo ""
echo "vman ${LATEST} installed to ${INSTALL_DIR}/vman"
echo ""
echo "Add to your ~/.zshrc or ~/.bashrc:"
echo '  export PATH="$HOME/.vman/current:$PATH"'
echo ""
echo "Then run:"
echo "  vman --install=latest"
echo "  vman --use=0.5.1"
