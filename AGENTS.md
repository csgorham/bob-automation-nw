# AGENTS.md

This file provides guidance to agents when working with code in this repository.

## Commands

### Terraform Operations
- Init & Plan per module directory (`terraform/network`, `terraform/s3`, `terraform/ec2`):
  ```bash
  cd terraform/ec2 && terraform init
  terraform plan -var-file=dev.auto.tfvars -var="vault_addr=$VAULT_ADDR" -var="vault_token=$VAULT_TOKEN"
  ```
- Target specific resource plan/apply:
  ```bash
  terraform plan -target=aws_instance.web -var-file=dev.auto.tfvars
  ```

### Ansible Drift Operations
- Run drift detection against a single host:
  ```bash
  cd ansible && ansible-playbook drift-detection.yaml -i "<EC2_IP>," --private-key="$SSH_KEY_PATH" -u ec2-user
  ```
- Run targeted drift remediation against a single host:
  ```bash
  cd ansible && ansible-playbook drift-remediation.yaml -i "<EC2_IP>," --private-key="$SSH_KEY_PATH" -u ec2-user
  ```
- Simulate drift (testing/demo scenario):
  ```bash
  cd ansible && ansible-playbook simulate-apache-drift.yaml -i "<EC2_IP>," --private-key="$SSH_KEY_PATH" -u ec2-user
  ```

### Sentinel & Packer
- Test Sentinel policies locally:
  ```bash
  cd sentinel && sentinel test
  ```
- Validate Packer templates:
  ```bash
  cd packer && packer validate -var-file=variables.pkr.hcl ami.pkr.hcl
  ```

## Non-Obvious Project Patterns & Gotchas

- **Dynamic Ports Source of Truth**: Security group ingress rules in `terraform/ec2` are dynamically decoded from `terraform/ec2/ports.yaml` via `yamldecode(file("${path.module}/ports.yaml"))`. Do not hardcode port definitions directly in Terraform security group resources.
- **Vault Dynamic Credentials**: Terraform relies on Vault data sources (`data "vault_aws_access_credentials" "creds"` under `role = "demo-role"`) and `data "vault_kv_secret_v2" "hcp_packer"` for HCP credentials. `vault_addr` and `vault_token` variables are required for provider execution.
- **Isolated Terraform State Architecture**: `terraform/s3`, `terraform/network`, and `terraform/ec2` are structured as independent state workspaces using HCP Terraform / Terraform Cloud tags (`tags = ["ec2", "ami-pipeline"]`). Cross-stack attributes rely on remote state references or shared configuration conventions rather than a unified root module.
- **Ansible Drift Output Structure**: Drift reports are JSON-formatted and saved to `/var/log/drift-reports/` on managed nodes (`drift-report-<timestamp>.json` and `remediation-report-<timestamp>.json`).
