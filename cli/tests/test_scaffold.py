"""Tests for scaffold.py"""

import textwrap
from pathlib import Path

import pytest

from stacklift.prompts import ProjectConfig
from stacklift.scaffold import scaffold, _build_context


def make_config(**kwargs) -> ProjectConfig:
    defaults = dict(
        project_name="my-saas",
        aws_region="us-east-1",
        domain_name="api.mysaas.com",
        framework="django",
        db_instance_class="db.t3.micro",
        cpu=256,
        memory=512,
        enable_celery=False,
        enable_staging=False,
        github_org="acme",
        github_repo="my-saas",
    )
    defaults.update(kwargs)
    return ProjectConfig(**defaults)


class TestBuildContext:
    def test_includes_all_required_keys(self):
        config = make_config()
        ctx = _build_context(config)
        required = [
            "project_name", "environment", "aws_region", "domain_name",
            "framework", "db_instance_class", "cpu", "memory",
            "enable_celery", "enable_staging", "github_org", "github_repo",
            "github_branch", "container_port", "health_check_path",
            "stacklift_source", "stacklift_ref",
        ]
        for key in required:
            assert key in ctx, f"missing key: {key}"

    def test_django_health_check_path(self):
        ctx = _build_context(make_config(framework="django"))
        assert ctx["health_check_path"] == "/api/health/"

    def test_fastapi_health_check_path(self):
        ctx = _build_context(make_config(framework="fastapi"))
        assert ctx["health_check_path"] == "/health"


class TestScaffold:
    def test_creates_all_files(self, tmp_path):
        config = make_config()
        written = scaffold(config, tmp_path)

        expected = [
            tmp_path / "infra" / "main.tf",
            tmp_path / "infra" / "variables.tf",
            tmp_path / "infra" / "terraform.tfvars",
            tmp_path / "infra" / "backend.tf",
            tmp_path / ".github" / "workflows" / "deploy.yml",
        ]
        for path in expected:
            assert path.exists(), f"expected file not created: {path}"
        assert len(written) == len(expected)

    def test_main_tf_contains_project_name(self, tmp_path):
        config = make_config(project_name="acme-api")
        scaffold(config, tmp_path)
        content = (tmp_path / "infra" / "main.tf").read_text()
        assert "acme-api" in content

    def test_main_tf_includes_celery_module_when_enabled(self, tmp_path):
        config = make_config(enable_celery=True)
        scaffold(config, tmp_path)
        content = (tmp_path / "infra" / "main.tf").read_text()
        assert "ecs_celery" in content

    def test_main_tf_excludes_celery_when_disabled(self, tmp_path):
        config = make_config(enable_celery=False)
        scaffold(config, tmp_path)
        content = (tmp_path / "infra" / "main.tf").read_text()
        assert "ecs_celery" not in content

    def test_deploy_yml_includes_celery_steps_when_enabled(self, tmp_path):
        config = make_config(enable_celery=True)
        scaffold(config, tmp_path)
        content = (tmp_path / ".github" / "workflows" / "deploy.yml").read_text()
        assert "ECS_CELERY" in content

    def test_deploy_yml_excludes_celery_when_disabled(self, tmp_path):
        config = make_config(enable_celery=False)
        scaffold(config, tmp_path)
        content = (tmp_path / ".github" / "workflows" / "deploy.yml").read_text()
        assert "ECS_CELERY" not in content

    def test_tfvars_contains_user_values(self, tmp_path):
        config = make_config(
            project_name="payments",
            aws_region="eu-west-1",
            domain_name="api.payments.io",
            github_org="bigco",
            github_repo="payments",
        )
        scaffold(config, tmp_path)
        content = (tmp_path / "infra" / "terraform.tfvars").read_text()
        assert 'project_name = "payments"' in content
        assert 'aws_region   = "eu-west-1"' in content
        assert 'domain_name     = "api.payments.io"' in content
        assert 'github_org    = "bigco"' in content

    def test_skips_existing_files_by_default(self, tmp_path):
        config = make_config()
        scaffold(config, tmp_path)

        # Overwrite main.tf with sentinel
        main_tf = tmp_path / "infra" / "main.tf"
        main_tf.write_text("# SENTINEL")

        # Second scaffold without overwrite — should not touch it
        scaffold(config, tmp_path, overwrite=False)
        assert main_tf.read_text() == "# SENTINEL"

    def test_overwrites_when_flag_set(self, tmp_path):
        config = make_config()
        scaffold(config, tmp_path)

        main_tf = tmp_path / "infra" / "main.tf"
        main_tf.write_text("# SENTINEL")

        scaffold(config, tmp_path, overwrite=True)
        assert main_tf.read_text() != "# SENTINEL"

    def test_fastapi_config_uses_correct_health_path(self, tmp_path):
        config = make_config(framework="fastapi")
        scaffold(config, tmp_path)
        content = (tmp_path / "infra" / "main.tf").read_text()
        assert '"/health"' in content
        assert '"/api/health/"' not in content

    def test_deploy_yml_valid_yaml(self, tmp_path):
        import yaml
        config = make_config(enable_celery=True)
        scaffold(config, tmp_path)
        content = (tmp_path / ".github" / "workflows" / "deploy.yml").read_text()
        # Should parse without errors
        yaml.safe_load(content)
