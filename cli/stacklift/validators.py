"""Pre-flight checks run before any prompts are shown."""

from __future__ import annotations

import re
import shutil
import subprocess
from dataclasses import dataclass

from rich.console import Console

console = Console()

MIN_TERRAFORM_VERSION = (1, 5, 0)


@dataclass
class CheckResult:
    name: str
    passed: bool
    message: str
    fix: str = ""


def _run(cmd: list[str], timeout: int = 10) -> tuple[int, str, str]:
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        return result.returncode, result.stdout.strip(), result.stderr.strip()
    except FileNotFoundError:
        return 127, "", f"command not found: {cmd[0]}"
    except subprocess.TimeoutExpired:
        return 1, "", f"timed out after {timeout}s"


def check_aws_cli() -> CheckResult:
    code, stdout, _ = _run(["aws", "--version"])
    if code != 0 or not stdout:
        return CheckResult(
            name="AWS CLI",
            passed=False,
            message="AWS CLI not found.",
            fix="Install from https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html",
        )
    return CheckResult(name="AWS CLI", passed=True, message=stdout.splitlines()[0])


def check_aws_credentials() -> CheckResult:
    code, stdout, stderr = _run(["aws", "sts", "get-caller-identity", "--no-cli-pager"])
    if code != 0:
        detail = stderr or "no output"
        return CheckResult(
            name="AWS credentials",
            passed=False,
            message=f"AWS credentials not configured or insufficient permissions: {detail}",
            fix=(
                "Run: aws configure\n"
                "  Or set AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY / AWS_SESSION_TOKEN\n"
                "  Or configure an IAM role / SSO profile."
            ),
        )
    # Extract account ID for a friendly message
    import json

    try:
        identity = json.loads(stdout)
        account = identity.get("Account", "unknown")
        arn = identity.get("Arn", "unknown")
        return CheckResult(
            name="AWS credentials",
            passed=True,
            message=f"Account {account} ({arn})",
        )
    except (json.JSONDecodeError, KeyError):
        return CheckResult(name="AWS credentials", passed=True, message="credentials valid")


def check_terraform() -> CheckResult:
    if shutil.which("terraform") is None:
        return CheckResult(
            name="Terraform",
            passed=False,
            message="Terraform not found.",
            fix="Install from https://developer.hashicorp.com/terraform/install",
        )

    code, stdout, _ = _run(["terraform", "--version"])
    if code != 0:
        return CheckResult(
            name="Terraform",
            passed=False,
            message="Could not determine Terraform version.",
            fix="Ensure 'terraform' is on your PATH.",
        )

    # Parse version from first line: "Terraform v1.6.0"
    match = re.search(r"Terraform v(\d+)\.(\d+)\.(\d+)", stdout)
    if not match:
        return CheckResult(
            name="Terraform",
            passed=False,
            message=f"Unrecognised version output: {stdout[:80]}",
            fix="Install Terraform >= 1.5 from https://developer.hashicorp.com/terraform/install",
        )

    major, minor, patch = int(match.group(1)), int(match.group(2)), int(match.group(3))
    version_tuple = (major, minor, patch)

    if version_tuple < MIN_TERRAFORM_VERSION:
        min_str = ".".join(str(v) for v in MIN_TERRAFORM_VERSION)
        return CheckResult(
            name="Terraform",
            passed=False,
            message=f"Terraform v{major}.{minor}.{patch} is below the required v{min_str}.",
            fix=f"Upgrade Terraform to >= {min_str}: https://developer.hashicorp.com/terraform/install",
        )

    return CheckResult(
        name="Terraform",
        passed=True,
        message=f"v{major}.{minor}.{patch}",
    )


def check_docker() -> CheckResult:
    if shutil.which("docker") is None:
        return CheckResult(
            name="Docker",
            passed=False,
            message="Docker not found.",
            fix="Install Docker Desktop from https://www.docker.com/products/docker-desktop/",
        )

    code, _, stderr = _run(["docker", "info"], timeout=15)
    if code != 0:
        return CheckResult(
            name="Docker",
            passed=False,
            message="Docker daemon is not running.",
            fix="Start Docker Desktop and wait for it to fully initialise before retrying.",
        )

    return CheckResult(name="Docker", passed=True, message="daemon running")


def run_all_checks() -> list[CheckResult]:
    checks = [
        check_aws_cli,
        check_aws_credentials,
        check_terraform,
        check_docker,
    ]
    results: list[CheckResult] = []
    for fn in checks:
        console.print(f"  Checking [bold]{fn.__name__.replace('check_', '').replace('_', ' ')}[/bold]...", end=" ")
        result = fn()
        results.append(result)
        if result.passed:
            console.print(f"[green]✓[/green] {result.message}")
        else:
            console.print(f"[red]✗[/red] {result.message}")
    return results


def assert_all_pass(results: list[CheckResult]) -> None:
    """Print fix instructions for any failed checks and raise SystemExit."""
    failures = [r for r in results if not r.passed]
    if not failures:
        return

    console.print()
    for f in failures:
        console.print(f"[red bold]✗ {f.name}[/red bold]")
        if f.fix:
            for line in f.fix.splitlines():
                console.print(f"  {line}")
        console.print()

    console.print(
        f"[red]Fix the {len(failures)} issue(s) above and run [bold]stacklift init[/bold] again.[/red]"
    )
    raise SystemExit(1)
