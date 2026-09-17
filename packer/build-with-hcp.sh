#!/bin/bash
set -e

# HCP Packer Registry Build Script
# This script builds an AMI and registers it with HCP Packer Registry

echo "🚀 Building AMI with HCP Packer Registry Integration"
echo "=================================================="

# Check for required environment variables
if [ -z "$HCP_CLIENT_ID" ] || [ -z "$HCP_CLIENT_SECRET" ]; then
    echo "❌ ERROR: HCP credentials not set!"
    echo ""
    echo "Please set the following environment variables:"
    echo "  export HCP_CLIENT_ID='your-client-id'"
    echo "  export HCP_CLIENT_SECRET='your-client-secret'"
    echo ""
    echo "Get these from: HCP Portal → Access Control (IAM) → Service Principals"
    exit 1
fi

# Check for required Packer variables
if [ -z "$PKR_VAR_vpc_id" ] || [ -z "$PKR_VAR_subnet_id" ]; then
    echo "❌ ERROR: VPC/Subnet not set!"
    echo ""
    echo "Please set the following environment variables:"
    echo "  export PKR_VAR_vpc_id='vpc-xxxxx'"
    echo "  export PKR_VAR_subnet_id='subnet-xxxxx'"
    echo ""
    echo "Or pass them as arguments:"
    echo "  ./build-with-hcp.sh vpc-xxxxx subnet-xxxxx"
    exit 1
fi

# Allow passing VPC/Subnet as arguments
if [ ! -z "$1" ]; then
    export PKR_VAR_vpc_id="$1"
fi

if [ ! -z "$2" ]; then
    export PKR_VAR_subnet_id="$2"
fi

# Set defaults for optional variables
export PKR_VAR_hcp_bucket_name="${PKR_VAR_hcp_bucket_name:-hcp-ami-pipeline}"
export PKR_VAR_version="${PKR_VAR_version:-1.0.0}"
export PKR_VAR_aws_region="${PKR_VAR_aws_region:-us-east-2}"

echo "📋 Build Configuration:"
echo "  Bucket Name: $PKR_VAR_hcp_bucket_name"
echo "  Version: $PKR_VAR_version"
echo "  Region: $PKR_VAR_aws_region"
echo "  VPC: $PKR_VAR_vpc_id"
echo "  Subnet: $PKR_VAR_subnet_id"
echo ""

# Initialize Packer
echo "🔧 Initializing Packer..."
packer init .

# Validate configuration
echo "✅ Validating Packer configuration..."
packer validate \
    -var "hcp_bucket_name=$PKR_VAR_hcp_bucket_name" \
    -var "version=$PKR_VAR_version" \
    -var "vpc_id=$PKR_VAR_vpc_id" \
    -var "subnet_id=$PKR_VAR_subnet_id" \
    .

# Build AMI
echo "🏗️  Building AMI and registering with HCP..."
packer build \
    -var "hcp_bucket_name=$PKR_VAR_hcp_bucket_name" \
    -var "version=$PKR_VAR_version" \
    -var "vpc_id=$PKR_VAR_vpc_id" \
    -var "subnet_id=$PKR_VAR_subnet_id" \
    .

echo ""
echo "✅ Build complete!"
echo ""
echo "📦 Next steps:"
echo "  1. Go to HCP Portal: https://portal.cloud.hashicorp.com/"
echo "  2. Navigate to Packer → $PKR_VAR_hcp_bucket_name"
echo "  3. You should see version $PKR_VAR_version"
echo "  4. Assign it to a channel (e.g., 'production', 'staging', 'latest')"
echo "  5. Use in Terraform with the hcp_packer_artifact data source"
echo ""

# Made with Bob
