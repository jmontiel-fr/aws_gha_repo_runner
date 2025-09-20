# Repository-Specific GitHub Actions Runner Terraform Module

This Terraform module creates dedicated EC2 instances for GitHub Actions runners with parametrized naming and comprehensive configuration options. Each repository gets its own isolated runner instance with proper tagging for cost tracking and management.

## Features

- **Dedicated EC2 Instance**: Each repository gets its own isolated runner instance
- **Parametrized Naming**: Instances named as `runner-{username}-{repository}`
- **Comprehensive Tagging**: Proper tags for cost tracking and resource management
- **Security Groups**: Configured security groups with SSH access control
- **Auto-Installation**: Automated GitHub Actions runner installation via user-data
- **Multiple Tool Support**: Pre-installed development tools (Docker, Node.js, Python, etc.)
- **Cost Optimization**: Optional features like auto-shutdown and instance scheduling
- **Monitoring**: Optional CloudWatch logs and detailed monitoring
- **Auto Recovery**: Optional Auto Scaling Group for instance recovery

## Usage

### Basic Usage

```hcl
module "my_app_runner" {
  source = "./modules/repository-runner"
  
  # Required variables
  github_username = "johndoe"
  repository_name = "my-web-app"
  key_pair_name   = "my-runner-key"
  
  # Optional configuration
  instance_type = "t3.small"
  environment   = "prod"
  cost_center   = "engineering"
}
```

### Advanced Usage

```hcl
module "api_service_runner" {
  source = "./modules/repository-runner"
  
  # Repository information
  github_username = "johndoe"
  repository_name = "api-service"
  key_pair_name   = "my-runner-key"
  
  # Instance configuration
  instance_type = "t3.medium"
  ami_id        = "ami-0abcdef1234567890"  # Custom AMI
  
  # Networking
  vpc_id                   = "vpc-12345678"
  subnet_id               = "subnet-12345678"
  allowed_ssh_cidr_blocks = ["10.0.0.0/8"]  # Restrict SSH access
  
  # Storage
  root_volume_type = "gp3"
  root_volume_size = 30
  
  # Features
  allocate_elastic_ip      = true
  enable_detailed_monitoring = true
  enable_cloudwatch_logs   = true
  log_retention_days      = 30
  
  # IAM
  create_iam_role = true
  iam_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess",
    "arn:aws:iam::aws:policy/AmazonECRPublicReadOnly"
  ]
  
  # Auto Recovery
  enable_auto_recovery = true
  
  # Environment
  environment = "prod"
  cost_center = "api-team"
  
  # Additional tools
  additional_tools = ["postgresql-client", "redis-tools"]
}
```

### Multiple Repository Runners

```hcl
# Web application runner
module "web_app_runner" {
  source = "./modules/repository-runner"
  
  github_username = "johndoe"
  repository_name = "web-app"
  key_pair_name   = "my-runner-key"
  instance_type   = "t3.small"
  environment     = "prod"
}

# API service runner
module "api_runner" {
  source = "./modules/repository-runner"
  
  github_username = "johndoe"
  repository_name = "api-service"
  key_pair_name   = "my-runner-key"
  instance_type   = "t3.micro"
  environment     = "dev"
}

# Mobile app runner
module "mobile_runner" {
  source = "./modules/repository-runner"
  
  github_username = "johndoe"
  repository_name = "mobile-app"
  key_pair_name   = "my-runner-key"
  instance_type   = "t3.medium"
  environment     = "prod"
  
  # Mobile development needs more tools
  additional_tools = ["android-sdk", "fastlane"]
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.0 |
| aws | ~> 5.0 |

## Providers

| Name | Version |
|------|---------|
| aws | ~> 5.0 |

## Inputs

### Required Inputs

| Name | Description | Type |
|------|-------------|------|
| github_username | GitHub username for instance naming and tagging | `string` |
| repository_name | Repository name for instance naming and tagging | `string` |
| key_pair_name | AWS key pair name for SSH access to the instance | `string` |

### Optional Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| instance_type | EC2 instance type for the runner | `string` | `"t3.micro"` |
| ami_id | AMI ID for the instance (leave empty to use latest Ubuntu 22.04 LTS) | `string` | `""` |
| vpc_id | VPC ID for the instance (leave empty to use default VPC) | `string` | `""` |
| subnet_id | Subnet ID for the instance (leave empty to use first available subnet) | `string` | `""` |
| allowed_ssh_cidr_blocks | CIDR blocks allowed for SSH access | `list(string)` | `["0.0.0.0/0"]` |
| root_volume_type | Root volume type | `string` | `"gp3"` |
| root_volume_size | Root volume size in GB | `number` | `20` |
| environment | Environment name (dev, staging, prod) | `string` | `"dev"` |
| cost_center | Cost center for billing and cost tracking | `string` | `"github-actions"` |
| runner_version | GitHub Actions runner version (leave empty for latest) | `string` | `""` |
| additional_tools | List of additional tools to install on the runner | `list(string)` | `[]` |
| allocate_elastic_ip | Whether to allocate an Elastic IP for the instance | `bool` | `false` |
| enable_detailed_monitoring | Enable detailed CloudWatch monitoring | `bool` | `false` |
| enable_cloudwatch_logs | Enable CloudWatch logs for the runner | `bool` | `false` |
| log_retention_days | CloudWatch log retention in days | `number` | `7` |
| create_iam_role | Whether to create an IAM role for the instance | `bool` | `false` |
| iam_policy_arns | List of IAM policy ARNs to attach to the instance role | `list(string)` | `[]` |
| enable_auto_recovery | Enable auto recovery using Auto Scaling Group | `bool` | `false` |
| auto_recovery_desired_capacity | Desired capacity for auto recovery (0 or 1) | `number` | `1` |

## Outputs

### Instance Information

| Name | Description |
|------|-------------|
| instance_id | EC2 instance ID |
| instance_arn | EC2 instance ARN |
| instance_name | EC2 instance name |
| instance_type | EC2 instance type |
| instance_state | EC2 instance state |

### Network Information

| Name | Description |
|------|-------------|
| instance_public_ip | EC2 instance public IP address |
| instance_private_ip | EC2 instance private IP address |
| instance_public_dns | EC2 instance public DNS name |
| instance_private_dns | EC2 instance private DNS name |
| elastic_ip | Elastic IP address (if allocated) |

### Security Information

| Name | Description |
|------|-------------|
| security_group_id | Security group ID |
| security_group_arn | Security group ARN |
| key_pair_name | Key pair name used for the instance |

### Repository Information

| Name | Description |
|------|-------------|
| github_username | GitHub username |
| repository_name | Repository name |
| repository_full_name | Full repository name (username/repository) |
| runner_url | GitHub repository URL for runner registration |

### Connection Information

| Name | Description |
|------|-------------|
| ssh_connection_command | SSH connection command |

## Pre-installed Tools

The module automatically installs the following tools on the runner instance:

### System Tools
- curl, wget, jq, git
- unzip, zip, tar, gzip
- build-essential, libssl-dev

### Container Tools
- Docker CE with Docker Compose
- Container registry access tools

### Development Languages
- **Node.js**: Latest LTS version with npm and yarn
- **Python**: Python 3 with pip, pipenv, poetry, virtualenv
- **Java**: OpenJDK 11 and 17
- **.NET**: SDK 6.0 and 7.0
- **Go**: Latest stable version

### Infrastructure Tools
- **AWS CLI**: Version 2
- **Terraform**: Latest version
- **kubectl**: Latest stable version
- **Helm**: Latest version

### GitHub Actions Runner
- Latest GitHub Actions runner
- Automatic dependency installation
- Service configuration scripts

## Instance Naming Convention

Instances are automatically named using the pattern:
```
runner-{github-username}-{repository-name}
```

Examples:
- `runner-johndoe-web-app`
- `runner-acme-corp-api-service`
- `runner-myteam-mobile-app`

## Tagging Strategy

All resources are tagged with:

| Tag | Description | Example |
|-----|-------------|---------|
| Name | Instance name | `runner-johndoe-web-app` |
| Purpose | Resource purpose | `GitHub Actions Runner` |
| Repository | Full repository name | `johndoe/web-app` |
| GitHubUsername | GitHub username | `johndoe` |
| RepositoryName | Repository name | `web-app` |
| Environment | Environment name | `prod` |
| ManagedBy | Management tool | `terraform` |
| AutoShutdown | Auto-shutdown flag | `true` |
| CostCenter | Cost center | `engineering` |
| CreatedBy | Creation source | `repository-runner-module` |
| CreatedAt | Creation timestamp | `2024-01-15T10:30:00Z` |

## Security Considerations

### Network Security
- Security groups restrict access to SSH (port 22) only
- Configurable CIDR blocks for SSH access
- All outbound traffic allowed for GitHub Actions functionality

### Instance Security
- Latest Ubuntu 22.04 LTS AMI by default
- Automatic security updates enabled
- Instance metadata v2 enforced
- Root volume encryption enabled

### IAM Security
- Optional IAM role creation with minimal permissions
- Configurable policy attachments
- Instance profile for secure AWS service access

## Cost Optimization

### Instance Types
- Default `t3.micro` for cost efficiency
- Burstable performance instances for variable workloads
- Configurable instance types based on requirements

### Storage Optimization
- GP3 volumes by default for better price/performance
- Configurable volume sizes
- Root volume encryption included

### Auto-Shutdown
- Instances tagged with `AutoShutdown: true`
- Can be used with AWS Instance Scheduler or Lambda functions
- Stop instances when not in use to reduce costs

### Monitoring and Alerting
- Optional detailed monitoring
- CloudWatch logs for troubleshooting
- Cost tracking through comprehensive tagging

## Monitoring and Logging

### CloudWatch Integration
```hcl
module "monitored_runner" {
  source = "./modules/repository-runner"
  
  github_username = "johndoe"
  repository_name = "my-app"
  key_pair_name   = "my-key"
  
  # Enable monitoring
  enable_detailed_monitoring = true
  enable_cloudwatch_logs    = true
  log_retention_days       = 30
}
```

### Health Checks
The module includes automated health check scripts:
- System resource monitoring
- Runner service status
- GitHub API connectivity
- Docker service status

## Auto Recovery

Enable automatic instance recovery:

```hcl
module "resilient_runner" {
  source = "./modules/repository-runner"
  
  github_username = "johndoe"
  repository_name = "critical-app"
  key_pair_name   = "my-key"
  
  # Enable auto recovery
  enable_auto_recovery           = true
  auto_recovery_desired_capacity = 1
}
```

## Examples

### Development Environment
```hcl
module "dev_runner" {
  source = "./modules/repository-runner"
  
  github_username = "developer"
  repository_name = "test-app"
  key_pair_name   = "dev-key"
  
  instance_type = "t3.micro"
  environment   = "dev"
  
  # Basic monitoring
  enable_cloudwatch_logs = true
  log_retention_days    = 7
}
```

### Production Environment
```hcl
module "prod_runner" {
  source = "./modules/repository-runner"
  
  github_username = "company"
  repository_name = "production-app"
  key_pair_name   = "prod-key"
  
  # Production configuration
  instance_type = "t3.medium"
  environment   = "prod"
  
  # Enhanced security
  allowed_ssh_cidr_blocks = ["10.0.0.0/8"]
  
  # Monitoring and recovery
  enable_detailed_monitoring = true
  enable_cloudwatch_logs    = true
  log_retention_days       = 90
  enable_auto_recovery     = true
  
  # IAM permissions
  create_iam_role = true
  iam_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
  ]
  
  # Static IP
  allocate_elastic_ip = true
}
```

## Troubleshooting

### Common Issues

1. **Instance fails to start**
   - Check AMI availability in the region
   - Verify key pair exists
   - Check subnet and VPC configuration

2. **SSH connection fails**
   - Verify security group rules
   - Check key pair permissions (chmod 400)
   - Ensure instance is in running state

3. **Runner registration fails**
   - Verify GitHub token permissions
   - Check repository access
   - Review user-data script logs

### Debugging

SSH into the instance and check:
```bash
# Check user-data execution
sudo tail -f /var/log/cloud-init-output.log

# Check runner setup logs
sudo tail -f /var/log/runner-setup.log

# Check runner status
sudo systemctl status actions-runner

# Run health check
/home/ubuntu/scripts/health-check.sh
```

## Contributing

When contributing to this module:

1. Follow Terraform best practices
2. Update documentation for any new variables or outputs
3. Test with multiple scenarios
4. Ensure backward compatibility
5. Update examples as needed

## License

This module is provided under the MIT License. See LICENSE file for details.