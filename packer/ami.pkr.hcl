packer {
  required_plugins {
    amazon = {
      version = ">= 1.2.0"
      source  = "github.com/hashicorp/amazon"
    }
    ansible = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/ansible"
    }
  }
}

# HCP Packer Registry Configuration
# Bucket will be auto-created on first build
hcp_packer_registry {
  bucket_name = var.hcp_bucket_name
  description = <<EOT
Hardened Amazon Linux 2023 AMI with security configurations and baseline packages.
Built with Ansible provisioning for consistent infrastructure.
  EOT

  bucket_labels = {
    "owner"          = "Platform Team"
    "os"             = "Amazon Linux 2023"
    "pipeline"       = "Harness"
    "security_level" = "hardened"
  }

  build_labels = {
    "build-time"   = timestamp()
    "build-source" = basename(path.cwd)
    "version"      = var.version
    "ansible"      = "true"
  }
}

source "amazon-ebs" "base" {
  region        = var.aws_region
  instance_type = var.instance_type

  # ✅ Dynamic base AMI (no hardcoding)
  source_ami_filter {
    filters = {
      name                = "al2023-ami-*-x86_64"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }

    owners      = ["amazon"]
    most_recent = true
  }

  # Networking (from Terraform/Vault/Harness)
  vpc_id    = var.vpc_id
  subnet_id = var.subnet_id

  ami_name = "${var.ami_name}-{{timestamp}}"

  ssh_username = "ec2-user"

  tags = {
    Name      = var.ami_name
    BuildDate = "{{timestamp}}"
    Pipeline  = "harness"
  }
}

build {
  sources = ["source.amazon-ebs.base"]

  # 🛠️ Harden / install software / configure OS
  provisioner "ansible" {
    playbook_file   = "../ansible/site.yaml"
    user            = "ec2-user"
    use_sftp        = false
    extra_arguments = [
      "-e", "ansible_remote_tmp=/tmp/.ansible/tmp",
      "--scp-extra-args", "'-O'"
    ]
  }

  # 📦 Output artifact metadata for Vault + Terraform
  post-processor "manifest" {
    output     = "manifest.json"
    strip_path = true
  }
}
