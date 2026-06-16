# S3 + DynamoDB remote state
#
# 1. Create the bucket and lock table ONCE (per AWS account, not per project):
#
#    aws s3api create-bucket \
#      --bucket stacklift-tfstate-mysaas \
#      --region us-east-1 \
#      --no-cli-pager
#
#    aws s3api put-bucket-versioning \
#      --bucket stacklift-tfstate-mysaas \
#      --versioning-configuration Status=Enabled \
#      --no-cli-pager
#
#    aws s3api put-bucket-encryption \
#      --bucket stacklift-tfstate-mysaas \
#      --server-side-encryption-configuration \
#        '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}' \
#      --no-cli-pager
#
#    aws dynamodb create-table \
#      --table-name stacklift-tfstate-lock \
#      --attribute-definitions AttributeName=LockID,AttributeType=S \
#      --key-schema AttributeName=LockID,KeyType=HASH \
#      --billing-mode PAY_PER_REQUEST \
#      --region us-east-1 \
#      --no-cli-pager
#
# 2. Create backend.tfvars with your values (do not commit this file):
#
#    bucket         = "stacklift-tfstate-mysaas"
#    key            = "prod/terraform.tfstate"
#    region         = "us-east-1"
#    dynamodb_table = "stacklift-tfstate-lock"
#    encrypt        = true
#
# 3. Initialise:
#
#    terraform init -backend-config=backend.tfvars
#
# The backend block below is intentionally empty — values are loaded at init time.
# Terraform does not allow variable interpolation in backend blocks.
