"""Interactive prompts for stacklift init."""

from __future__ import annotations

from dataclasses import dataclass, field

from rich.console import Console
from rich.prompt import Confirm, Prompt

console = Console()

AWS_REGIONS = [
    "us-east-1", "us-east-2", "us-west-1", "us-west-2",
    "eu-west-1", "eu-west-2", "eu-central-1",
    "ap-southeast-1", "ap-southeast-2", "ap-northeast-1",
    "ca-central-1", "sa-east-1",
]

DB_INSTANCE_CLASSES = [
    "db.t3.micro", "db.t3.small", "db.t3.medium",
    "db.t4g.micro", "db.t4g.small", "db.t4g.medium",
    "db.m5.large", "db.m6g.large",
]

VALID_CPU = [256, 512, 1024, 2048, 4096]
VALID_MEMORY = {
    256:  [512, 1024, 2048],
    512:  [1024, 2048, 3072, 4096],
    1024: [2048, 3072, 4096, 5120, 6144, 7168, 8192],
    2048: list(range(4096, 16385, 1024)),
    4096: list(range(8192, 30721, 1024)),
}


@dataclass
class ProjectConfig:
    project_name: str = ""
    aws_region: str = "us-east-1"
    domain_name: str = ""
    framework: str = "django"
    db_instance_class: str = "db.t3.micro"
    cpu: int = 256
    memory: int = 512
    enable_celery: bool = False
    enable_staging: bool = False
    github_org: str = ""
    github_repo: str = ""

    # Derived — populated after prompts
    route53_zone_id: str = "REPLACE_WITH_YOUR_ZONE_ID"
    environment: str = "prod"
    container_port: int = 8000
    health_check_path: str = field(init=False)

    def __post_init__(self) -> None:
        self.health_check_path = "/health" if self.framework == "fastapi" else "/api/health/"


def _prompt_project_name() -> str:
    import re

    while True:
        value = Prompt.ask("  [cyan]Project name[/cyan]", default="my-saas")
        value = value.strip().lower()
        if re.match(r"^[a-z][a-z0-9-]{1,28}[a-z0-9]$", value):
            return value
        console.print(
            "  [red]Must be 3–30 chars, lowercase letters/numbers/hyphens, start with a letter.[/red]"
        )


def _prompt_region() -> str:
    value = Prompt.ask("  [cyan]AWS region[/cyan]", default="us-east-1")
    value = value.strip()
    if value not in AWS_REGIONS:
        console.print(f"  [yellow]Warning:[/yellow] '{value}' is not a common region — proceeding anyway.")
    return value


def _prompt_domain() -> str:
    import re

    while True:
        value = Prompt.ask("  [cyan]Domain name[/cyan]", default="api.example.com")
        value = value.strip().lower().lstrip("https://").lstrip("http://").rstrip("/")
        if re.match(r"^[a-z0-9][a-z0-9\-\.]+\.[a-z]{2,}$", value):
            return value
        console.print("  [red]Enter a valid domain (e.g. api.mysaas.com).[/red]")


def _prompt_framework() -> str:
    value = Prompt.ask(
        "  [cyan]Framework[/cyan]",
        choices=["django", "fastapi"],
        default="django",
    )
    return value


def _prompt_db_instance_class() -> str:
    value = Prompt.ask("  [cyan]Database instance class[/cyan]", default="db.t3.micro")
    value = value.strip()
    if value not in DB_INSTANCE_CLASSES:
        console.print(f"  [yellow]Warning:[/yellow] '{value}' not in common classes — proceeding anyway.")
    return value


def _prompt_cpu() -> int:
    while True:
        raw = Prompt.ask("  [cyan]ECS CPU units[/cyan]", default="256")
        try:
            value = int(raw)
        except ValueError:
            console.print("  [red]Enter a number.[/red]")
            continue
        if value not in VALID_CPU:
            console.print(f"  [red]Must be one of: {', '.join(str(v) for v in VALID_CPU)}[/red]")
            continue
        return value


def _prompt_memory(cpu: int) -> int:
    valid = VALID_MEMORY.get(cpu, [512])
    default = valid[0]
    while True:
        raw = Prompt.ask(f"  [cyan]ECS memory (MB)[/cyan]", default=str(default))
        try:
            value = int(raw)
        except ValueError:
            console.print("  [red]Enter a number.[/red]")
            continue
        if value not in valid:
            console.print(f"  [red]For {cpu} CPU, memory must be one of: {', '.join(str(v) for v in valid)}[/red]")
            continue
        return value


def _prompt_github_org() -> str:
    while True:
        value = Prompt.ask("  [cyan]GitHub org / username[/cyan]", default="my-github-username")
        value = value.strip()
        if value:
            return value
        console.print("  [red]GitHub org cannot be empty.[/red]")


def _prompt_github_repo(project_name: str) -> str:
    value = Prompt.ask("  [cyan]GitHub repository name[/cyan]", default=project_name)
    return value.strip()


def collect(skip_preflight_output: bool = False) -> ProjectConfig:
    console.print()
    console.print("[bold]Stacklift Init[/bold] — answer a few questions to scaffold your infrastructure.\n")

    project_name    = _prompt_project_name()
    aws_region      = _prompt_region()
    domain_name     = _prompt_domain()
    framework       = _prompt_framework()
    db_instance     = _prompt_db_instance_class()
    cpu             = _prompt_cpu()
    memory          = _prompt_memory(cpu)
    enable_celery   = framework == "django" and Confirm.ask("  [cyan]Enable Celery + Redis?[/cyan]", default=False)
    enable_staging  = Confirm.ask("  [cyan]Enable staging environment?[/cyan]", default=False)
    github_org      = _prompt_github_org()
    github_repo     = _prompt_github_repo(project_name)

    config = ProjectConfig(
        project_name=project_name,
        aws_region=aws_region,
        domain_name=domain_name,
        framework=framework,
        db_instance_class=db_instance,
        cpu=cpu,
        memory=memory,
        enable_celery=enable_celery,
        enable_staging=enable_staging,
        github_org=github_org,
        github_repo=github_repo,
    )
    config.health_check_path = "/health" if framework == "fastapi" else "/api/health/"

    console.print()
    _print_summary(config)
    console.print()

    if not Confirm.ask("[bold]Scaffold these files?[/bold]", default=True):
        console.print("[yellow]Aborted.[/yellow]")
        raise SystemExit(0)

    return config


def _print_summary(config: ProjectConfig) -> None:
    console.print("[bold underline]Your configuration[/bold underline]")
    rows = [
        ("Project name", config.project_name),
        ("AWS region", config.aws_region),
        ("Domain", config.domain_name),
        ("Framework", config.framework),
        ("Database", config.db_instance_class),
        ("ECS (CPU / memory)", f"{config.cpu} / {config.memory} MB"),
        ("Celery worker", "yes" if config.enable_celery else "no"),
        ("Staging environment", "yes" if config.enable_staging else "no"),
        ("GitHub repo", f"{config.github_org}/{config.github_repo}"),
    ]
    for key, val in rows:
        console.print(f"  [dim]{key:<24}[/dim] {val}")
