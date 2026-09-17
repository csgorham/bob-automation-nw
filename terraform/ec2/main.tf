terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 3.0"
    }
    hcp = {
      source  = "hashicorp/hcp"
      version = "~> 0.82"
    }
  }

  cloud {
    organization = "dev_space-cgh"
    workspaces {
      tags = ["ec2", "ami-pipeline"]
    }
  }
}

# ── Vault Provider ─────────────────────────────────────────────────
provider "vault" {
  address = var.vault_addr
  token   = var.vault_token
}

# ── Dynamic AWS Credentials from Vault ────────────────────────────
data "vault_aws_access_credentials" "creds" {
  backend = "aws"
  role    = "demo-role"
}

provider "aws" {
  region     = var.instance_config.aws_region
  access_key = data.vault_aws_access_credentials.creds.access_key
  secret_key = data.vault_aws_access_credentials.creds.secret_key
  token      = data.vault_aws_access_credentials.creds.security_token
}

# ── HCP Packer Credentials from Vault ─────────────────────────────
data "vault_kv_secret_v2" "hcp_packer" {
  mount = "secret"
  name  = "ami-pipeline/hcp-packer"
}

provider "hcp" {
  client_id     = data.vault_kv_secret_v2.hcp_packer.data["hcp_client_id"]
  client_secret = data.vault_kv_secret_v2.hcp_packer.data["hcp_client_secret"]
  project_id    = data.vault_kv_secret_v2.hcp_packer.data["hcp_project_id"]
}

# ── HCP Packer: Resolve Latest AMI ────────────────────────────────
data "hcp_packer_artifact" "ami" {
  bucket_name  = var.hcp_bucket_name
  channel_name = var.instance_config.hcp_channel_name
  platform     = "aws"
  region       = var.instance_config.aws_region
}

# ── Remote State: VPC & Subnet from network workspace ─────────────
data "terraform_remote_state" "network" {
  backend = "remote"
  config = {
    organization = "dev_space-cgh"
    workspaces = {
      name = "ami-pipeline-network"
    }
  }
}

# ── Security Group — dynamically built from ports.yaml catalog ─────
#
# ingress_ports in the instance_config (from *.auto.tfvars) are sourced
# from the port catalog at terraform/ec2/ports.yaml.  Bob reads that
# catalog when a developer requests a port change, validates risk_level
# and allowed_environments, then edits the tfvars block.  Terraform
# iterates this list here and creates one ingress rule per entry.
#
resource "aws_security_group" "web" {
  name        = "ami-pipeline-${var.environment_name}-sg"
  description = "Security group for ami-pipeline ${var.environment_name} environment"
  vpc_id      = data.terraform_remote_state.network.outputs.vpc_id

  # ── Dynamic ingress rules decoded from tfvars ingress_ports list ──
  dynamic "ingress" {
    for_each = var.instance_config.ingress_ports
    content {
      from_port   = ingress.value.port
      to_port     = ingress.value.port
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
      description = ingress.value.description
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name         = "ami-pipeline-${var.environment_name}-sg"
    Environment  = var.instance_config.environment
    CostCenter   = var.instance_config.cost_center
    Project      = var.instance_config.project
    Owner        = var.instance_config.owner
    BusinessUnit = var.instance_config.business_unit
    ManagedBy    = "terraform"
  }
}

# ── EC2 Instance ───────────────────────────────────────────────────
resource "aws_instance" "web" {
  ami                         = data.hcp_packer_artifact.ami.external_identifier
  instance_type               = var.instance_config.instance_type
  subnet_id                   = data.terraform_remote_state.network.outputs.subnet_id
  vpc_security_group_ids      = [aws_security_group.web.id]
  associate_public_ip_address = true

  tags = {
    Name         = "ami-pipeline-${var.environment_name}"
    Environment  = var.instance_config.environment
    CostCenter   = var.instance_config.cost_center
    Project      = var.instance_config.project
    Owner        = var.instance_config.owner
    BusinessUnit = var.instance_config.business_unit
    ManagedBy    = "terraform"
    AMISource    = "hcp-packer"
  }
}

# ── Outputs ────────────────────────────────────────────────────────
output "instance_id" {
  value       = aws_instance.web.id
  description = "EC2 instance ID"
}

output "public_ip" {
  value       = aws_instance.web.public_ip
  description = "Public IP address of the EC2 instance"
}

output "security_group_id" {
  value       = aws_security_group.web.id
  description = "Security group ID"
}

output "ami_id" {
  value       = data.hcp_packer_artifact.ami.external_identifier
  description = "AMI ID resolved from HCP Packer"
}
