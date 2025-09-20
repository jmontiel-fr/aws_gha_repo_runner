#!/bin/bash

# =============================================================================
# User Data Script for GitHub Actions Repository Runner EC2 Instance
# =============================================================================
# This script installs all required development tools for repository-level
# GitHub Actions workflows. The instance will be registered with individual
# repositories using repository-scoped GitHub PATs.
#
# Tools installed:
# - Docker, AWS CLI, Python, Java, Terraform, kubectl, Helm
# - All tools are version-controlled via Terraform variables
# =============================================================================

set -e  # Exit on any error

# Update system packages
apt-get update
apt-get upgrade -y

# Install common dependencies
apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    software-properties-common \
    unzip \
    wget

# Install Docker using official Docker repository
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install -y docker-ce=${docker_version}~3-0~ubuntu-$(lsb_release -cs) docker-ce-cli=${docker_version}~3-0~ubuntu-$(lsb_release -cs) containerd.io
systemctl enable docker
systemctl start docker
usermod -aG docker ubuntu

# Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64-${aws_cli_version}.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install
rm -rf aws awscliv2.zip

# Install Python 3.12 using deadsnakes PPA
add-apt-repository ppa:deadsnakes/ppa -y
apt-get update
apt-get install -y python${python_version} python${python_version}-venv python${python_version}-pip
# Create symlink for python3 command
update-alternatives --install /usr/bin/python3 python3 /usr/bin/python${python_version} 1

# Install OpenJDK 17
apt-get install -y openjdk-${openjdk_version}-jdk

# Install Terraform using HashiCorp repository
wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | tee /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list
apt-get update
apt-get install -y terraform=${terraform_version}

# Install kubectl using official Kubernetes repository
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list
apt-get update
apt-get install -y kubectl=${kubectl_version}-1.1

# Install Helm using official installer
curl https://get.helm.sh/helm-v${helm_version}-linux-amd64.tar.gz -o helm.tar.gz
tar -zxvf helm.tar.gz
mv linux-amd64/helm /usr/local/bin/helm
rm -rf linux-amd64 helm.tar.gz

# Set proper permissions and ownership
chown -R ubuntu:ubuntu /home/ubuntu

# Create a verification script for repository runner setup
cat > /home/ubuntu/verify-tools.sh << 'EOF'
#!/bin/bash
echo "=== GitHub Actions Repository Runner - Tool Versions ==="
echo "Docker: $(docker --version)"
echo "AWS CLI: $(aws --version)"
echo "Python: $(python3 --version)"
echo "Java: $(java -version 2>&1 | head -n 1)"
echo "Terraform: $(terraform --version | head -n 1)"
echo "kubectl: $(kubectl version --client --short)"
echo "Helm: $(helm version --short)"
echo ""
echo "=== Repository Runner Setup Notes ==="
echo "This instance is configured for GitHub repository-level runners."
echo "Use GitHub PAT with 'repo' scope (not 'admin:org')."
echo "Register with: https://github.com/{username}/{repository}"
EOF

chmod +x /home/ubuntu/verify-tools.sh
chown ubuntu:ubuntu /home/ubuntu/verify-tools.sh

# Log completion for repository runner setup
echo "Repository runner user data script completed successfully at $(date)" >> /var/log/user-data.log
echo "Instance ready for GitHub Actions repository runner registration" >> /var/log/user-data.log