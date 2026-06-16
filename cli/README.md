# stacklift CLI

Scaffold production AWS infrastructure for Django and FastAPI in minutes.

## Install

```bash
pip install stacklift
```

Requires Python >= 3.11.

## Usage

```bash
cd your-project
stacklift init
```

Runs pre-flight checks (AWS CLI, credentials, Terraform >= 1.5, Docker), asks 11 questions, and writes:

```
infra/
  main.tf           ← all 8 Stacklift modules wired together
  variables.tf
  terraform.tfvars  ← pre-filled with your answers
  backend.tf        ← S3 backend setup instructions
.github/
  workflows/
    deploy.yml      ← build → ECR push → ECS deploy
```

## Options

```
--output, -o    Directory to scaffold into (default: current directory)
--overwrite     Overwrite existing files
--skip-checks   Skip pre-flight checks
--version, -v   Print version and exit
```

## Development

```bash
cd cli
pip install -e ".[dev]"
pytest --cov=stacklift tests/
```

Full reference: [docs/cli-reference.md](../docs/cli-reference.md)
