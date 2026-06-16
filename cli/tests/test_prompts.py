"""Tests for prompts.py"""

import pytest

from stacklift.prompts import ProjectConfig


class TestProjectConfig:
    def test_defaults(self):
        config = ProjectConfig()
        assert config.environment == "prod"
        assert config.container_port == 8000
        assert config.framework == "django"

    def test_django_health_check_path(self):
        config = ProjectConfig(framework="django")
        assert config.health_check_path == "/api/health/"

    def test_fastapi_health_check_path(self):
        config = ProjectConfig(framework="fastapi")
        assert config.health_check_path == "/health"

    def test_health_check_path_updates_on_framework_change(self):
        config = ProjectConfig(framework="django")
        assert config.health_check_path == "/api/health/"
        # Simulate user changing framework after construction
        config.framework = "fastapi"
        config.health_check_path = "/health"
        assert config.health_check_path == "/health"

    def test_celery_defaults_false(self):
        config = ProjectConfig()
        assert config.enable_celery is False

    def test_staging_defaults_false(self):
        config = ProjectConfig()
        assert config.enable_staging is False

    def test_full_config(self):
        config = ProjectConfig(
            project_name="my-api",
            aws_region="eu-west-1",
            domain_name="api.myapi.com",
            framework="fastapi",
            db_instance_class="db.t3.small",
            cpu=512,
            memory=1024,
            enable_celery=False,
            enable_staging=True,
            github_org="myorg",
            github_repo="my-api",
        )
        assert config.project_name == "my-api"
        assert config.aws_region == "eu-west-1"
        assert config.cpu == 512
        assert config.memory == 1024
        assert config.enable_staging is True
        assert config.health_check_path == "/health"

    def test_project_name_with_hyphens(self):
        config = ProjectConfig(project_name="my-cool-saas")
        assert config.project_name == "my-cool-saas"
