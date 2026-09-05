# autoservicemanager-infra-k8s

Terraform do stack **compute/edge** (Fase 3): EKS, NLB, VPC Link, API Gateway HTTP API, JWT Authorizer, Lambda authCpf, JWKS (S3+CloudFront) e IRSA.

Consome `terraform_remote_state` do [infra-db](../infra-db/) (ADR-008). Este diretório vive no monorepo até a cisão do repo GitHub `autoservicemanager-infra-k8s`.

**Docs:** [RFC-001](../docs/architecture/rfc-001-cloud-aws.md) · [ADR-004](../docs/architecture/adr-004-api-gateway-vpc-link.md)–[009](../docs/architecture/adr-009-github-oidc-aws-iam.md) · [obs](../docs/observability/) · [runbook](../docs/runbook.md)

## Escopo

| Recurso | Detalhe |
|---------|---------|
| Remote state | Lê `db/<homolog\|prod>/terraform.tfstate` (VPC + RDS SG + secret) |
| EKS | Kubernetes **1.34**, node group `t3.medium` (desired **1** em homolog por FinOps), OIDC provider, SG nós (suporte padrão AWS; ver [calendário EKS](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html)) |
| SG MySQL | Regras **SG→SG**: nodes + Lambda → `db_sg_id` |
| NLB interno | Target group `ip` porta app (3000) + listener :80 |
| VPC Link | HTTP API → NLB |
| API Gateway | `POST /auth/cpf` → Lambda; `/clientes/*` e `/ordens-servico/*` → JWT; `/admin/*`, `/webhooks/*`, `/health` sem JWT RS256 |
| JWT | RSA 2048; secret `${project}-${env}/jwt-auth-cpf`; JWKS em CloudFront |
| Lambda | Placeholder zip gerado no plan (`archive_file` ← `placeholder/handler.js`); código real via CI `auth-lambda` (`AUTH_LAMBDA_NAME`) |
| IRSA | Roles para `autoservice/autoservice-api` e `autoservice-migrate` |
| Observabilidade | Addon `amazon-cloudwatch-observability` (Container Insights + Fluent Bit), dashboard `{name}-ops`, alarmes SNS, log groups application/performance |

## Pré-requisitos

1. Bootstrap state (mesmo do infra-db): `infra-db/scripts/bootstrap-state.sh`
2. **`infra-db` apply** no ambiente (`homolog` ou `prod`)
3. Terraform >= 1.5, Node 22 (script JWKS), AWS CLI

## Apply local

```bash
cp backend.hcl.example backend.hcl   # key = k8s/homolog/terraform.tfstate
cp terraform.tfvars.example terraform.tfvars
# tf_state_bucket = bucket real

terraform init -backend-config=backend.hcl
TF_VAR_environment=homolog TF_VAR_tf_state_bucket=autoservicemanager-tfstate-ACCOUNT \
  terraform plan
TF_VAR_environment=homolog TF_VAR_tf_state_bucket=... terraform apply
```

Só validação (sem state/AWS real no plan):

```bash
terraform init -backend=false
terraform validate
```

## Pós-apply (app)

1. Anotar `app_irsa_role_arn` / `migrate_irsa_role_arn` nos ServiceAccounts.
2. Registrar pods no `target_group_arn` (AWS Load Balancer Controller `TargetGroupBinding` ou Service anotado).
3. CI auth-lambda: secret `AUTH_LAMBDA_NAME` = output `auth_lambda_name`.
4. ConfigMap app: `JWT` não precisa da chave privada; confia em `x-cpf` do gateway.
5. Observabilidade: `kubectl apply -f k8s/xray-daemonset.yaml`; assinar SNS `ops_alerts_topic_arn` (ver [docs/observability/alerts.md](../docs/observability/alerts.md)).

## CI/CD (OIDC)

Workflow: [`.github/workflows/infra-k8s-ci-cd.yml`](../.github/workflows/infra-k8s-ci-cd.yml)

| Evento | Ação |
|--------|------|
| PR (`infra-k8s/**`) | `fmt` + `validate` — **sem AWS** |
| Push `develop` | OIDC → plan/apply; key `k8s/homolog/` |
| Push `master` | OIDC → plan/apply; key `k8s/prod/` |

Secrets: `AWS_ROLE_ARN`. Var opcional: `TF_STATE_BUCKET`.

## Destroy

```bash
TF_VAR_environment=homolog TF_VAR_tf_state_bucket=... terraform destroy
```

Ordem: **destruir este stack antes** do `infra-db`.

<!-- ci-trigger: infra-k8s apply homolog -->

## Outputs principais

`api_endpoint`, `jwt_issuer`, `eks_cluster_name`, `auth_lambda_name`, `target_group_arn`, `app_irsa_role_arn`, `ops_alerts_topic_arn`, `ops_dashboard_name`
