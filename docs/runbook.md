# TaskFlow Operational Runbook

## 1. Deployment procedure

Deploys go through the GitLab pipeline (`.gitlab-ci.yml`) — not manual commands from a laptop.

1. Push to the default branch.
2. **lint** — checks Terraform formatting, Ansible syntax, and TypeScript types.
3. **security** — scans for leaked secrets (`gitleaks`) and insecure Terraform (`tfsec`).
4. **test** — runs the Jest test suite. Fails if coverage drops below 70%.
5. **build** — builds the Docker image, tags it with the commit SHA, scans it with `trivy`, pushes to ECR.
6. **plan** — runs `terraform plan` and saves it as an artifact.
7. **apply** — a manual approval step. Someone has to click "run." Applies the plan.
8. **configure** — runs Ansible against the EC2 instances, using AWS's dynamic inventory (no manual IP lists).
9. **deploy** — forces ECS to roll out the new image.
10. **smoke-test** — checks `/health` through the ALB. Fails the pipeline if it's not a 200.

### Rolling back a bad release

- **App is broken, infra is fine:** point the ECS service at the previous task definition revision and force a new deployment:
  ```bash
  aws ecs update-service \
    --cluster taskflow-prod-cluster \
    --service taskflow-prod-service \
    --task-definition <previous-revision> \
    --force-new-deployment
  ```
  ECS keeps old revisions around, so this is usually just picking the last known-good one.

- **Infra change broke something:** revert the commit in Terraform and re-run the pipeline through the manual `apply` step. Don't hand-edit things in the AWS console. Terraform will fight you on the next apply.

## 2. Scaling procedure

### How automated vertical scaling works

- CloudWatch alarms watch CPU and memory usage on the ECS service (high at 75%, low at 20%).
- An alarm firing sends a message through SNS to a Lambda function.
- The Lambda looks at the current task's CPU/memory, moves it one step up or down on a fixed scale  `256/512 → 512/1024 → 1024/2048 → 2048/4096`  and deploys the new task definition.

This only changes how big each task is (vertical scaling). It does not add more task copies  there's no auto-scaling for task *count* in this setup.

### Manual intervention

- **Scaling flaps up and down repeatedly:** the workload is probably sitting right on the alarm threshold. Widen the gap between the high and low thresholds.
- **Lambda errors out:** check its CloudWatch Logs (`/aws/lambda/taskflow-prod-vertical-scaler`). Usually means someone hand-edited the task definition and the current size doesn't match a known step.
- **Need a specific size right now:** register a task definition manually with the size you want and force a deployment, same command as the rollback above. Disable the relevant alarm first if you don't want the Lambda to resize it again shortly after.
- **Want scaling off entirely:** disable the SNS subscription or the CloudWatch alarms. The service keeps running fine, it just stops auto-resizing.

## 3. Incident scenarios

### A — ECS tasks stuck in `PENDING`

**Check in this order:**
1. **Capacity** : is there room on the EC2 instances for another task? Check the ASG's instance count and available CPU/memory.
2. **New instance not configured yet** : a brand-new EC2 instance has no Docker or ECS agent until Ansible has run on it. Re-run the `configure` stage if needed.
3. **Can't pull the image** : check if the image tag exists in ECR, and that the ECS execution role still has its permissions.

### B — ALB returning 502s

**Check in this order:**
1. **Target health** : check the target group in the AWS console. Unhealthy targets mean the ALB has nothing to forward to.
2. **App vs. database problem** : `/health` itself checks the database. If `/health` returns 503 (not a connection failure), the app is up but the database isn't. That tells you where to look next.
3. **Security group rules**  confirm the EC2 security group still allows traffic in from the ALB's security group.

### C — Database connection pool exhaustion

**Symptoms:** queries timing out, `/health` returning 503 under load.

**Why it happens:** each app instance can open up to 10 database connections. With 2 tasks running, that's up to 20 connections against a small RDS instance  a traffic spike or a slow query can use them all up.

**Fix:**
- Short term: restart the ECS service to clear stuck connections.
- Longer term: lower the per-task connection limit, add a database index if one query is the problem, or move to a bigger RDS instance if traffic has genuinely outgrown it.

## 4. Backup and restore (RDS)

- **Automated backups:** RDS keeps 1 day of automated snapshots. This is a minimal setting — worth raising for anything beyond an exercise.
- **Manual snapshot before a risky change:**
  ```bash
  aws rds create-db-snapshot \
    --db-instance-identifier taskflow-prod-postgres \
    --db-snapshot-identifier taskflow-manual-<date>
  ```
- **Restoring:** snapshots restore to a *new* instance, not in place:
  ```bash
  aws rds restore-db-instance-from-db-snapshot \
    --db-instance-identifier taskflow-prod-postgres-restored \
    --db-snapshot-identifier <snapshot-id>
  ```
  Then update the database secret in Secrets Manager with the new instance's address and redeploy.
