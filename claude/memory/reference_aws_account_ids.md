---
name: aws-account-ids
description: Treeverse AWS account IDs and which environment each maps to (prod vs staging vs dev)
metadata:
  type: reference
---

Treeverse AWS accounts, keyed by the local `saml2aws`/AWS profile. The account ids live in
`~/.agents/local.env` (kept out of git); read it when you need the numbers.

- **Production** (`PROD_AWS_ACCOUNT_ID`) — profile `cloud-prod`. Kube contexts: the `prod-*` aliases (`prod-us-east-1`, `prod-eu-west-1`, `prod-ap-northeast-1`, `prod-eu-north-1`, `prod-us-west-2`) and the raw-ARN form `arn:aws:eks:*:<prod account>:cluster/lakefs-cloud`.
- **Staging** (`STAGING_AWS_ACCOUNT_ID`) — profile `cloud-staging`. Kube contexts: `staging-*` and `lakefs-cloud-staging`.
- **`cloud-dev`** = dev profile (account id not cached locally).

Treat the production account as production: it is a read-only environment; mutating actions need explicit per-action approval. This is what the `~/.claude/hooks/prod-mutation-guard.sh` PreToolUse hook enforces (the account id and `prod-*`/`cloud-prod` names are its prod signals, plus the active kube context).

**Verify anytime:** after a login, `grep x_principal_arn ~/.aws/credentials` — the account id sits between `sts::` and `:assumed-role` for each profile. Or `aws sts get-caller-identity --profile cloud-prod`.
