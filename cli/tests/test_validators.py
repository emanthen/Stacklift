"""Tests for validators.py"""

from unittest.mock import patch

import pytest

from stacklift.validators import (
    CheckResult,
    assert_all_pass,
    check_aws_cli,
    check_aws_credentials,
    check_docker,
    check_terraform,
)


class TestCheckAwsCli:
    def test_passes_when_aws_installed(self):
        with patch("stacklift.validators._run", return_value=(0, "aws-cli/2.15.0 Python/3.11.0", "")):
            result = check_aws_cli()
        assert result.passed is True
        assert result.name == "AWS CLI"

    def test_fails_when_not_installed(self):
        with patch("stacklift.validators._run", return_value=(127, "", "command not found: aws")):
            result = check_aws_cli()
        assert result.passed is False
        assert result.fix != ""

    def test_fails_when_empty_output(self):
        with patch("stacklift.validators._run", return_value=(0, "", "")):
            result = check_aws_cli()
        assert result.passed is False


class TestCheckAwsCredentials:
    def test_passes_with_valid_identity(self):
        identity_json = '{"UserId":"AIDAM","Account":"123456789012","Arn":"arn:aws:iam::123456789012:user/dev"}'
        with patch("stacklift.validators._run", return_value=(0, identity_json, "")):
            result = check_aws_credentials()
        assert result.passed is True
        assert "123456789012" in result.message

    def test_fails_with_nonzero_exit(self):
        with patch("stacklift.validators._run", return_value=(255, "", "Unable to locate credentials")):
            result = check_aws_credentials()
        assert result.passed is False
        assert result.fix != ""

    def test_passes_with_malformed_json(self):
        with patch("stacklift.validators._run", return_value=(0, "not-json", "")):
            result = check_aws_credentials()
        assert result.passed is True


class TestCheckTerraform:
    def test_passes_with_valid_version(self):
        with patch("shutil.which", return_value="/usr/local/bin/terraform"):
            with patch("stacklift.validators._run", return_value=(0, "Terraform v1.6.0\non linux_amd64", "")):
                result = check_terraform()
        assert result.passed is True
        assert "1.6.0" in result.message

    def test_fails_with_old_version(self):
        with patch("shutil.which", return_value="/usr/local/bin/terraform"):
            with patch("stacklift.validators._run", return_value=(0, "Terraform v1.4.6", "")):
                result = check_terraform()
        assert result.passed is False
        assert "1.4.6" in result.message

    def test_fails_when_not_installed(self):
        with patch("shutil.which", return_value=None):
            result = check_terraform()
        assert result.passed is False
        assert result.fix != ""

    def test_passes_with_minimum_version(self):
        with patch("shutil.which", return_value="/usr/local/bin/terraform"):
            with patch("stacklift.validators._run", return_value=(0, "Terraform v1.5.0", "")):
                result = check_terraform()
        assert result.passed is True

    def test_fails_with_unrecognised_output(self):
        with patch("shutil.which", return_value="/usr/local/bin/terraform"):
            with patch("stacklift.validators._run", return_value=(0, "OpenTofu v1.6.0", "")):
                result = check_terraform()
        assert result.passed is False


class TestCheckDocker:
    def test_passes_when_running(self):
        with patch("shutil.which", return_value="/usr/bin/docker"):
            with patch("stacklift.validators._run", return_value=(0, "Server: Docker Engine...", "")):
                result = check_docker()
        assert result.passed is True

    def test_fails_when_daemon_not_running(self):
        with patch("shutil.which", return_value="/usr/bin/docker"):
            with patch("stacklift.validators._run", return_value=(1, "", "Cannot connect to Docker daemon")):
                result = check_docker()
        assert result.passed is False
        assert "Docker Desktop" in result.fix

    def test_fails_when_not_installed(self):
        with patch("shutil.which", return_value=None):
            result = check_docker()
        assert result.passed is False


class TestAssertAllPass:
    def test_does_not_raise_when_all_pass(self):
        results = [CheckResult("A", True, "ok"), CheckResult("B", True, "ok")]
        assert_all_pass(results)  # should not raise

    def test_raises_system_exit_on_failure(self):
        results = [
            CheckResult("A", True, "ok"),
            CheckResult("B", False, "broken", fix="fix it"),
        ]
        with pytest.raises(SystemExit):
            assert_all_pass(results)
