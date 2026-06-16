# CLI Reference

## Installation

```bash
pip install stacklift
```

Requires Python >= 3.11.

---

## Commands

### `stacklift init`

Scaffold production AWS infrastructure into the current directory.

```bash
stacklift init [OPTIONS]
```

**Options:**

| Option | Default | Description |
|---|---|---|
| `--output`, `-o` | `.` | Directory to write files into |
| `--overwrite` | `false` | Overwrite existing files |
| `--skip-checks` | `false` | Skip pre-flight environment checks |
| `--version`, `-v` | — | Print version and exit |
| `--help` | — | Show help and exit |

**Examples:**

```bash
# Scaffold into current directory
stacklift init

# Scaffold into a specific directory
stacklift init --output ./infra

# Re-scaffold and overwrite existing files
stacklift init --overwrite

# Skip checks (e.g. in CI where Docker is not available)
stacklift init --skip-checks
```

---

## Pre-flight checks

`stacklift init` runs four checks before showing any prompts:

| Check | What it verifies | Fix if failing |
|---|---|---|
| AWS CLI | `aws --version` exits 0 | Install from aws.amazon.com/cli |
| AWS credentials | `aws sts get-caller-identity` exits 0 | Run `aws configure` or set env vars |
| Terraform | `terraform --version` >= 1.5 | Install from developer.hashicorp.com |
| Docker | `docker info` exits 0 | Start Docker Desktop |

All four must pass before prompts are shown. Use `--skip-checks` only in environments where you know the tools are available but not all checks pass (e.g. CI without Docker).

---

## Interactive prompts

`stacklift init` asks 11 questions:

| Prompt | Default | Validation |
|---|---|---|
| Project name | `my-saas` | 3–30 chars, lowercase, letters/numbers/hyphens |
| AWS region | `us-east-1` | Any region string |
| Domain name | `api.example.com` | Valid domain format |
| Framework | `django` | `django` or `fastapi` |
| Database instance class | `db.t3.micro` | Any valid RDS instance class |
| ECS CPU units | `256` | 256, 512, 1024, 2048, 4096 |
| ECS memory (MB) | `512` | Must be compatible with chosen CPU |
| Enable Celery + Redis? | `n` | Django only |
| Enable staging environment? | `n` | |
| GitHub org / username | — | Non-empty |
| GitHub repository name | project name | Non-empty |

---

## Output files

```
infra/
  main.tf           ← all 8 modules wired together
  variables.tf      ← variable declarations
  terraform.tfvars  ← pre-filled with your answers
  backend.tf        ← S3 backend setup instructions
.github/
  workflows/
    deploy.yml      ← complete CI/CD workflow
```

---

## After scaffolding

1. Create the S3 backend (see the comment in `infra/backend.tf`)
2. Fill in `infra/terraform.tfvars` — set `route53_zone_id`
3. `terraform init -backend-config=backend.tfvars`
4. `terraform plan`
5. `terraform apply`
6. Update secrets: `aws secretsmanager put-secret-value ...`
7. Set GitHub Actions variables from `terraform output`
8. Push to your branch → CI/CD deploys automatically
