# GitHub Actions Repository Runner - Terraform Configuration

This Terraform configuration creates AWS infrastructure for a GitHub Actions self-hosted runner that works with **individual repositories** rather than organizations.

## Key Features

- **Repository-Level**: Designed for personal GitHub accounts and individual repositories
- **Simplified Permissions**: Only requires `repo` scope GitHub PAT (not `admin:org`)
- **Cost-Optimized**: Uses t3.micro instance with automatic start/stop via workflows
- **Secure**: SSH access restricted to personal IP, GitHub access from official IP ranges
- **Backward Compatible**: Works with existing AWS infrastructure setups

## Quick Start

1. **Copy the example configuration:**
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

2. **Update terraform.tfvars with your values:**
   - Set your personal IP address for SSH access
   - Configure your AWS key pair name
   - Adjust tool versions if needed

3. **Deploy the infrastructure:**
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

4. **Configure your GitHub repository:**
   - Add the required secrets (see Repository Setup section)
   - Copy the provided workflow files to `.github/workflows/`
   - Run the configuration workflow to register the runner

## Repository Setup

After deploying the infrastructure, configure your GitHub repository with these secrets:

| Secret Name | Description | Example |
|-------------|-------------|---------|
| `AWS_ACCESS_KEY_ID` | AWS access key | `AKIA...` |
| `AWS_SECRET_ACCESS_KEY` | AWS secret key | `wJal...` |
| `AWS_REGION` | AWS region | `eu-west-1` |
| `GH_PAT` | GitHub PAT with `repo` scope | `ghp_...` |
| `EC2_INSTANCE_ID` | From Terraform output | `i-1234567890abcdef0` |
| `RUNNER_NAME` | Runner name | `gha_aws_runner` |

## GitHub PAT Requirements

**Important:** This setup requires a GitHub Personal Access Token with **`repo` scope only**:

- ✅ `repo` - Full control of private repositories
- ❌ `admin:org` - NOT required (this is for organizations)

You must have **admin permissions** on the target repository.

## Migration from Organization Setup

If you're migrating from an organization-level runner:

1. **Backup existing configuration**
2. **Update GitHub PAT scope** from `admin:org` to `repo`
3. **Update repository secrets** with new variable names
4. **Re-register runner** with repository endpoints
5. **Test workflows** to ensure functionality

The Terraform infrastructure remains largely unchanged - only the runner registration process changes.

## File Structure

```
terraform/
├── main.tf              # Provider and core configuration
├── variables.tf         # Input variables with validation
├── locals.tf           # Computed values and GitHub IP ranges
├── vpc.tf              # VPC and networking resources
├── security.tf         # Security groups and access rules
├── ec2.tf              # EC2 instance configuration
├── outputs.tf          # Outputs for GitHub Actions integration
├── user_data.sh        # Instance initialization script
├── terraform.tfvars    # Your actual configuration values
├── terraform.tfvars.example  # Example configuration
└── README.md           # This file
```

## Cost Optimization

- **Instance Type**: t3.micro (free tier eligible)
- **Storage**: No additional EBS volumes
- **Networking**: No NAT Gateway or EIP charges
- **Runtime**: Instance only runs when workflows are active

Estimated monthly cost: $8-15 USD (depending on usage)

## Security Features

- **Network Isolation**: Dedicated VPC with restricted access
- **SSH Access**: Limited to your personal IP address only
- **GitHub Access**: Restricted to official GitHub IP ranges
- **Repository Isolation**: Runner only accessible to configured repository
- **No Organization Access**: Cannot access other repositories or organization resources

## Troubleshooting

### Common Issues

1. **Runner not appearing in repository:**
   - Check GitHub PAT has `repo` scope
   - Verify you have admin permissions on repository
   - Ensure EC2 instance is running

2. **Permission errors:**
   - Confirm PAT scope is `repo` (not `admin:org`)
   - Check repository admin permissions
   - Verify Actions are enabled in repository settings

3. **SSH connection issues:**
   - Update `personal_ip` in terraform.tfvars
   - Check security group rules
   - Verify key pair exists in AWS

### Useful Commands

```bash
# Check runner status
aws ec2 describe-instances --instance-ids <INSTANCE_ID>

# SSH to instance
ssh -i ~/.ssh/your-key.pem ubuntu@<INSTANCE_IP>

# Check GitHub runners via API
curl -H "Authorization: token <GH_PAT>" \
  "https://api.github.com/repos/<USERNAME>/<REPO>/actions/runners"
```

## Support

For issues specific to repository runner setup:
1. Check the troubleshooting section above
2. Verify your GitHub PAT scope and permissions
3. Ensure repository Actions are enabled
4. Review AWS CloudWatch logs for instance issues

## Backward Compatibility

This configuration maintains backward compatibility with existing organization-level setups:

- Same AWS resources and naming conventions
- Same tool versions and configurations  
- Same security group and networking setup
- Only runner registration process changes

You can migrate existing infrastructure by updating the runner registration scripts and GitHub workflows without recreating AWS resources.