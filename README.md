# TaskFlow — Platform Engineering Assignment

**TaskFlow** is an internal task management REST API (Node.js/TypeScript + Express + PostgreSQL) deployed on AWS using Terraform, Ansible, Docker, and GitLab CI/CD.

---

## 1. System Overview

- **`app/`**: Express & TypeScript REST API providing CRUD on `/tasks`, a `/health` endpoint, input validation with Zod, Winston JSON logging, and Jest tests (70% coverage threshold).
- **`terraform/`**: Modular AWS IaC provisioning a multi-AZ VPC, ALB, ECS cluster on an EC2 Auto Scaling Group, RDS PostgreSQL, IAM roles, and a Lambda-driven vertical scaling mechanism.
- **`ansible/`**: Configures EC2 hosts dynamically (`aws_ec2` plugin) — installs Docker, configures the ECS/CloudWatch agents, and applies OS security baseline hardening.
- **`.gitlab-ci.yml`**: 9-stage pipeline: `lint` → `security` → `test` → `build` → `plan` → `apply` (manual gate) → `configure` → `deploy` → `smoke-test`.

---

## 2. DevOps vs. Platform Engineering

- **DevOps** breaks down silos between software development and IT operations through shared ownership, automation, CI/CD, and fast feedback loops.
- **Platform Engineering** productizes DevOps practices. Instead of individual application teams building custom cloud infrastructure from scratch, a platform team builds an **Internal Developer Platform (IDP)** with standardized templates, reusable modules, and "golden paths" to reduce cognitive load.
- **In this project**: Building the reusable Terraform modules and Ansible roles represents **platform engineering**. Assembling the application, CI/CD pipeline, and on-call operational runbook represents **DevOps** in action.

---

## 3. Why DevSecOps Matters

DevSecOps shifts security left by embedding automated scanning into the pipeline rather than relying on manual audits right before release:
- **Gitleaks**: Catches hardcoded API keys and credentials before code merges.
- **tfsec / Checkov**: Validates Terraform code against AWS security baselines prior to `apply`.
- **Trivy**: Scans Docker image layers for OS and dependency CVEs.
- **Least-Privilege IAM**: Restricts permissions across EC2 instance, ECS task execution, and task roles.
- **Zero Committed Secrets**: RDS credentials reside in AWS Secrets Manager and are injected at container runtime.

---

## 4. Local Setup & Execution

### Prerequisites
- Node.js 20+, Docker, PostgreSQL

```bash
cd app
npm install
cp .env.example .env   # Configure PORT, DATABASE_URL, LOG_LEVEL
npm run dev             # Start dev server via ts-node
npm test                # Run unit tests (70% coverage gate)

### Run with Docker

```bash
docker build -t taskflow-app .
docker run -p 3000:3000 --env-file .env taskflow-app
```

---

## 5. Clean AWS Account Deployment

1. **Bootstrap Remote State**: Manually create an S3 bucket (`taskflow-tfstate-<account-id>`) and DynamoDB lock table (`taskflow-tf-locks`) as defined in `terraform/envs/prod/backend.tf`.
2. **GitLab CI/CD Setup**: Add masked AWS credentials (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`) to repository CI/CD variables.
3. **Pipeline Execution**:
   - Push to `main` to trigger automated `lint`, `security`, `test`, `build`, and `plan` stages.
   - Manually trigger the `apply` stage to provision AWS resources.
   - The pipeline automatically runs `configure` (Ansible via SSM), `deploy` (force new ECS deployment), and `smoke-test` (curls `/health` via ALB DNS).