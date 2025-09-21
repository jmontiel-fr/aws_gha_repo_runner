#!/bin/bash
set -e

echo "=== Direct GitHub Actions Runner Installation ==="
echo "Repository: https://github.com/jmontiel-fr/crypto-robot"
echo "Runner Name: gha_aws_runner"
echo "Timestamp: $(date)"

# Clean up any locks and processes
echo "Cleaning up package locks..."
sudo rm -f /var/lib/apt/lists/lock /var/cache/apt/archives/lock /var/lib/dpkg/lock*
sudo systemctl stop unattended-upgrades 2>/dev/null || true
sudo pkill -f apt 2>/dev/null || true
sudo pkill -f dpkg 2>/dev/null || true
sleep 3

# Update packages
echo "Updating package lists..."
sudo DEBIAN_FRONTEND=noninteractive apt-get update -y

# Create runner directory
echo "Setting up runner directory..."
mkdir -p ~/actions-runner
cd ~/actions-runner

# Download runner if not already present
if [ ! -f "config.sh" ]; then
    echo "Downloading GitHub Actions runner..."
    RUNNER_VERSION=$(curl -s https://api.github.com/repos/actions/runner/releases/latest | jq -r '.tag_name' | sed 's/v//')
    curl -o actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz -L \
        "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz"
    
    tar xzf ./actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz
    rm actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz
    
    echo "Installing dependencies..."
    sudo ./bin/installdependencies.sh
fi

# Stop existing service if running
echo "Stopping existing runner service..."
sudo ./svc.sh stop 2>/dev/null || true
sudo ./svc.sh uninstall 2>/dev/null || true

# Remove existing configuration
echo "Removing existing runner configuration..."
./config.sh remove --token "$1" 2>/dev/null || true

# Configure new runner
echo "Configuring new runner..."
./config.sh \
    --url "https://github.com/jmontiel-fr/crypto-robot" \
    --token "$1" \
    --name "gha_aws_runner" \
    --labels "self-hosted,gha_aws_runner" \
    --work "_work" \
    --unattended \
    --replace

# Install and start service
echo "Installing and starting runner service..."
sudo ./svc.sh install ubuntu
sudo ./svc.sh start

# Verify service status
echo "Verifying runner service status..."
sleep 3
sudo ./svc.sh status

echo "=== Runner Installation Complete ==="
echo "Runner 'gha_aws_runner' configured for repository: jmontiel-fr/crypto-robot"