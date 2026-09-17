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
  }

  cloud {
    organization = "dev_space-cgh"
    workspaces {
      name = "ami-pipeline-network"
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
  region     = var.aws_region
  access_key = data.vault_aws_access_credentials.creds.access_key
  secret_key = data.vault_aws_access_credentials.creds.secret_key
  token      = data.vault_aws_access_credentials.creds.security_token
}

# ── VPC ────────────────────────────────────────────────────────────
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name         = "ami-pipeline-vpc"
    Project      = "ami-pipeline"
    Environment  = var.environment
    ManagedBy    = "terraform"
    Owner        = var.owner
    CostCenter   = var.cost_center
    BusinessUnit = var.business_unit
  }
}

# ── Internet Gateway ───────────────────────────────────────────────
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name         = "ami-pipeline-igw"
    Project      = "ami-pipeline"
    Environment  = var.environment
    ManagedBy    = "terraform"
    Owner        = var.owner
    CostCenter   = var.cost_center
    BusinessUnit = var.business_unit
  }
}

# ── Public Subnet ──────────────────────────────────────────────────
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true

  tags = {
    Name         = "ami-pipeline-public-subnet"
    Project      = "ami-pipeline"
    Environment  = var.environment
    ManagedBy    = "terraform"
    Owner        = var.owner
    CostCenter   = var.cost_center
    BusinessUnit = var.business_unit
  }
}

# ── Route Table ────────────────────────────────────────────────────
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name         = "ami-pipeline-public-rt"
    Project      = "ami-pipeline"
    Environment  = var.environment
    ManagedBy    = "terraform"
    Owner        = var.owner
    CostCenter   = var.cost_center
    BusinessUnit = var.business_unit
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ── Outputs ────────────────────────────────────────────────────────
output "vpc_id" {
  value       = aws_vpc.main.id
  description = "VPC ID — consumed by ec2 workspace via remote state"
}

output "public_subnet_id" {
  value       = aws_subnet.public.id
  description = "Public subnet ID — consumed by ec2 workspace via remote state"
}

output "vpc_cidr" {
  value       = aws_vpc.main.cidr_block
  description = "VPC CIDR block"
}
