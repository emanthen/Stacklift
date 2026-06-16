"""stacklift CLI entry point."""

from __future__ import annotations

from pathlib import Path
from typing import Annotated

import typer
from rich.console import Console

from . import __version__
from . import prompts as prompt_module
from . import scaffold as scaffold_module
from . import validators

app = typer.Typer(
    name="stacklift",
    help="Scaffold production AWS infrastructure for Django and FastAPI.",
    add_completion=False,
    rich_markup_mode="rich",
)

console = Console()


def _version_callback(value: bool) -> None:
    if value:
        console.print(f"stacklift {__version__}")
        raise typer.Exit()


@app.callback()
def main(
    version: Annotated[
        bool,
        typer.Option("--version", "-v", callback=_version_callback, is_eager=True, help="Show version and exit."),
    ] = False,
) -> None:
    pass


@app.command()
def init(
    output: Annotated[
        Path,
        typer.Option("--output", "-o", help="Directory to scaffold files into.", show_default=True),
    ] = Path("."),
    overwrite: Annotated[
        bool,
        typer.Option("--overwrite", help="Overwrite existing files."),
    ] = False,
    skip_checks: Annotated[
        bool,
        typer.Option("--skip-checks", help="Skip pre-flight environment checks (not recommended)."),
    ] = False,
) -> None:
    """Scaffold production AWS infrastructure for Django or FastAPI.

    Runs pre-flight checks, collects project configuration via interactive
    prompts, then generates Terraform files and a GitHub Actions deploy
    workflow into the current directory (or --output).
    """
    console.print(f"\n[bold]stacklift[/bold] [dim]v{__version__}[/dim]")
    console.print("[dim]Production AWS for Django & FastAPI — https://github.com/emanthen/Stacklift[/dim]\n")

    # ── Pre-flight checks ─────────────────────────────────────────────────────
    if not skip_checks:
        console.print("[bold]Pre-flight checks[/bold]")
        results = validators.run_all_checks()
        validators.assert_all_pass(results)
        console.print()

    # ── Interactive prompts ───────────────────────────────────────────────────
    config = prompt_module.collect()

    # ── Scaffold files ────────────────────────────────────────────────────────
    output_dir = output.resolve()
    console.print(f"\n[bold]Scaffolding into[/bold] {output_dir}\n")

    scaffold_module.scaffold(config, output_dir, overwrite=overwrite)
    scaffold_module.print_next_steps(config, output_dir)
