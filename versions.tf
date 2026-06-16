# This file documents the minimum Terraform and provider versions required
# by all Stacklift modules. It is not a runnable Terraform configuration —
# individual modules each have their own versions.tf.
#
# Use from the Terraform Registry:
#
#   module "ecs_service" {
#     source  = "emanthen/stacklift/aws//modules/ecs-service"
#     version = "~> 0.1"
#     ...
#   }
#
# Minimum versions:
#   terraform    >= 1.5
#   hashicorp/aws ~> 5.0
#   hashicorp/random ~> 3.5  (rds module only)
#   hashicorp/null ~> 3.0    (django-celery-postgres example only)
