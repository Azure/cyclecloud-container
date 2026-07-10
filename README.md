# CycleCloud Marketplace Container Image

This repository produces a generalized, marketplace-ready CycleCloud container image based on Ubuntu 24.04 or AlmaLinux 9 with support for Azure Identity (Managed Identity or Workload Identity), mounted configuration files, and persistent volumes.


## Building the Image

Run `build.sh` , this will build the container and run tests locally. If you want to skip the tests then run like this `build.sh --notest` .

## Running the Container


### Minimum Docker Example

Username and password can be created for testing. Username and password arguments should not be used in production systems. 
Using host networking (simplest, exposes all CycleCloud ports directly):

```bash
docker run \
  --name cyclecloud \
  --network host \
  -e CYCLECLOUD_PASSWORD="MySecurePassword123!" \
  -e CYCLECLOUD_USERNAME="ccadmin" \
  cyclecloud:latest
```

Using port mapping (maps to less commonly used host ports to avoid conflicts in WSL):

```bash
docker run \
  --name cyclecloud \
  -e CYCLECLOUD_USERNAME="ccadmin" \
  -p 9080:8080 \
  -p 9443:8443 \
  cyclecloud:latest
```

### Docker with Volumes

Cyclecloud relies on persistent filesystem. All production systems should mount the following volumes on persistent disk.

```bash
docker run \
  --name cyclecloud \
  -v cyclecloud-data:/opt/cycle_server/data \
  -v cyclecloud-logs:/opt/cycle_server/logs \
  -v cyclecloud-config:/opt/cycle_server/config \
  -v cyclecloud-ssh:/opt/cycle_server/.ssh \
  -v cyclecloud-work:/opt/cycle_server/work \
  -p 8080:8080 \
  -p 8443:8443 \
  cyclecloud:latest
```

### Docker with Env File

```bash
docker run -it \
  --name cyclecloud \
  --env-file ./example.env \
  -v cyclecloud-data:/opt/cycle_server/data \
  -v cyclecloud-logs:/opt/cycle_server/logs \
  -v cyclecloud-config:/opt/cycle_server/config \
  -v cyclecloud-ssh:/opt/cycle_server/.ssh \
  -v cyclecloud-work:/opt/cycle_server/work \
  -p 8080:8080 \
  -p 8443:8443 \
  cyclecloud:latest
```

### Kubernetes Example

See helm chart in ./charts

## Environment Variables

All environment variables have sensible defaults. Override them as needed:

An example env file is included at the repo root as `example.env`. Pass it at runtime with Docker's `--env-file` flag or the equivalent in your orchestrator.

| Variable | Default | Description |
|----------|---------|-------------|
| `CYCLECLOUD_USERNAME` | `""` | Initial admin username |
| `CYCLECLOUD_PASSWORD` | `""` | - Sets an initial password for initial cyclecloud user for testing |
| `CYCLECLOUD_USER_PUBKEY` | `""` | SSH public key for admin user |
| `CYCLECLOUD_STORAGE` | `""` | Azure Storage account name for CycleCloud locker |
| `CYCLECLOUD_RESOURCE_GROUP` | (from IMDS) | Resource group for cluster resources. Defaults to CycleCloud's RG if not specified |
| `CYCLECLOUD_WEBSERVER_MAX_HEAP_SIZE` | `"4096M"` | JVM maximum heap size |
| `CYCLECLOUD_WEBSERVER_PORT` | `"8080"` | HTTP port (must be >1024 for unprivileged user) |
| `CYCLECLOUD_WEBSERVER_SSL_PORT` | `"8443"` | HTTPS port (must be >1024 for unprivileged user) |
| `CYCLECLOUD_WEBSERVER_HTTPS_ENABLED` | `"true"` | Enable HTTPS. Self-signed cert generated on first start if keystore missing |
| `CYCLECLOUD_WEBSERVER_CLUSTER_PORT` | `"9443"` | Cluster communications port |
| `CYCLECLOUD_HOSTNAME` | `""` | Hostname/IP for cluster nodes to reach CycleCloud |
| `CYCLECLOUD_FORCE_DELETE_VMS` | `"true"` | Force delete VMs on cluster termination |
| `CYCLECLOUD_FORCE_DELETE_VMSS` | `"true"` | Force delete VMSS on cluster termination |
| `STORAGE_MANAGED_IDENTITY` | `""` | Managed Identity for storage account access (Locker MI) |
| `GENERATE_CS_CONFIG` | `"true"` | Generate `cycle_server.properties` from env vars (only if no mounted config exists) |
| `CONTAINER_DEBUG` | `"false"` | If `"true"`, container enters `sleep infinity` on failure for debugging |
| `ENTRA_ENABLED` | `"false"` | Enable Entra ID authentication (vars accepted but implementation deferred) |
| `ENTRA_TENANT_ID` | `""` | Entra tenant ID |
| `ENTRA_CLIENT_ID` | `""` | Entra client ID |
| `ENTRA_OBJECT_ID` | `""` | Entra object ID |
| `ENTRA_AUTH_ENDPOINT` | `""` | Entra authentication endpoint |
| `ENTRA_USERNAME` | `""` | Entra service account username |
| `ENTRA_UID` | `""` | Entra service account UID |
| `DRYRUN` | `""` | Pass `--dryrun` for testing (no IMDS access required) |


## Persistent Volume Mounts

The container requires persistent volumes for data durability and multi-restart compatibility. This volume mounts may be skipped for testing only.

| Mount Point | Purpose | Notes |
|---|---|---|
| `/opt/cycle_server/data` |  CycleCloud database, backups, configuration state | **Critical for data persistence** |
| `/opt/cycle_server/logs` |  Log files | Supports log rotation and monitoring |
| `/opt/cycle_server/config` | Configuration files | Supports mounted `cycle_server.properties` via Docker volume or Kubernetes ConfigMap. If mounted file exists, env vars do NOT override it. |
| `/opt/cycle_server/.ssh` | SSH keys | CycleCloud auto-generates node keypair (`cyclecloud.pem`) on first start if absent. |
| `/opt/cycle_server/work` |  Jetpack/project staging | Preserves deployed cluster compatibility across restarts |

**IMPORTANT**: Do NOT mount `/opt/cycle_server` itself — that would prevent container upgrades.


## Azure Identity

Azure Cyclecloud **requires** Azure identity (IMDS access). Two modes are supported:

### Managed Identity (Default)

- Pod/VM must have system-assigned or user-assigned Managed Identity
- Used to authenticate with Azure Resource Manager and storage

### Workload Identity

- Pod must have Workload Identity binding (Azure AD pod identity)


## Troubleshooting

### Container exits immediately

**Check the logs**:
```bash
docker logs cyclecloud
```

### Container runs but CycleCloud fails to start

**Enable debug mode**:
```bash
docker run -e CONTAINER_DEBUG=true cyclecloud:latest
```

The container will enter `sleep infinity` if CycleCloud fails, allowing log inspection.

### Port access issues

- Container listens on **8080** (HTTP) and **8443** (HTTPS), not 80/443
- Use port mapping in Docker or a Service in Kubernetes to expose external ports:
  ```bash
  docker run -p 443:8443 cyclecloud:latest
  ```


## Cyclecloud Account/Subscription Setup 

You can use ` cyclecloud_account.py` to automate subscription configuration. If you do not use `cyclecloud_account.py` to create the subscription then Cyclecloud will prompt you with normal subscription configuration wizard on first login.

 The `cyclecloud_account.py` script initializes the CycleCloud CLI and creates the default Azure account **after** CycleCloud is running. It is not called automatically by the container entrypoint — use it manually via `kubectl exec` or as an init/sidecar step once CycleCloud has started and is healthy.

**Prerequisites**: CycleCloud must be running and responding on the HTTPS port (check the readiness probe at `https://localhost:8443/health_monitor`).

#### Usage via `docker exec`

```bash
docker exec -it cyclecloud python3 /cs-install/scripts/cyclecloud_account.py \
  --useManagedIdentity \
  --storageAccount="mystorageaccount" \
  --storageManagedIdentity="/subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.ManagedIdentity/userAssignedIdentities/<name>" \
  --resourceGroup="my-cluster-rg" \
  --subscriptionId="sub-id" \
  --location="azure-region"
```

#### Usage via `kubectl exec`

```bash
kubectl exec -it <cyclecloud-pod> -- python3 /cs-install/scripts/cyclecloud_account.py \
  --useWorkloadIdentity \
  --storageAccount="mystorageaccount" \
  --storageManagedIdentity="/subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.ManagedIdentity/userAssignedIdentities/<name>" \
  --resourceGroup="my-cluster-rg" \
  --subscriptionId="sub-id" \
  --location="azure-region"
```


#### All Arguments

| Argument | Default | Description |
|----------|---------|-------------|
| `--username` | `cc_admin` | CycleCloud admin username |
| `--password` | `""` | Admin password (if empty, resets password via `cycle_server reset_access`) |
| `--tenantId` | — | Azure AD tenant ID |
| `--useManagedIdentity` | `false` | Use Managed Identity for Azure account |
| `--useWorkloadIdentity` | `false` | Use Workload Identity for Azure account |
| `--webServerSslPort` | `8443` | CycleCloud HTTPS port (for CLI initialization) |
| `--entraEnabled` | `false` | Use Entra ID authentication for CLI init |
| `--entraObjectId` | — | Entra object ID (required with `--entraEnabled`) |
| `--noDefaultAccount` | `false` | Skip Azure account creation (only initialize CLI) |
| `--azureSovereignCloud` | `public` | Azure cloud environment (`public`, `china`, `germany`, `usgov`) |
| `--applicationId` | — | Service Principal application ID (if not using MI/WI) |
| `--applicationSecret` | — | Service Principal secret (if not using MI/WI) |
| `--storageAccount` | — | Storage account name for CycleCloud locker |
| `--storageManagedIdentity` | — | Fully qualified resource ID of the Managed Identity for storage access (e.g., `/subscriptions/{subId}/resourceGroups/{rg}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/{name}`). If provided, locker uses MI auth; otherwise uses SharedAccessKey |
| `--subscriptionId` | (from IMDS) | Subscription Id for cluster resources |
| `--location` | (from IMDS) | Azure region for cluster resources |
| `--resourceGroup` | (from IMDS) | Resource group name for cluster resources |
| `--dryrun` | `false` | Test mode — skips IMDS and uses dummy metadata |

#### How location and locker identity are resolved

- **Location**: Automatically fetched from IMDS if not specified. The account uses the same Azure region as the VM/pod running CycleCloud. There is no CLI override.
- **Subscription ID**: Automatically fetched from IMDS if not specified.
- **Resource Group**: Defaults to the VM's resource group if `--resourceGroup` is not specified.
- **Locker auth**: If `--storageManagedIdentity` is provided, the locker authenticates to storage using that Managed Identity (requires `Storage Blob Data Contributor` role on the storage account). Must be the fully qualified resource ID, e.g., `/subscriptions/{subId}/resourceGroups/{rg}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/{name}`. If omitted, it falls back to SharedAccessKey.


## License

See [LICENSE](LICENSE) file.

## Security Reporting

See [SECURITY.md](SECURITY.md) for security vulnerability reporting instructions.