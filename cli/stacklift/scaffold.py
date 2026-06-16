"""Render Jinja2 templates and write scaffolded files."""

from __future__ import annotations

from pathlib import Path

from jinja2 import Environment, FileSystemLoader, StrictUndefined
from rich.console import Console

from .prompts import ProjectConfig
from .utils import safe_write, templates_dir

console = Console()

STACKLIFT_REF = "v0.1.0"
STACKLIFT_SOURCE = "github.com/emanthen/Stacklift"


def _jinja_env() -> Environment:
    return Environment(
        loader=FileSystemLoader(str(templates_dir())),
        undefined=StrictUndefined,
        trim_blocks=True,
        lstrip_blocks=True,
        keep_trailing_newline=True,
    )


def _render(template_name: str, context: dict) -> str:
    env = _jinja_env()
    template = env.get_template(template_name)
    return template.render(**context)


def _build_context(config: ProjectConfig) -> dict:
    return {
        "project_name":      config.project_name,
        "environment":       config.environment,
        "aws_region":        config.aws_region,
        "domain_name":       config.domain_name,
        "framework":         config.framework,
        "db_instance_class": config.db_instance_class,
        "cpu":               config.cpu,
        "memory":            config.memory,
        "enable_celery":     config.enable_celery,
        "enable_staging":    config.enable_staging,
        "github_org":        config.github_org,
        "github_repo":       config.github_repo,
        "github_branch":     "main",
        "container_port":    config.container_port,
        "health_check_path": config.health_check_path,
        "stacklift_source":  STACKLIFT_SOURCE,
        "stacklift_ref":     STACKLIFT_REF,
    }


def scaffold(config: ProjectConfig, output_dir: Path, overwrite: bool = False) -> list[Path]:
    """Render all templates and write to output_dir. Returns list of written paths."""
    ctx = _build_context(config)
    written: list[Path] = []

    files: list[tuple[str, Path]] = [
        ("main.tf.j2",            output_dir / "infra" / "main.tf"),
        ("variables.tf.j2",       output_dir / "infra" / "variables.tf"),
        ("terraform.tfvars.j2",   output_dir / "infra" / "terraform.tfvars"),
        ("backend.tf.j2",         output_dir / "infra" / "backend.tf"),
        ("deploy.yml.j2",         output_dir / ".github" / "workflows" / "deploy.yml"),
    ]

    for template_name, dest in files:
        content = _render(template_name, ctx)
        did_write = safe_write(dest, content, overwrite=overwrite)
        if did_write:
            console.print(f"  [green]created[/green]  {dest.relative_to(output_dir)}")
            written.append(dest)
        else:
            console.print(f"  [yellow]skipped[/yellow]  {dest.relative_to(output_dir)} (already exists)")

    return written


def print_next_steps(config: ProjectConfig, output_dir: Path) -> None:
    p = config.project_name

    console.print()
    console.print("[bold green]✓ Scaffolding complete.[/bold green]")
    console.print()
    console.print("[bold underline]Next steps[/bold underline]")
    console.print()
    console.print("  [bold]1.[/bold] Create the S3 backend (once per AWS account):")
    console.print(f"       aws s3api create-bucket --bucket stacklift-tfstate-{p} --region {config.aws_region} --no-cli-pager")
    console.print(f"       aws dynamodb create-table --table-name stacklift-tfstate-lock \\")
    console.print( "         --attribute-definitions AttributeName=LockID,AttributeType=S \\")
    console.print( "         --key-schema AttributeName=LockID,KeyType=HASH \\")
    console.print( "         --billing-mode PAY_PER_REQUEST --no-cli-pager")
    console.print()
    console.print("  [bold]2.[/bold] Edit [cyan]infra/terraform.tfvars[/cyan] — fill in your Route53 zone ID and GitHub details.")
    console.print()
    console.print("  [bold]3.[/bold] Initialise Terraform:")
    console.print("       cd infra")
    console.print(f"       terraform init -backend-config=backend.tfvars")
    console.print()
    console.print("  [bold]4.[/bold] Review the plan:")
    console.print("       terraform plan")
    console.print()
    console.print("  [bold]5.[/bold] Apply (~10 minutes):")
    console.print("       terraform apply")
    console.print()
    console.print("  [bold]6.[/bold] Update secrets in Secrets Manager, set GitHub Actions variables, push to main.")
    console.print()
    console.print(f"  Full guide: [link]https://github.com/emanthen/Stacklift/blob/main/docs/tutorials/deploy-django-saas-in-30-minutes.md[/link]")
    console.print()
