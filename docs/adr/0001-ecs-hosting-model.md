# ADR 0001: Host ECS on EC2 Auto Scaling Group Instead of Fargate

## Status
Accepted

## Context
AWS ECS offers two launch types for containers: **AWS Fargate** (serverless compute managed by AWS) and **EC2** (user-managed virtual servers).

Under normal circumstances, Fargate is the simpler choice because it removes server management, OS patching, and capacity planning. However, this project specifically requires demonstrating configuration management with **Ansible** (dynamic inventory, OS hardening, Docker setup, and agent configuration). Because Fargate abstracts away the underlying host, there are no operating systems or IP endpoints for Ansible to connect to or configure.

## Decision
Deploy the ECS cluster on **EC2 instances** using an Auto Scaling Group (ASG) running ECS-optimized Amazon Linux 2023.

- **Terraform** provisions the infrastructure (VPC, ASG, Launch Template, and IAM roles)[cite: 1, 2].
- **Ansible** configures the host instances dynamically using AWS tags (`Role=ecs-host`, `Environment=prod`) over AWS Systems Manager (SSM) without exposing SSH ports[cite: 1, 2].

## Consequences

### Advantages
- **Enables Configuration Management**: Creates a clean separation between Infrastructure as Code (Terraform) and host configuration (Ansible).
- **Direct OS & Security Control**: Allows custom kernel hardening, disabling password-based SSH, and managing system update policies directly.
- **Private Access via SSM**: Host configuration runs securely over SSM without assigning public IP addresses to the instances.

### Trade-offs
- **Higher Operational Overhead**: Host maintenance, security patching, and AMI rotation must be managed manually or via pipelines.
- **Capacity Planning**: ECS tasks can get stuck in a `PENDING` state if the underlying EC2 instances run out of CPU or memory.
- **Provisioning Lag**: New instances require an Ansible configuration run before they can reliably register and run ECS workloads.
- **Broader IAM Scope**: Requires an EC2 host instance profile alongside standard ECS task and execution roles.

## Alternatives Considered
- **AWS Fargate**: Rejected because it abstracts host-level access, preventing the use of Ansible for operating system configuration and hardening.