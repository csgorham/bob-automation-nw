# ─────────────────────────────────────────────
# Development Environment Configuration
# ─────────────────────────────────────────────

environment_name = "dev"

instance_config = {
  instance_type    = "t3.micro"
  aws_region       = "us-east-2"
  hcp_channel_name = "latest"

  # Tags
  cost_center   = "IBM Engineering"
  project       = "IBM Pipeline Development"
  environment   = "Development"
  owner         = "IBM DevOps Team"
  business_unit = "IBM Technology Infrastructure"

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
      port        = 8082
      description = "Dev tools from anywhere"
    }
  ]
}
