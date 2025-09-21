#!/bin/bash
# GitHub Actions Runner Instance Initialization Script
# This script sets up a dedicated EC2 instance for a specific repository runner

set -e

# Configuration from template variables
GITHUB_USERNAME="${github_username}"
REPOSITORY_NAME="${repository_name}"
RUNNER_VERSION="${runner_version}"
ADDITIONAL_TOOLS="${additional_tools}"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a /var/log/runner-setup.log
}

log "Starting GitHub Actions runner setup for $GITHUB_USERNAME/$REPOSITORY_NAME"

# Update system packages
log "Updating system packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get upgrade -y

# Install essential packages
log "Installing essential packages..."
apt-get install -y \
    curl \
    wget \
    jq \
    git \
    unzip \
    zip \
    tar \
    gzip \
    ca-certificates \
    gnupg \
    lsb-release \
    software-properties-common \
    apt-transport-https \
    build-essential \
    libssl-dev \
    libffi-dev \
    python3-dev \
    python3-pip \
    python3-venv

# Install Docker
log "Installing Docker..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Configure Docker
systemctl enable docker
systemctl start docker
usermod -aG docker ubuntu

# Install Docker Compose (standalone)
log "Installing Docker Compose..."
DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | jq -r '.tag_name')
curl -L "https://github.com/docker/compose/releases/download/$${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Install AWS CLI v2
log "Installing AWS CLI v2..."
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install
rm -rf aws awscliv2.zip

# Install Node.js (LTS)
log "Installing Node.js..."
curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
apt-get install -y nodejs

# Install Yarn
log "Installing Yarn..."
npm install -g yarn

# Install Python tools
log "Installing Python tools..."
pip3 install --upgrade pip
pip3 install pipenv poetry virtualenv

# Install Java (OpenJDK 11 and 17)
log "Installing Java..."
apt-get install -y openjdk-11-jdk openjdk-17-jdk

# Install .NET SDK
log "Installing .NET SDK..."
wget https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb -O packages-microsoft-prod.deb
dpkg -i packages-microsoft-prod.deb
rm packages-microsoft-prod.deb
apt-get update
apt-get install -y dotnet-sdk-6.0 dotnet-sdk-7.0

# Install Go
log "Installing Go..."
GO_VERSION=$(curl -s https://api.github.com/repos/golang/go/releases/latest | jq -r '.tag_name')
wget "https://golang.org/dl/$${GO_VERSION}.linux-amd64.tar.gz"
rm -rf /usr/local/go && tar -C /usr/local -xzf "$${GO_VERSION}.linux-amd64.tar.gz"
rm "$${GO_VERSION}.linux-amd64.tar.gz"
echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/profile

# Install Terraform
log "Installing Terraform..."
wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | tee /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list
apt-get update
apt-get install -y terraform

# Install kubectl
log "Installing kubectl..."
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl

# Install Helm
log "Installing Helm..."
curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | tee /usr/share/keyrings/helm.gpg > /dev/null
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | tee /etc/apt/sources.list.d/helm-stable-debian.list
apt-get update
apt-get install -y helm

# Install additional tools if specified
if [ -n "$ADDITIONAL_TOOLS" ] && [ "$ADDITIONAL_TOOLS" != "[]" ]; then
    log "Installing additional tools: $ADDITIONAL_TOOLS"
    # Parse JSON array and install each tool
    echo "$ADDITIONAL_TOOLS" | jq -r '.[]' | while read -r tool; do
        if [ -n "$tool" ]; then
            log "Installing additional tool: $tool"
            apt-get install -y "$tool" || log "Warning: Failed to install $tool"
        fi
    done
fi

# Create ubuntu user directories
log "Setting up ubuntu user environment..."
mkdir -p /home/ubuntu/{actions-runner,scripts,logs}
chown -R ubuntu:ubuntu /home/ubuntu

# Download and install GitHub Actions runner
log "Downloading GitHub Actions runner..."
cd /home/ubuntu/actions-runner

# Get the latest runner version if not specified
if [ -z "$RUNNER_VERSION" ] || [ "$RUNNER_VERSION" = "" ]; then
    RUNNER_VERSION=$(curl -s https://api.github.com/repos/actions/runner/releases/latest | jq -r '.tag_name' | sed 's/v//')
fi

log "Installing GitHub Actions runner version: $RUNNER_VERSION"

# Download runner
curl -o actions-runner-linux-x64-$${RUNNER_VERSION}.tar.gz -L \
    "https://github.com/actions/runner/releases/download/v$${RUNNER_VERSION}/actions-runner-linux-x64-$${RUNNER_VERSION}.tar.gz"

# Verify checksum (optional but recommended)
curl -o actions-runner-linux-x64-$${RUNNER_VERSION}.tar.gz.sha256 -L \
    "https://github.com/actions/runner/releases/download/v$${RUNNER_VERSION}/actions-runner-linux-x64-$${RUNNER_VERSION}.tar.gz.sha256"

if sha256sum -c actions-runner-linux-x64-$${RUNNER_VERSION}.tar.gz.sha256; then
    log "Runner checksum verification passed"
else
    log "Warning: Runner checksum verification failed"
fi

# Extract runner
tar xzf ./actions-runner-linux-x64-$${RUNNER_VERSION}.tar.gz
rm actions-runner-linux-x64-$${RUNNER_VERSION}.tar.gz*

# Set ownership
chown -R ubuntu:ubuntu /home/ubuntu/actions-runner

# Install runner dependencies
log "Installing runner dependencies..."
sudo -u ubuntu ./bin/installdependencies.sh

# Create runner configuration script
log "Creating runner configuration script..."
cat > /home/ubuntu/scripts/configure-runner.sh << 'EOF'
#!/bin/bash
# GitHub Actions Runner Configuration Script

set -e

GITHUB_USERNAME="$1"
REPOSITORY_NAME="$2"
GITHUB_TOKEN="$3"
RUNNER_NAME="$4"

if [ -z "$GITHUB_USERNAME" ] || [ -z "$REPOSITORY_NAME" ] || [ -z "$GITHUB_TOKEN" ] || [ -z "$RUNNER_NAME" ]; then
    echo "Usage: $0 <github_username> <repository_name> <github_token> <runner_name>"
    exit 1
fi

cd /home/ubuntu/actions-runner

# Stop existing service if running
sudo ./svc.sh stop 2>/dev/null || true
sudo ./svc.sh uninstall 2>/dev/null || true

# Remove existing configuration
./config.sh remove --token "$GITHUB_TOKEN" 2>/dev/null || true

# Configure runner
./config.sh \
    --url "https://github.com/$${GITHUB_USERNAME}/$${REPOSITORY_NAME}" \
    --token "$GITHUB_TOKEN" \
    --name "$RUNNER_NAME" \
    --labels "self-hosted,gha_aws_runner,$${GITHUB_USERNAME}-$${REPOSITORY_NAME}" \
    --work "_work" \
    --unattended \
    --replace

# Install and start service
sudo ./svc.sh install ubuntu
sudo ./svc.sh start

echo "Runner configured successfully for ${GITHUB_USERNAME}/${REPOSITORY_NAME}"
EOF

chmod +x /home/ubuntu/scripts/configure-runner.sh
chown ubuntu:ubuntu /home/ubuntu/scripts/configure-runner.sh

# Create runner removal script
log "Creating runner removal script..."
cat > /home/ubuntu/scripts/remove-runner.sh << 'EOF'
#!/bin/bash
# GitHub Actions Runner Removal Script

set -e

GITHUB_TOKEN="$1"

if [ -z "$GITHUB_TOKEN" ]; then
    echo "Usage: $0 <github_token>"
    exit 1
fi

cd /home/ubuntu/actions-runner

# Stop and uninstall service
sudo ./svc.sh stop 2>/dev/null || true
sudo ./svc.sh uninstall 2>/dev/null || true

# Remove runner configuration
./config.sh remove --token "$GITHUB_TOKEN" 2>/dev/null || true

echo "Runner removed successfully"
EOF

chmod +x /home/ubuntu/scripts/remove-runner.sh
chown ubuntu:ubuntu /home/ubuntu/scripts/remove-runner.sh

# Create systemd service template (alternative to svc.sh)
log "Creating systemd service template..."
cat > /etc/systemd/system/actions-runner.service << EOF
[Unit]
Description=GitHub Actions Runner for ${GITHUB_USERNAME}/${REPOSITORY_NAME}
After=network.target

[Service]
Type=simple
User=ubuntu
Group=ubuntu
WorkingDirectory=/home/ubuntu/actions-runner
ExecStart=/home/ubuntu/actions-runner/run.sh
Restart=always
RestartSec=5
Environment=HOME=/home/ubuntu
Environment=USER=ubuntu

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload

# Set up log rotation
log "Setting up log rotation..."
cat > /etc/logrotate.d/actions-runner << EOF
/home/ubuntu/actions-runner/_diag/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 644 ubuntu ubuntu
}
EOF

# Create health check script
log "Creating health check script..."
cat > /home/ubuntu/scripts/health-check.sh << 'EOF'
#!/bin/bash
# GitHub Actions Runner Health Check Script

set -e

GITHUB_USERNAME="${github_username}"
REPOSITORY_NAME="${repository_name}"

echo "=== GitHub Actions Runner Health Check ==="
echo "Repository: ${GITHUB_USERNAME}/${REPOSITORY_NAME}"
echo "Timestamp: $(date)"
echo ""

# Check if runner directory exists
if [ -d "/home/ubuntu/actions-runner" ]; then
    echo "✓ Runner directory exists"
else
    echo "✗ Runner directory missing"
    exit 1
fi

# Check if runner is configured
if [ -f "/home/ubuntu/actions-runner/.runner" ]; then
    echo "✓ Runner is configured"
    
    # Show runner configuration
    echo "Runner configuration:"
    cat /home/ubuntu/actions-runner/.runner | jq .
else
    echo "✗ Runner not configured"
fi

# Check service status
if systemctl is-active --quiet actions-runner; then
    echo "✓ Runner service is active"
else
    echo "✗ Runner service is not active"
    systemctl status actions-runner --no-pager || true
fi

# Check system resources
echo ""
echo "=== System Resources ==="
echo "CPU Usage: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)%"
echo "Memory Usage: $(free | grep Mem | awk '{printf("%.1f%%", $3/$2 * 100.0)}')"
echo "Disk Usage: $(df -h / | awk 'NR==2{printf "%s", $5}')"

# Check Docker
if systemctl is-active --quiet docker; then
    echo "✓ Docker service is running"
else
    echo "✗ Docker service is not running"
fi

# Check network connectivity
if curl -s --max-time 5 https://api.github.com > /dev/null; then
    echo "✓ GitHub API connectivity OK"
else
    echo "✗ GitHub API connectivity failed"
fi

echo ""
echo "Health check completed"
EOF

chmod +x /home/ubuntu/scripts/health-check.sh
chown ubuntu:ubuntu /home/ubuntu/scripts/health-check.sh

# Set up cron job for health checks
log "Setting up health check cron job..."
echo "*/15 * * * * /home/ubuntu/scripts/health-check.sh >> /home/ubuntu/logs/health-check.log 2>&1" | crontab -u ubuntu -

# Create instance information file
log "Creating instance information file..."
cat > /home/ubuntu/instance-info.json << EOF
{
    "github_username": "${GITHUB_USERNAME}",
    "repository_name": "${REPOSITORY_NAME}",
    "instance_id": "$(curl -s http://169.254.169.254/latest/meta-data/instance-id)",
    "instance_type": "$(curl -s http://169.254.169.254/latest/meta-data/instance-type)",
    "availability_zone": "$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)",
    "public_ip": "$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)",
    "private_ip": "$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)",
    "setup_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "runner_version": "${RUNNER_VERSION}"
}
EOF

chown ubuntu:ubuntu /home/ubuntu/instance-info.json

# Set up automatic security updates
log "Configuring automatic security updates..."
apt-get install -y unattended-upgrades
echo 'Unattended-Upgrade::Automatic-Reboot "false";' >> /etc/apt/apt.conf.d/50unattended-upgrades

# Clean up
log "Cleaning up..."
apt-get autoremove -y
apt-get autoclean

# Final ownership fix
chown -R ubuntu:ubuntu /home/ubuntu

log "GitHub Actions runner instance setup completed successfully!"
log "Instance ready for repository: ${GITHUB_USERNAME}/${REPOSITORY_NAME}"
log "To configure the runner, use: /home/ubuntu/scripts/configure-runner.sh"

# Signal completion
touch /var/log/runner-setup-complete
echo "Setup completed at $(date)" > /var/log/runner-setup-complete