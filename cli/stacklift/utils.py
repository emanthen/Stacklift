"""Shared utilities."""

from __future__ import annotations

import os
from pathlib import Path


def ensure_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


def project_root() -> Path:
    """Return the directory stacklift init was invoked from."""
    return Path(os.getcwd())


def safe_write(path: Path, content: str, overwrite: bool = False) -> bool:
    """Write content to path. Returns True if written, False if skipped."""
    if path.exists() and not overwrite:
        return False
    ensure_dir(path.parent)
    path.write_text(content, encoding="utf-8")
    return True


def templates_dir() -> Path:
    return Path(__file__).parent / "templates"
