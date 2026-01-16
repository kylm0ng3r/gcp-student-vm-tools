#!/usr/bin/env bash
set -euo pipefail

REPO_OWNER="kylm0ng3r"
REPO_NAME="gcp-student-vm-tools"
BRANCH="main"

RAW_BASE="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${BRANCH}"

INSTALL_DIR="$HOME/gcp"
SCRIPT_NAME="manage_students.sh"
CONFIG_EXAMPLE="config.env.example"

echo "==========================================="
echo " GCP Student VM Tools – Installer"
echo "==========================================="
echo

# --- helpers ---
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

is_wsl() {
  grep -qi microsoft /proc/version 2>/dev/null
}

# --- environment check ---
echo "🔍 Checking environment..."

if ! command_exists bash; then
  echo "❌ bash not found. This script requires bash."
  exit 1
fi

if ! command_exists curl; then
  echo "❌ curl not found. Please install curl and re-run."
  exit 1
fi

OS="$(uname -s)"

echo "✔ OS detected: $OS"
if is_wsl; then
  echo "✔ Running inside WSL"
fi

echo

# --- install gcloud if missing ---
if command_exists gcloud; then
  echo "✔ Google Cloud CLI already installed"
else
  echo "⬇ Installing Google Cloud CLI..."

  if [[ "$OS" == "Darwin" ]]; then
    # macOS
    if ! command_exists brew; then
      echo "❌ Homebrew not found."
      echo "Install Homebrew first: https://brew.sh"
      exit 1
    fi
    brew install --cask google-cloud-sdk

  elif [[ "$OS" == "Linux" ]]; then
    sudo apt-get update -y
    sudo apt-get install -y apt-transport-https ca-certificates gnupg curl
    curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
      | sudo gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg

    echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] \
https://packages.cloud.google.com/apt cloud-sdk main" \
      | sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list >/dev/null

    sudo apt-get update -y
    sudo apt-get install -y google-cloud-cli
  else
    echo "❌ Unsupported OS: $OS"
    exit 1
  fi
fi

echo
echo "📁 Setting up workspace at $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# --- download scripts ---
echo "⬇ Downloading scripts..."

curl -fsSL "$RAW_BASE/$SCRIPT_NAME" -o "$SCRIPT_NAME"
curl -fsSL "$RAW_BASE/$CONFIG_EXAMPLE" -o "$CONFIG_EXAMPLE"

chmod +x "$SCRIPT_NAME"

echo
echo "✔ Installation complete"
echo
echo "==========================================="
echo " NEXT STEPS"
echo "==========================================="
echo
echo "1️⃣ Authenticate with Google Cloud:"
echo "   gcloud init"
echo
echo "2️⃣ (Optional) Copy config:"
echo "   cp config.env.example config.env"
echo "   # then edit config.env if needed"
echo
echo "3️⃣ Run the VM manager:"
echo "   cd ~/gcp"
echo "   ./$SCRIPT_NAME"
echo
echo "==========================================="

