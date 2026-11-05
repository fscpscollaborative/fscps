# **Contribute**
If you want to contribute, please, create an issue or  PR on the main project https://github.com/fscpscollaborative/fscps

## Probe FinOps NuGet access without LCS

[Test-FinOpsNuGetAccess.ps1](Helpers/Test-FinOpsNuGetAccess.ps1) checks the Developer
Tools Service used by the Power Platform Tools Visual Studio extension. It lists
releases, selects the latest application build (or an explicit `-AppBuild`), obtains
links for all five build packages, and checks each blob with HEAD. It does not
download packages, upload anything, or change the existing update workflow.
Automatic selection is a connectivity check, not a recommendation to upgrade.

Run with PowerShell 7 and an Azure CLI session in the environment's tenant:

```powershell
az login --tenant <tenant-id> --allow-no-subscriptions
.\Actions\Helpers\Test-FinOpsNuGetAccess.ps1 -DataverseUrl https://contoso.crm.dynamics.com/
```

The script obtains a token for the Dataverse organization, not for LCS or the
Developer Tools Service hostname. Alternatively, pass `-AccessToken` as a
`SecureString` obtained by your chosen authentication method. Never paste tokens,
passwords, SAS links, or client secrets into chat or workflow logs.

An application-token probe can use an existing service-principal Azure CLI
session. Do not replace an interactive profile or create credentials without
approval. Application-user access in Dataverse must already be configured.
Support for application tokens by this particular service is not yet verified;
successful user-token access does not prove unattended CI access.

These are internal API contracts, not a documented compatibility guarantee.
Only public-cloud Dataverse and Azure Blob URLs are currently accepted. Errors
report HTTP status and correlation ID without response bodies or SAS URLs.
A successful probe verifies link issuance and blob accessibility, not NuGet
archive integrity or completeness of the legacy SDP/version-update workflow.

Run the isolated tests with Pester 5:

```powershell
Invoke-Pester -Path .\Actions\Helpers\Test-FinOpsNuGetAccess.Tests.ps1
```

## Synchronize NuGets from Dataverse in GitHub Actions

[Update NuGets (Dataverse)](../.github/workflows/update_nuget_dataverse.yml) is a
separate, opt-in replacement for the NuGet part of the LCS workflow. The legacy
workflow remains unchanged because Software Deployable Packages and LCS asset
IDs are not available from this API. Do not run both writers concurrently; disable
the legacy schedule after migrating, or run its SDP updates separately.

The new workflow discovers every advertised release and, by default, synchronizes
the newest available application build of each release. `all_builds` explicitly
backfills every build currently returned by the service; this can transfer hundreds
of GB and may require multiple runs. Daily latest-only synchronization does not
archive builds that appear and disappear between runs.

Each package is downloaded to a unique temporary directory, checked against its
root `.nuspec` ID/version and Content-Length, hashed with SHA-256, and uploaded to
the existing flat layout `<PackageId>.<NuGetVersion>.nupkg`. Platform packages use
the platform version; application packages use the application version. Packages
are removed locally after each upload. The publisher sets SHA-256/version blob
metadata, verifies the published size and metadata, and skips matching packages
on subsequent runs. Legacy blobs without validation metadata are downloaded and
republished once. The container must already exist.

Only after all selected packages are published does the script atomically update
[versions.default.json](Helpers/versions.default.json). It adds new release records,
advances `AppVersionLatest` and `PlatformVersionLatest` without downgrading, and
sets `PlatformUpdate`. Existing GA versions, LCS IDs, Commerce branch and custom
fields are preserved. New records have empty GA and LCS fields: the API does not
identify GA or provide SDP IDs. No partially updated JSON is committed on failure;
successful blob uploads remain available and can be reused on rerun.

### One-time authentication and repository configuration

1. Register an Entra application and add its application user to the target
   Dataverse organization with appropriate access. **This service's application
   token support is still unverified**; first run `list_only` using that identity.
2. Configure a federated identity credential with issuer
   `https://token.actions.githubusercontent.com`, audience
   `api://AzureADTokenExchange`, and subject
   `repo:<owner>/<repository>:ref:refs/heads/<branch>`. The subject must match the
   repository and branch actually running the workflow (including its default
   branch for schedules). No client secret or user refresh token is needed.
3. Configure these GitHub repository variables:

   | Variable | Value |
   | --- | --- |
   | `FINOPS_DATAVERSE_URL` | Organization root URL, e.g. `https://orgf60be27e.crm4.dynamics.com/` |
   | `FINOPS_AZURE_TENANT_ID` | Dataverse tenant ID |
   | `FINOPS_AZURE_CLIENT_ID` | Application/client ID |
   | `FINOPS_NUGET_STORAGE_ACCOUNT` | Optional; defaults to `ciellosarchive` |
   | `FINOPS_NUGET_STORAGE_CONTAINER` | Optional; defaults to `nuget` |
   | `FINOPS_NUGET_SYNC_ENABLED` | Set to `true` only after a successful manual synchronization; enables the daily 22:00 UTC run |
   | `FINOPS_BUILD_PREFIX_OVERRIDES` | Optional JSON object; defaults to `{"10.0.45":"10.0.2345"}` |

   The prefix override is explicit because the service advertises `10.0.2545` for
   10.0.45, whose build list is empty; `10.0.2345` was verified against the service.
   Set the variable to `{}` when Microsoft fixes the catalog. Unknown catalog or
   package inconsistencies fail instead of guessing a version.

4. Storage authentication uses the existing `NUGET_STORAGE_SAS_TOKEN` secret when
   present (read, create/write permissions are required). Otherwise grant the
   federated principal **Storage Blob Data Contributor** on the target container;
   the script uses Azure CLI `--auth-mode login`. Blob traffic uses the storage
   identity/SAS, never the Dataverse token.
5. Dispatch with `list_only: true` first (the default). Then dispatch with
   `list_only: false` to publish and commit JSON to the selected branch. The
   workflow stages only the versions file. Branch protection must permit the bot's
   push, otherwise publication succeeds but the commit push fails explicitly.
   Push conflicts are not force-resolved: rerun on the latest branch revision.

The schedule is disabled until explicitly enabled. `list_only` does not access
storage or write files. The GitHub job summary shows the selected releases/builds
or publication results, without tokens or download URLs. The existing access
probe can independently verify SAS issuance and blob HEAD access.

### Administrator handoff: where to obtain Client ID and configure OIDC

#### Current deployment and temporary client-secret authentication

Application-token discovery and SAS issuance were successfully verified on
November 5, 2026 against `https://operations-on-qa.crm.dynamics.com/`, tenant
`46e85934-1fab-4533-a4ad-de92ce1fd81a`, application `XPP-MCP` (Client ID
`ddd14b4b-a5fb-4491-84ea-d5bdabcb5d71`). Its application user currently has
System Administrator for validation; reduce that role after verifying the
required permissions. The Ciellos details below describe the earlier setup.

Creating federation was denied by Entra. Until an administrator configures OIDC,
the workflow supports an explicitly selected `FINOPS_AZURE_AUTH_MODE=client-secret`
repository variable and a `FINOPS_AZURE_CREDENTIALS` repository secret containing
the Azure login JSON (`clientId`, `clientSecret`, `tenantId`, and optionally
`subscriptionId`). Upload it from a protected local file, never commit it or
print its contents. This is a temporary alternative, not a silent fallback after
OIDC failure. Rotate the secret according to organizational policy.

After federation is configured, set `FINOPS_AZURE_AUTH_MODE=oidc`, verify a full
run, then remove `FINOPS_AZURE_CREDENTIALS` if no longer needed. OIDC is the
default when the mode variable is absent. Scheduled synchronization remains
independently gated by `FINOPS_NUGET_SYNC_ENABLED`.

Client ID is the **Application (client) ID** of an Entra app registration. It is
not a user account, an application Object ID, an Enterprise Application Object
ID, or a secret. Do not assume that the existing `LCS_CLIENT_ID` has the required
Dataverse access. Prefer a dedicated single-tenant application for this job.

The target verified during investigation:

| Setting | Value |
| --- | --- |
| Dataverse URL | `https://orgf60be27e.crm4.dynamics.com/` |
| Directory (tenant) ID, Ciellos | `79bb53e9-f531-46a9-8a2d-49084810b651` |
| Target GitHub repository | `fscpscollaborative/fscps` |
| Default branch for scheduled runs | `develop` (verified November 3, 2026) |
| Storage account / existing container | `ciellosarchive` / `nuget` |

The local checkout's origin is `onikolaiev/fscps`, not the target repository.
Federation must trust the repository actually executing the workflow. A credential
for the collaborative repository does not authorize a run in the personal fork.
Recheck the default branch before configuration.

Ask the Entra/Power Platform administrator to perform the following:

1. In [Microsoft Entra admin center](https://entra.microsoft.com/), select the
   Ciellos tenant, then **App registrations > New registration**. For example,
   name it `fscps-finops-nuget-sync`, select accounts in this directory only, and
   leave Redirect URI empty. An existing dedicated application can be reused
   after reviewing its owners and permissions.
2. On the application's **Overview** page, copy **Application (client) ID** and
   **Directory (tenant) ID**. These identifiers are not secrets and can be shared
   with the repository maintainer. No client secret is needed for OIDC.
3. In [Power Platform admin center](https://admin.powerplatform.microsoft.com/),
   go to **Manage > Environments**, select the environment matching the URL above,
   then **Settings > Users + permissions > Application users > New app user**.
   Choose **Add an app**, select the same registration by its Client ID, choose
   the appropriate business unit, and assign an administrator-approved security
   role before creating the user.

   The minimum role required by this internal Developer Tools endpoint is not
   established. Do not claim that ordinary API permissions or an Azure RBAC role
   grant Dataverse access. If necessary, an administrator can approve temporary
   **System Administrator** access for the initial probe, then narrow the role
   and repeat the probe before enabling production. Do not grant tenant-wide
   Graph permissions or create a user password to solve this.
4. In the Entra app registration, open **Certificates & secrets > Federated
   credentials > Add credential** and choose **GitHub Actions deploying Azure
   resources**. Enter organization `fscpscollaborative`, repository `fscps`,
   entity type **Branch**, branch `develop`, and a name such as
   `github-fscps-develop`. Verify the resulting values exactly:

   ```text
   Issuer:   https://token.actions.githubusercontent.com
   Subject:  repo:fscpscollaborative/fscps:ref:refs/heads/develop
   Audience: api://AzureADTokenExchange
   ```

   This trusts all eligible workflows on that branch, not only one YAML file:
   protect branch write access accordingly. Runs on another branch need a
   separately approved credential. The current workflow does not use a GitHub
   Environment; if one is introduced, its OIDC subject changes and the credential
   must be updated.
5. For secretless storage access, have the Azure administrator assign **Storage
   Blob Data Contributor** to the same service principal at the scope of the
   existing `nuget` container, not the entire subscription. The Azure principal
   must exist in the storage subscription's tenant; cross-tenant storage access
   is a separate configuration, not implied by Dataverse access.

   If retaining the existing `NUGET_STORAGE_SAS_TOKEN`, skip this RBAC change.
   The secret must remain in GitHub and must permit reading and creating/writing
   blobs, including setting metadata. The workflow prefers this SAS when present;
   switch away from it deliberately only after validating RBAC.

Ask the GitHub repository administrator/maintainer to:

1. Make the new workflow and helper scripts available on `develop` in
   `fscpscollaborative/fscps`. They are not deployed merely by editing this checkout.
2. Open **Settings > Secrets and variables > Actions > Variables** and set:

   ```text
   FINOPS_DATAVERSE_URL   = https://orgf60be27e.crm4.dynamics.com/
   FINOPS_AZURE_TENANT_ID = 79bb53e9-f531-46a9-8a2d-49084810b651
   FINOPS_AZURE_CLIENT_ID = <Application (client) ID supplied by the Entra admin>
   ```

   Leave `FINOPS_NUGET_SYNC_ENABLED` unset or `false`. Client ID and tenant ID
   belong in variables, not in client-secret/password fields.
3. Run **Actions > Update NuGets (Dataverse) > Run workflow** on `develop`, with
   `list_only` checked. This validates GitHub token exchange and the application's
   access to release/build discovery; it does not validate storage or SAS issuance.
4. If discovery succeeds, run with `list_only` unchecked and `all_builds` unchecked.
   Verify package publication and the versions-file commit before enabling the
   schedule. Application-token authorization for SAS issuance may still fail
   even when catalog discovery works. Capture HTTP status/correlation ID for the
   administrator; do not export bearer tokens or SAS links.
5. Enable `FINOPS_NUGET_SYNC_ENABLED=true` only after the full run succeeds and
   the legacy JSON writer is no longer scheduled concurrently.

The administrator should return the Client ID, tenant confirmation, application
user/role confirmation, federated credential subject, and selected storage
authentication mode. **Do not request or share passwords, client secrets, user
refresh tokens, access tokens, or SAS values.** If application authentication is
rejected by the Developer Tools service, stop and investigate with the correlation
ID; OIDC configuration alone cannot make a user-only endpoint support applications.

Official configuration references:

- [Manage Dataverse application users](https://learn.microsoft.com/en-us/power-platform/admin/manage-application-users)
- [Create an Entra federated identity trust](https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation-create-trust)

For local discovery with an existing Azure CLI session:

```powershell
.\Actions\Helpers\Sync-FinOpsNuGets.ps1 `
    -DataverseUrl https://orgf60be27e.crm4.dynamics.com/ `
    -BuildPrefixOverrides @{ '10.0.45' = '10.0.2345' } -ListOnly
```

Run all isolated tests:

```powershell
Invoke-Pester -Path .\Actions\Helpers\Test-FinOpsNuGetAccess.Tests.ps1, .\Actions\Helpers\Sync-FinOpsNuGets.Tests.ps1
```
