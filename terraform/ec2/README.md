# EC2 Instance Provisioning Guide

This guide provides step-by-step instructions for developers to provision EC2 instances using Terraform with proper tagging for cost tracking and resource management.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Tag Requirements](#tag-requirements)
- [Workflow: Adding a New EC2 Instance](#workflow-adding-a-new-ec2-instance)
- [Environment-Specific Configuration](#environment-specific-configuration)
- [Example Configurations](#example-configurations)
- [Troubleshooting](#troubleshooting)

---

## Overview

This Terraform configuration provisions EC2 instances with:

- AMI images from HCP Packer Registry
- Dynamic AWS credentials from HashiCorp Vault
- Network configuration from Vault KV store
- Comprehensive resource tagging for cost allocation and management
- Security groups with configurable ports (defined in `ports.yaml`)

---

## Prerequisites

Before provisioning EC2 instances, ensure you have:

1. **Access to Required Systems:**

   - HashiCorp Vault access with appropriate permissions
   - HCP Packer Registry access
   - AWS account access (via Vault dynamic secrets)
   - Terraform Cloud workspace access
2. **Required Tools:**

   - Terraform CLI (v1.0+)
   - Git
   - AWS CLI (optional, for verification)
3. **Environment Variables:**

   ```bash
   export TF_VAR_vault_addr="https://your-vault-address"
   export TF_VAR_vault_token="your-vault-token"
   ```

---

## Tag Requirements

All EC2 instances **MUST** include the following tags for proper cost allocation and resource management:

| Tag Name               | Description                             | Example Values                                 |
| ---------------------- | --------------------------------------- | ---------------------------------------------- |
| **CostCenter**   | Which department pays for this resource | Engineering, Operations, Marketing             |
| **Project**      | What business initiative it supports    | AMI Pipeline Development, Customer Portal      |
| **Environment**  | Deployment environment                  | Development, Staging, Production               |
| **Owner**        | Who is responsible for this resource    | DevOps Team, Platform Engineering Team         |
| **BusinessUnit** | Which part of the organization uses it  | Technology Infrastructure, Product Development |

### Why Tags Matter

- **Cost Allocation:** Tags enable accurate cost tracking in AWS Cost Explorer and Cloudability
- **Resource Management:** Easily identify and manage resources by project, owner, or environment
- **Compliance:** Meet organizational requirements for resource accountability
- **Automation:** Enable automated policies and workflows based on tags

---

## Workflow: Adding a New EC2 Instance

Follow this GitOps workflow to provision a new EC2 instance:

### Step 1: Create a Feature Branch

```bash
# Navigate to the project directory
cd infra

# Ensure you're on the main branch and up to date
git checkout main
git pull origin main

# Create a new feature branch
git checkout -b feature/add-ec2-<environment>-<purpose>

# Example:
git checkout -b feature/add-ec2-staging-api-server
```

### Step 2: Create Environment Configuration File

Create a new `.auto.tfvars` file for your environment:

```bash
# Create a new environment file (e.g., staging)
vim terraform/ec2/staging.auto.tfvars
```

### Step 3: Configure Instance Settings and Tags

Add your configuration using the `instances` variable. **Important:** All `*.auto.tfvars` files use the same `instances` variable - Terraform automatically merges them!

```hcl
# ─────────────────────────────────────────────
# Environment Configuration
# ─────────────────────────────────────────────

environment_name = "staging"

instance_config = {
  instance_type    = "t3.micro"
  aws_region       = "us-east-2"
  hcp_channel_name = "latest"

  # Tags
  cost_center   = "IBM Engineering staging"
  project       = "IBM Pipeline staging"
  environment   = "staging"
  owner         = "IBM DevOps Team staging"
  business_unit = "IBM Technology Infrastructure staging"

  # Ports
  ingress_ports = [
    {
      port        = 22
      description = "SSH from anywhere."
    },
    {
      port        = 80
      description = "HTTP from anywhere"
    },
    {
      port        = 443
      description = "HTTPS from anywhere"
    },
    {
      port        = 8080
      description = "Dev tools from anywhere"
    },
    {
      port        = 8081
      description = "Dev tools from anywhere"
    }
  ]
}
```

### Step 4: Validate Configuration

```bash
# Navigate to the EC2 terraform directory
cd terraform/ec2

# Initialize Terraform (if not already done)
terraform init

# Validate the configuration
terraform validate

# Format the code
terraform fmt

# Plan the changes (Terraform automatically loads all *.auto.tfvars files)
terraform plan
```

### Step 5: Commit Changes

```bash
# Add the new/modified files
git add terraform/ec2/staging.auto.tfvars

# Commit with a descriptive message
git commit -m "feat: add staging EC2 instance configuration

- Add staging.auto.tfvars with t3.small instance
- Configure tags for cost center: Engineering
- Set owner: Backend Team
- Environment: Staging"
```

### Step 6: Push Branch and Create Pull Request

```bash
# Push the branch to remote
git push origin feature/add-ec2-staging-api-server
```

Then create a Pull Request:

1. Go to your repository on GitHub/GitLab
2. Click "New Pull Request" or "Create Merge Request"
3. Select your feature branch as the source
4. Select `main` as the target branch
5. Fill in the PR template:
   - **Title:** `feat: Add staging EC2 instance for API Gateway`
   - **Description:**
     ```
     ## Changes
     - Added staging.auto.tfvars for new staging environment
     - Configured t3.small instance type
     - Added proper cost allocation tags

     ## Tags Applied
     - Cost Center: Engineering
     - Project: API Gateway Staging
     - Environment: Staging
     - Owner: Backend Team
     - Business Unit: Product Development

     ## Testing
     - [ ] Terraform validate passed
     - [ ] Terraform plan reviewed
     - [ ] Tags verified in plan output
     ```

### Step 7: Code Review and Approval

1. Request review from:

   - Team lead or senior engineer
   - DevOps/Platform team member
   - Cost management stakeholder (for production)
2. Address any feedback or requested changes
3. Ensure CI/CD checks pass:

   - Terraform validation
   - Sentinel policy checks
   - Security scans

### Step 8: Merge and Deploy

Once approved:

1. **Merge the Pull Request:**

   ```bash
   # Via GitHub/GitLab UI or command line
   git checkout main
   git pull origin main
   ```
2. **Automatic Deployment:**

   - The Harness pipeline will automatically trigger
   - Terraform will apply the changes
   - EC2 instance will be provisioned with proper tags
3. **Verify Deployment:**

   ```bash
   # Check Terraform Cloud workspace
   # Verify in AWS Console that tags are applied
   # Confirm instance is running
   ```

---

## Environment-Specific Configuration

### Development Environment (`dev.auto.tfvars`)

**Purpose:** Development and testing
**Instance Type:** `t3.micro` (cost-effective)
**Region:** `us-east-2`
**HCP Channel:** `latest`

```hcl
instance_type = "t3.micro"
aws_region    = "us-east-2"
hcp_bucket_name  = "hcp-ami-pipeline"
hcp_channel_name = "latest"

cost_center = "Engineering"
project = "AMI Pipeline Development"
environment = "Development"
owner = "DevOps Team"
business_unit = "Technology Infrastructure"
```

### Production Environment (`prod.auto.tfvars`)

**Purpose:** Production workloads
**Instance Type:** `t3.small` (better performance)
**Region:** `us-east-1`
**HCP Channel:** `production`

```hcl
instance_type = "t3.small"
aws_region    = "us-east-1"
hcp_bucket_name  = "hcp-ami-pipeline"
hcp_channel_name = "production"

cost_center = "Operations"
project = "AMI Pipeline Production"
environment = "Production"
owner = "Platform Engineering Team"
business_unit = "Technology Infrastructure"
```

---

## Example Configurations

### Example 1: Adding a Staging Environment

**File:** `terraform/ec2/staging.auto.tfvars`

```hcl
instances = {
  staging = {
    instance_type    = "t3.small"
    aws_region       = "us-west-2"
    hcp_channel_name = "staging"

    cost_center   = "Engineering"
    project       = "Customer Portal Staging"
    environment   = "Staging"
    owner         = "Frontend Team"
    business_unit = "Product Development"

    ingress_ports = [
      {
        port        = 22
        description = "SSH from anywhere"
      },
      {
        port        = 80
        description = "HTTP from anywhere"
      },
      {
        port        = 443
        description = "HTTPS from anywhere"
      }
    ]
  }
}
```

### Example 2: Adding a QA Environment

**File:** `terraform/ec2/qa.auto.tfvars`

```hcl
instances = {
  qa = {
    instance_type    = "t3.micro"
    aws_region       = "us-east-2"
    hcp_channel_name = "qa"

    cost_center   = "Quality Assurance"
    project       = "Automated Testing Infrastructure"
    environment   = "QA"
    owner         = "QA Team"
    business_unit = "Quality Engineering"

    ingress_ports = [
      {
        port        = 22
        description = "SSH from anywhere"
      },
      {
        port        = 80
        description = "HTTP from anywhere"
      }
    ]
  }
}
```

### Example 3: Adding Multiple Instances in One File

**File:** `terraform/ec2/test-environments.auto.tfvars`

```hcl
instances = {
  test1 = {
    instance_type    = "t3.micro"
    aws_region       = "us-east-1"
    hcp_channel_name = "latest"
    cost_center      = "Engineering"
    project          = "Test Environment 1"
    environment      = "Test"
    owner            = "QA Team"
    business_unit    = "Quality Engineering"
    ingress_ports = [
      { port = 22, description = "SSH" },
      { port = 80, description = "HTTP" }
    ]
  }
  test2 = {
    instance_type    = "t3.micro"
    aws_region       = "us-east-2"
    hcp_channel_name = "latest"
    cost_center      = "Engineering"
    project          = "Test Environment 2"
    environment      = "Test"
    owner            = "QA Team"
    business_unit    = "Quality Engineering"
    ingress_ports = [
      { port = 22, description = "SSH" },
      { port = 80, description = "HTTP" }
    ]
  }
}
```

---

## Troubleshooting

### Issue: Tags Not Showing in AWS Cost Explorer or Cloudability

**Possible Causes:**

1. Tags were not properly applied during resource creation
2. Cost allocation tags not activated in AWS Billing Console
3. Delay in tag propagation (can take 24-48 hours)

**Solutions:**

```bash
# 1. Verify tags in Terraform plan
terraform plan -var-file="your-env.auto.tfvars" | grep -A 10 "tags"

# 2. Check tags on deployed resources
aws ec2 describe-instances --instance-ids i-xxxxx --query 'Reservations[*].Instances[*].Tags'

# 3. Activate cost allocation tags in AWS Console:
# AWS Console → Billing → Cost Allocation Tags → Activate tags
```

### Issue: Terraform Plan Shows Tag Changes

**Cause:** Tag values in tfvars don't match deployed resources

**Solution:**

```bash
# Review the plan carefully
terraform plan -var-file="your-env.auto.tfvars"

# If intentional, apply the changes
terraform apply -var-file="your-env.auto.tfvars"

# If unintentional, revert tfvars to match current state
```

### Issue: Missing Required Variables

**Error:** `Error: No value for required variable`

**Solution:**
Ensure all required fields are defined in your `instances` map within the `.auto.tfvars` file:

```hcl
instances = {
  your_env = {
    instance_type    = "t3.micro"
    aws_region       = "us-east-2"
    hcp_channel_name = "latest"
    cost_center      = "YourDepartment"
    project          = "YourProject"
    environment      = "YourEnvironment"
    owner            = "YourTeam"
    business_unit    = "YourBusinessUnit"
    ingress_ports    = [...]
  }
}
```

### Issue: Vault Authentication Failure

**Error:** `Error: failed to read Vault secret`

**Solution:**

```bash
# Verify Vault token is set
echo $TF_VAR_vault_token

# Test Vault connectivity
vault status

# Renew token if expired
vault token renew
```

---

## Additional Resources

- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [HCP Packer Documentation](https://developer.hashicorp.com/packer/docs/hcp)
- [AWS Tagging Best Practices](https://docs.aws.amazon.com/general/latest/gr/aws_tagging.html)
- [Terraform Cloud Workspaces](https://developer.hashicorp.com/terraform/cloud-docs/workspaces)

---

## Support

For questions or issues:

- **DevOps Team:** devops@company.com
- **Slack Channel:** #infrastructure-support
- **Documentation:** [Internal Wiki](https://wiki.company.com/infrastructure)

---

**Last Updated:** 2026-05-08
**Maintained By:** DevOps Team
