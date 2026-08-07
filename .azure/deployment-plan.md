# Azure Deployment Plan

## Status

Validated

## Scope

Modernize the existing Azure infrastructure to use managed identities and RBAC, and verify that no credentials are exposed in tracked project files.

## Azure Context

- Tenant: `1a828a01-604c-42e6-86dd-a5fcc38a6969`
- Subscription: `MCAP922076-miyakesan`
- Subscription ID: `401f453f-7b92-4e20-9c55-265205a1b26f`
- Location: `eastus2` (existing project default)
- Resource group: `rg-voiceagent-analytics-<environment>`
- Safety gate: deployment scripts must verify both tenant and subscription before any write operation.

## Current Architecture

- Azure Event Hubs namespace, event hub, and two consumer groups.
- Microsoft Fabric Eventstream, Eventhouse, and Power BI are currently configured manually.
- Local/SAS authentication has already been changed to disabled in uncommitted user work.
- Current RBAC parameters accept external principal IDs, but default to empty and silently omit assignments.
- No Azure-hosted producer resource is defined in the repository; only the telemetry contract and sample clients exist.
- No Fabric workspace or Fabric capacity identifier is defined in the repository or visible in the queried Azure context.

## Proposed Changes

### Recommended: complete Azure layer plus Fabric workspace identity integration

1. Preserve the existing keyless changes and remove the empty-principal deployment gap.
2. Create a user-assigned managed identity for the telemetry producer in Bicep and Terraform.
3. Grant that identity `Azure Event Hubs Data Sender` on the telemetry event hub.
4. Require a Fabric workspace identity principal ID for non-development deployments and grant it `Azure Event Hubs Data Receiver` on the telemetry event hub.
5. Keep the optional administrative principal explicit; do not create broad owner access by default.
6. Keep `disableLocalAuth: true` / `local_authentication_enabled = false` and remove all authorization rules and connection-string outputs.
7. Create Log Analytics and Event Hubs diagnostic settings without shared keys.
8. Output only non-secret identifiers: namespace FQDN, resource IDs, managed identity client ID/principal ID, consumer groups, and workspace identity setup guidance.
9. Harden deployment scripts to require and verify tenant/subscription, pass identity parameters, avoid printing tokens, and fail when required identities are missing.
10. Keep Terraform behavior equivalent to Bicep, while using Bicep as the validated deployment path to avoid duplicate ownership of the same resources.
11. Update stale documentation that still instructs users to retrieve connection strings or use SAS.

### Alternative: provision Fabric items end to end

Also create/configure Fabric workspace identity, Eventstream, Eventhouse, and connections through Fabric APIs or a Fabric Terraform provider. This requires the target Fabric capacity ID, workspace ID/name, tenant settings that permit service principals, and Fabric API permissions. Those inputs are not currently available, so this option cannot be safely implemented or validated yet.

### Rejected

- SAS/connection strings stored in Key Vault: still secret-based and unnecessary for Event Hubs data access.
- Empty optional identity IDs: produces a successful deployment with a nonfunctional data path.
- `Azure Event Hubs Data Owner` for producer or consumer: broader than required.

## Security Validation

- Scan tracked files for secrets, credentials, access keys, SAS tokens, and connection strings.
- Validate managed identity resources and least-privilege RBAC assignments.
- Scan Git history where tooling is available to detect previously committed credentials.
- Validate Bicep compilation and lint diagnostics.
- Validate Terraform formatting, initialization, and configuration.
- Run an Azure what-if against the confirmed tenant/subscription after implementation.
- Do not deploy resources until validation succeeds and deployment is explicitly requested/approved.

## Validation Criteria

- Local authentication is disabled on the Event Hubs namespace.
- No authorization-rule resources or secret outputs exist.
- Producer identity always receives only `Azure Event Hubs Data Sender`.
- Fabric workspace identity receives only `Azure Event Hubs Data Receiver`.
- Production fails validation when the Fabric workspace identity is absent.
- Deployment scripts stop when tenant/subscription do not match the plan.
- Secret scans contain no material credentials; documentation-only matches are reviewed manually.

## All Validation Checks Pass

- [x] Bicep core validation: CLI, authentication, build, Azure validation, and what-if.
	- [x] Azure CLI installed and authenticated in the approved tenant/subscription.
	- [x] Bicep build succeeds for the subscription entrypoint and resource-group module.
	- [x] Azure deployment validation succeeds at subscription scope.
	- [x] Azure what-if succeeds with 9 creates, 0 modifies, and 0 deletes.
- [x] Bicep linting succeeds.
- [x] Applicable Azure Policies are reviewed for the target subscription.
- [x] Terraform preflight succeeds for the parity configuration.
	- [x] Terraform init succeeds without a backend.
	- [x] Terraform formatting check succeeds.
	- [x] Terraform validate succeeds.
	- [x] Terraform plan succeeds with 10 adds, 0 changes, and 0 destroys.
	- [x] Terraform state check is not applicable because Bicep is the deployment path and no Terraform backend/state is configured.
	- [x] No unresolved Go-style template variables or tfvars JSON are present.
- [x] Secret scan succeeds for tracked files and Git history.

## Deployment

The request is treated as implementation and validation, not an implicit production deployment. After plan approval, the project will be changed and validated. Actual Azure writes will require a separate explicit confirmation after the what-if result is available.

## Implementation Evidence

- Bicep resource-group module compiles successfully.
- Subscription-scoped Bicep entrypoint compiles successfully.
- Terraform configuration is formatted and valid with locked provider versions.
- PowerShell deployment scripts parse successfully.
- Azure what-if succeeded in tenant `1a828a01-604c-42e6-86dd-a5fcc38a6969`, subscription `401f453f-7b92-4e20-9c55-265205a1b26f`.
- What-if result: 9 creates, 0 modifies, 0 deletes.
- Tracked-file secret scan found no material credentials.
- Git history scan found one five-character SharedAccessKey placeholder and no material credential.

## Remaining External Input

- Enable the target Fabric workspace identity and provide its Object ID before configuring Eventstream or deploying production. This identity is managed by Fabric and cannot be created by the Azure-only IaC without the target Fabric workspace/capacity context.

## Role Assignment Verification

- Status: Verified.
- Producer UAMI: `Azure Event Hubs Data Sender`, scoped to the telemetry Event Hub.
- Fabric workspace identity: `Azure Event Hubs Data Receiver`, scoped to the telemetry Event Hub, created only when its Object ID is supplied.
- Optional admin principal: `Azure Event Hubs Data Owner`, scoped to the Event Hubs namespace, omitted by default.
- Managed identity principal types: fixed to `ServicePrincipal`; only the optional admin type is configurable.
- Broad management-plane roles at resource-group or subscription scope: none.
- Local developer data-plane access: not granted by IaC; use the developer's Entra identity only when explicit local event publishing is required.

## Section 7: Validation Proof

| Check | Command | Result |
|---|---|---|
| Bicep core | `validate-deployment.ps1 -Scope sub -Location eastus2 -Template ./infra/bicep/main.subscription.bicep -Parameters ./infra/bicep/main.parameters.dev.json -Subscription 401f453f-7b92-4e20-9c55-265205a1b26f` | PASS: CLI, auth, build, ARM validate, what-if; 10 creates, 0 modifies, 0 deletes |
| Bicep lint | `az bicep lint --file infra/bicep/main.subscription.bicep` and `az bicep lint --file infra/bicep/main.bicep` | PASS: no diagnostics |
| Terraform format | `terraform -chdir=infra/terraform fmt -check` | PASS |
| Terraform syntax | `terraform -chdir=infra/terraform validate` | PASS |
| Terraform preview | `terraform -chdir=infra/terraform plan -input=false -out=tfplan` | PASS: 10 adds, 0 changes, 0 destroys; no warnings |
| Terraform state | `terraform -chdir=infra/terraform state list` | Not applicable: no Terraform backend/state; Bicep is canonical |
| PowerShell | PowerShell AST parser for `infra/bicep/deploy.ps1` and `infra/deploy-planb.ps1` | PASS |
| Azure Policy | `az policy assignment list` and `az policy state summarize` | PASS: 4 Defender/ASC assignments; no noncompliant policy/resource summary |
| Tracked secrets | `git grep` for keys, passwords, client secrets, and private-key headers | PASS: no material credential patterns |
| Secret history | `git log -G` plus redacted candidate classification | PASS: one five-character `SharedAccessKey` placeholder; no material credential |
| Editor diagnostics | VS Code diagnostics for modified infrastructure files | PASS: no errors |

The official Terraform PowerShell runner was also attempted. Its `Args` parameter collided with PowerShell's automatic `$args` variable and invoked Terraform without subcommands. The equivalent documented command sequence above was run directly and passed.
