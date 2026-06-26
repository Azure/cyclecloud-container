# CycleCloud Marketplace Container Image

This repository produces a generalized, marketplace-ready CycleCloud container image based on Ubuntu 24.04 with support for Azure Identity (Managed Identity or Workload Identity), mounted configuration files, and persistent volumes.

## Features

- **Ubuntu 24.04 base image** with OpenJDK 8, Azure CLI, and Python 3
- **Unprivileged execution** as `cycle_server` user (UID 1169, GID 1169)
- **Azure Identity support** via Managed Identity or Workload Identity
- **Persistent volume support** for data, logs, configuration, SSH keys, and work directories
- **Flexible configuration** via environment variables with sensible defaults
- **Security-first design** with fail-closed password validation and IMDS requirement
- **Debug mode** for troubleshooting container startup issues

## Building the Image

```bash
docker build -t cyclecloud:latest .
```

## Running the Container

### Prerequisites

- Azure VM or AKS pod with IMDS access
- For AKS: Pod must have Managed Identity or Workload Identity enabled
- Azure managed disks or Azure Files for persistent volumes
- Set `fsGroup: 1169` in the pod `securityContext` (Kubernetes only)

### Minimum Docker Example

```bash
docker run -it \
  --name cyclecloud \
  -e CYCLECLOUD_PASSWORD="MySecurePassword123!" \
  -e CYCLECLOUD_USERNAME="ccadmin" \
  cyclecloud:latest
```

### Docker with Volumes

```bash
docker run -it \
  --name cyclecloud \
  -e CYCLECLOUD_PASSWORD="MySecurePassword123!" \
  -e CYCLECLOUD_USERNAME="ccadmin" \
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

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: cyclecloud
spec:
  serviceAccountName: cyclecloud-sa  # Must have Managed Identity or Workload Identity binding
  securityContext:
    runAsUser: 1169
    runAsGroup: 1169
    fsGroup: 1169  # Critical: Required for PV mounts to be writable by UID 1169
  containers:
  - name: cyclecloud
    image: cyclecloud:latest
    env:
    - name: CYCLECLOUD_PASSWORD
      valueFrom:
        secretKeyRef:
          name: cyclecloud-secret
          key: password
    - name: CYCLECLOUD_USERNAME
      value: "ccadmin"
    - name: CYCLECLOUD_STORAGE
      value: "mystorageaccount"
    - name: USE_WORKLOAD_IDENTITY
      value: "true"
    ports:
    - containerPort: 8080
      name: http
    - containerPort: 8443
      name: https
    - containerPort: 9443
      name: cluster
    volumeMounts:
    - name: data
      mountPath: /opt/cycle_server/data
    - name: logs
      mountPath: /opt/cycle_server/logs
    - name: config
      mountPath: /opt/cycle_server/config
    - name: ssh
      mountPath: /opt/cycle_server/.ssh
    - name: work
      mountPath: /opt/cycle_server/work
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: cyclecloud-data-pvc
  - name: logs
    persistentVolumeClaim:
      claimName: cyclecloud-logs-pvc
  - name: config
    persistentVolumeClaim:
      claimName: cyclecloud-config-pvc
  - name: ssh
    persistentVolumeClaim:
      claimName: cyclecloud-ssh-pvc
  - name: work
    persistentVolumeClaim:
      claimName: cyclecloud-work-pvc
```

## Environment Variables

All environment variables have sensible defaults. Override them as needed:

An example env file is included at the repo root as `example.env`. Pass it at runtime with Docker's `--env-file` flag or the equivalent in your orchestrator.

| Variable | Default | Description |
|----------|---------|-------------|
| `CYCLECLOUD_USERNAME` | `"ccadmin"` | Initial admin username |
| `CYCLECLOUD_PASSWORD` | `"CHANGEME"` | **REQUIRED** - Change before production use. Container fails to start if left as `"CHANGEME"` unless `CONTAINER_DEBUG=true` |
| `CYCLECLOUD_USER_PUBKEY` | `""` | SSH public key for admin user |
| `USE_WORKLOAD_IDENTITY` | `"false"` | If `"true"`, use Workload Identity; otherwise Managed Identity |
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
| `NO_DEFAULT_ACCOUNT` | `""` | Pass `--noDefaultAccount` to skip account creation |

## Persistent Volume Mounts

The container requires persistent volumes for data durability and multi-restart compatibility:

| Mount Point | Purpose | Notes |
|---|---|---|
| `/opt/cycle_server/data` | **Required** - CycleCloud database, backups, configuration state | **Critical for data persistence** |
| `/opt/cycle_server/logs` | **Required** - Log files | Supports log rotation and monitoring |
| `/opt/cycle_server/config` | Configuration files | Supports mounted `cycle_server.properties` via Docker volume or Kubernetes ConfigMap. If mounted file exists, env vars do NOT override it. |
| `/opt/cycle_server/.ssh` | **Required** - SSH keys | CycleCloud auto-generates node keypair (`cyclecloud.pem`) on first start if absent. Persists across restarts. Do NOT mount `/opt/cycle_server/.ssh` before first run if you want auto-generation. |
| `/opt/cycle_server/work` | **Required** - Jetpack/project staging | Preserves deployed cluster compatibility across restarts |

**IMPORTANT**: Do NOT mount `/opt/cycle_server` itself — that would prevent container upgrades.

## Configuration File Precedence

Configuration is resolved in this order (highest to lowest priority):

1. **User-mounted `cycle_server.properties`** (via Docker volume or Kubernetes ConfigMap) — **never overwritten**
2. **Runtime environment variables** supplied to the container, including values loaded through Docker `--env-file`
3. **Build-time package defaults** from `cyclecloud8` package

Example: If you mount `/opt/cycle_server/config/cycle_server.properties` and also set `CYCLECLOUD_WEBSERVER_PORT=9999`, CycleCloud will use the port from the mounted file, not the env var.

## Azure Identity

The container **requires** Azure identity (IMDS access). Two modes are supported:

### Managed Identity (Default)

- Pod/VM must have system-assigned or user-assigned Managed Identity
- Used to authenticate with Azure Resource Manager and storage
- Enable via `USE_WORKLOAD_IDENTITY="false"` (default)

### Workload Identity

- Pod must have Workload Identity binding (Azure AD pod identity)
- Requires environment variables: `AZURE_AUTHORITY_HOST`, `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`
- Enable via `USE_WORKLOAD_IDENTITY="true"`

If IMDS is unreachable, the container exits with error: `ERROR: IMDS endpoint unreachable — container requires Azure identity`

## Security Considerations

1. **Password Validation (Fail-Closed)**:
   - If `CYCLECLOUD_PASSWORD="CHANGEME"` (default) and `CONTAINER_DEBUG != "true"`, the container **exits at startup** with error code 1.
   - This prevents accidental production deployments with default credentials.
   - Override via secret before production use; for testing, set `CONTAINER_DEBUG=true`.

2. **Unprivileged User**:
   - Container runs as UID 1169 (cycle_server), not root.
   - Cannot bind ports <1024; ports must be 8080/8443.
   - No `CAP_NET_BIND_SERVICE` is added — this is a security requirement, not a cosmetic choice.

3. **Kubernetes fsGroup**:
   - Set `fsGroup: 1169` in the pod `securityContext`.
   - Without it, Kubernetes assigns root ownership to mounted volumes, and the unprivileged container fails to write to them.

4. **No Backup/Restore Loop**:
   - Backup/restore logic has been removed from the entrypoint.
   - Rely on persistent volumes for data durability.

## Troubleshooting

### Container exits immediately

**Check the logs**:
```bash
docker logs cyclecloud
```

**Common reasons**:
- `CYCLECLOUD_PASSWORD="CHANGEME"` and `CONTAINER_DEBUG != "true"` → Set a new password or enable debug mode
- IMDS unreachable → Ensure container runs on Azure VM/AKS pod with IMDS access
- Missing persistent volumes → Create volumes before starting

### Container runs but CycleCloud fails to start

**Enable debug mode**:
```bash
docker run -e CONTAINER_DEBUG=true -e CYCLECLOUD_PASSWORD="test" cyclecloud:latest
```

The container will enter `sleep infinity` if CycleCloud fails, allowing log inspection:
```bash
docker exec cyclecloud bash -c 'tail -f /opt/cycle_server/logs/catalina.out'
```

### Port access issues

- Container listens on **8080** (HTTP) and **8443** (HTTPS), not 80/443
- Use port mapping in Docker or a Service in Kubernetes to expose external ports:
  ```bash
  docker run -p 443:8443 cyclecloud:latest
  ```

### Configuration not applied

**If you mounted `cycle_server.properties`**:
- Environment variables are ignored for that property file
- Edit the mounted file directly or remount a new one

**If you're using env vars**:
- Ensure `GENERATE_CS_CONFIG="true"` (default)
- Env vars only apply if no mounted config file exists

### Persistent volume ownership issues (Kubernetes)

- Verify `fsGroup: 1169` is set in pod `securityContext`
- Check PV access mode is `ReadWriteOnce` or `ReadWriteMany`
- Verify PVC is bound to a PV

## Advanced Configuration

### Custom JVM Options

Set JVM options via environment variable:
```bash
docker run -e CYCLECLOUD_WEBSERVER_JVM_OPTIONS="-Xms2g -Xmx6g" cyclecloud:latest
```

### Dry-Run Mode (Testing without IMDS)

```bash
docker run -e DRYRUN=true -e CYCLECLOUD_PASSWORD="test" cyclecloud:latest
```

### Skip Default Account Creation

```bash
docker run -e NO_DEFAULT_ACCOUNT=true cyclecloud:latest
```

(Useful for CycleCloud instances that manage other subscriptions)

## Acceptance Criteria (Implementation Status)

✅ Container builds successfully from Ubuntu 24.04 base  
✅ Container starts CycleCloud in foreground mode  
✅ All ENV vars have sensible defaults  
✅ Fail-closed security gate for default password  
✅ Container requires Azure Identity (MI or WI) via IMDS  
✅ Persistent volumes for data, logs, config, .ssh, work are supported  
✅ No backup/restore logic in entrypoint  
✅ `CONTAINER_DEBUG=true` keeps container alive for troubleshooting  
✅ Runs as unprivileged cycle_server user  
✅ `FORCE_DELETE` configuration via cyclecloud_install.py  
✅ SSH keypair auto-generated on first start  
✅ HTTPS with self-signed certificate on first start  

## Deferred Features (Not in Scope)

- AzLinux 4.x base image (revisit when available)
- Credential rotation via `util/rotate_creds.sh` (TBD)
- Running without IMDS
- Entra ID integration logic (variables accepted but behavior not yet specified)

## License

See [LICENSE](LICENSE) file.

## Security Reporting

See [SECURITY.md](SECURITY.md) for security vulnerability reporting instructions.