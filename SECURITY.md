# Security Policy

## Supported versions

| Version | Supported |
|---|---|
| 0.1.x (latest) | ✅ Security fixes |
| < 0.1.0 | ❌ |

---

## Reporting a vulnerability

**Do not open a public GitHub issue for security vulnerabilities.**

Email: emanthen@gmail.com  
Subject line: `[SECURITY] Stacklift — <brief description>`

Include:
- Description of the vulnerability
- Steps to reproduce or a proof-of-concept
- Potential impact
- Any suggested fix (optional)

**Response SLA:** Acknowledgement within 48 hours. Fix timeline depends on severity:

| Severity | Fix timeline |
|---|---|
| Critical (data exposure, credential leak) | 48 hours |
| High (privilege escalation, IAM bypass) | 7 days |
| Medium (information disclosure) | 30 days |
| Low | Next release |

You will receive credit in the CHANGELOG unless you prefer to remain anonymous.

---

## Security design

Stacklift is built around these security defaults. Understanding them helps you evaluate risk.

### No long-lived AWS credentials in CI/CD

The `cicd` module creates a GitHub Actions OIDC provider and IAM role. GitHub exchanges a short-lived OIDC token for temporary AWS credentials scoped to a single repository and branch. Nothing is stored in GitHub Secrets.

Trust policy uses `StringLike` on the `sub` claim:
```
token.actions.githubusercontent.com:sub → repo:ORG/REPO:ref:refs/heads/BRANCH
```

### No plaintext secrets in Terraform state

All passwords and API keys are stored in AWS Secrets Manager. ECS injects them as environment variables at task startup — the application reads `os.environ["DATABASE_URL"]`, never fetches secrets itself.

RDS passwords are generated via `random_password` with `lifecycle { ignore_changes = [password] }` so Terraform never rotates a live database password on apply.

### ECS tasks in private subnets

All ECS Fargate tasks run in private subnets with `assign_public_ip = false`. Outbound traffic routes through a NAT Gateway. Inbound traffic reaches the container only through the ALB security group.

### RDS protected from accidental deletion

Two independent guards:
- `deletion_protection = true` on the RDS instance (AWS-level protection)
- `lifecycle { prevent_destroy = true }` in Terraform (plan-level protection)

Both must be removed before `terraform destroy` will succeed. This is intentional.

### IAM least-privilege

Each ECS service gets two IAM roles:
- **Execution role**: ECR pull + Secrets Manager read + CloudWatch Logs write. Only the specific secret ARNs are allowed.
- **Task role**: empty by default. Extend via `task_role_policy_arns` for exactly the permissions your app needs.

The `cicd` IAM role uses `iam:PassRole` scoped to the specific task execution and task role ARNs — not `iam:PassRole: *`.

### TLS 1.3 enforced at the ALB

The HTTPS listener uses `ELBSecurityPolicy-TLS13-1-2-2021-06` — TLS 1.3 preferred, TLS 1.2 minimum, TLS 1.0/1.1 rejected.

---

## Known limitations

- **Terraform state contains resource IDs and ARNs.** State is stored in S3 with SSE-AES256. It does not contain secret values (passwords are in Secrets Manager), but it does contain subnet IDs, security group IDs, and other infrastructure metadata. Ensure your S3 backend bucket is private with versioning enabled.

- **`random_password` result is in Terraform state.** The RDS password is stored in state (base64-encoded) in addition to Secrets Manager. The state is encrypted at rest. For higher security, consider a secrets rotation Lambda (available in the Pro tier).

- **Container image scanning is basic.** ECR Basic Scanning is enabled by default. For production, consider enabling ECR Enhanced Scanning (Amazon Inspector) for continuous vulnerability assessment.
