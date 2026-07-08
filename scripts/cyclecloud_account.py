#!/usr/bin/python3
"""
CycleCloud Account Setup - runs after CycleCloud is started.
Initializes the CycleCloud CLI and creates the default Azure account.
"""

import os
import json
import argparse
import random
import subprocess
from string import ascii_lowercase
from subprocess import CalledProcessError, check_output
from urllib.request import urlopen, Request
from shutil import rmtree
from tempfile import mkdtemp
from time import sleep


tmpdir = mkdtemp()
print("Creating temp directory {} for account setup".format(tmpdir))
cycle_root = "/opt/cycle_server"
cs_cmd = cycle_root + "/cycle_server"


def clean_up():
    """Clean up temporary directory."""
    rmtree(tmpdir)


def _catch_sys_error(cmd_list):
    """Execute a system command and catch errors."""
    try:
        output = check_output(cmd_list)
        safe_cmd = [c if '--password' not in c else '--password=***' for c in cmd_list]
        print(safe_cmd)
        print(output)
        return output
    except CalledProcessError as e:
        safe_cmd = [c if '--password' not in c else '--password=***' for c in e.cmd]
        print("Error with cmd: %s" % safe_cmd)
        print("Output: %s" % e.output)
        raise


def reset_cyclecloud_pw(username):
    """Reset a CycleCloud user password."""
    reset_pw = subprocess.Popen([cs_cmd, "reset_access", username],
                                stdin=subprocess.PIPE,
                                stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE)
    reset_out, reset_err = reset_pw.communicate(b"yes\n")
    print(reset_out)
    if reset_err:
        print("Password reset error: %s" % (reset_err))
    out_split = reset_out.rsplit(None, 1)
    pw = out_split.pop().decode("utf-8")
    print("Disabling forced password reset for {}".format(username))
    update_cmd = 'update AuthenticatedUser set ForcePasswordReset = false where Name=="%s"' % (username)
    _catch_sys_error([cs_cmd, 'execute', update_cmd])
    return pw


def setup_local_account(admin_user, password, webserver_port):
    """Initialize CLI for the local admin account (CC must be running)."""
    cyclecloud_admin_pw = ""
    if password:
        cyclecloud_admin_pw = password
    else:
        # Password was generated pre-start; reset to get a new one from CC
        cyclecloud_admin_pw = reset_cyclecloud_pw(admin_user)

    initialize_cyclecloud_cli(admin_user, cyclecloud_admin_pw, webserver_port)


def initialize_cyclecloud_cli(admin_user, cyclecloud_admin_pw, webserver_port):
    """Initialize the CycleCloud CLI."""
    print("Initializing CycleCloud CLI")
    password_flag = ("--password=%s" % cyclecloud_admin_pw)
    _catch_sys_error(["/usr/local/bin/cyclecloud", "initialize", "--loglevel=debug", "--batch", "--force",
                      "--url=https://localhost:{}".format(webserver_port),
                      "--verify-ssl=false", "--username=%s" % admin_user, password_flag])


def initialize_cli_with_workload_identity(webserver_port):
    """Initialize CycleCloud CLI with workload identity."""
    print("Initializing cyclecloud CLI with workload identity")
    _catch_sys_error([
        "/usr/local/bin/cyclecloud", "initialize",
        "--workload-identity",
        "--verify-ssl=false",
        "--url=https://localhost:{}".format(webserver_port),
        "--batch",
        "--force",
        "--loglevel=debug"
    ])


def initialize_cli_with_managed_identity(webserver_port, tenant_id, entra_object_id):
    """Initialize CycleCloud CLI with managed identity."""
    print("Initializing cyclecloud CLI with managed identity")
    _catch_sys_error([
        "/usr/local/bin/cyclecloud", "initialize",
        "--identity",
        "--tenant_id={}".format(tenant_id),
        "--object_id={}".format(entra_object_id),
        "--verify-ssl=false",
        "--url=https://localhost:{}".format(webserver_port),
        "--batch",
        "--force",
        "--loglevel=debug"
    ])


def get_workload_identity():
    """Validate that required workload identity environment variables are set."""
    required_vars = ["AZURE_AUTHORITY_HOST", "AZURE_TENANT_ID", "AZURE_CLIENT_ID"]
    missing = [v for v in required_vars if v not in os.environ]
    if missing:
        print("Missing environment variables for workload identity: {}".format(", ".join(missing)))
        raise KeyError("Required workload identity env vars not set: {}".format(missing))
    print("Workload Identity exists")


def get_vm_metadata():
    """Fetch VM metadata from IMDS with retries."""
    metadata_url = "http://169.254.169.254/metadata/instance?api-version=2017-08-01"
    metadata_req = Request(metadata_url, headers={"Metadata": "true"})

    for attempt in range(30):
        print("Fetching metadata (attempt {}/30)".format(attempt + 1))
        try:
            metadata_response = urlopen(metadata_req, timeout=2)
            return json.load(metadata_response)
        except ValueError as e:
            print("Failed to get metadata: %s" % e)
            print("Retrying...")
            sleep(2)
            continue
        except Exception as e:
            print("Error fetching metadata: %s" % e)
            print("Retrying...")
            sleep(2)
            continue

    print("ERROR: IMDS endpoint unreachable — container requires Azure identity")
    raise Exception("ERROR: IMDS endpoint unreachable — container requires Azure identity")


def create_azure_account(vm_metadata, use_managed_identity, use_workload_identity, tenant_id, application_id,
                         application_secret, azure_cloud, storageAccount, storage_managed_identity, resource_group=None):
    """Create the default Azure account using CycleCloud CLI (requires CC running)."""
    subscription_id = vm_metadata["compute"]["subscriptionId"]
    location = vm_metadata["compute"]["location"]
    metadata_rg = vm_metadata["compute"]["resourceGroupName"]

    if resource_group:
        print("CycleCloud created in resource group: %s" % metadata_rg)
        print("Cluster resources will be created in resource group: %s" % resource_group)
    else:
        resource_group = metadata_rg

    random_suffix = ''.join(random.SystemRandom().choice(ascii_lowercase) for _ in range(14))

    if storageAccount:
        print('Storage account specified, using it as the default locker')
        storage_account_name = storageAccount
    else:
        storage_account_name = 'cyclecloud{}'.format(random_suffix)

    azure_data = {
        "Environment": azure_cloud,
        "AzureRMUseManagedIdentity": use_managed_identity,
        "AzureRMUseWorkloadIdentity": use_workload_identity,
        "AzureResourceGroup": resource_group,
        "AzureRMApplicationId": application_id,
        "AzureRMApplicationSecret": application_secret,
        "AzureRMSubscriptionId": subscription_id,
        "AzureRMTenantId": tenant_id,
        "DefaultAccount": True,
        "Location": location,
        "Name": "azure",
        "Provider": "azure",
        "ProviderId": subscription_id,
        "RMStorageAccount": storage_account_name,
        "RMStorageContainer": "cyclecloud"
    }

    if storage_managed_identity:
        azure_data["LockerIdentity"] = storage_managed_identity
        azure_data["LockerAuthMode"] = "ManagedIdentity"
    else:
        azure_data["LockerAuthMode"] = "SharedAccessKey"

    # Write to temp file and use cyclecloud account create
    account_file = os.path.join(tmpdir, "azure_account.json")
    with open(account_file, 'w') as fp:
        json.dump(azure_data, fp)

    print("CycleCloud account data:")
    print(json.dumps(azure_data))

    _catch_sys_error(["/usr/local/bin/cyclecloud", "account", "create", "-f", account_file])


def cyclecloud_account_setup(admin_user, password, webserver_port, use_managed_identity, use_workload_identity,
                             tenant_id, entra_enabled=False, entra_object_id=None,
                             no_default_account=False, azure_cloud="public", application_id=None,
                             application_secret=None, storageAccount=None, storage_managed_identity=None,
                             resource_group=None, dryrun=False):
    """Initialize CycleCloud CLI and create Azure account (requires CC to be running)."""
    print("Initializing cyclecloud CLI")

    if use_workload_identity:
        get_workload_identity()

    if not entra_enabled:
        setup_local_account(admin_user, password, webserver_port)
    else:
        print("Entra is enabled.")
        if use_workload_identity:
            print("Using Workload Identity.")
            initialize_cli_with_workload_identity(webserver_port)
        elif use_managed_identity:
            print("Using Managed Identity.")
            initialize_cli_with_managed_identity(webserver_port, tenant_id, entra_object_id)
        else:
            raise ValueError("Entra is enabled but neither workload identity nor managed identity is configured. "
                             "Please enable --useWorkloadIdentity or --useManagedIdentity.")

    if not no_default_account:
        if not dryrun:
            vm_metadata = get_vm_metadata()
        else:
            vm_metadata = {
                "compute": {
                    "subscriptionId": "1234-50-679890",
                    "location": "dryrun",
                    "resourceGroupName": "dryrun-rg"
                }
            }
        create_azure_account(vm_metadata, use_managed_identity, use_workload_identity, tenant_id,
                             application_id, application_secret, azure_cloud, storageAccount,
                             storage_managed_identity, resource_group)


def main():
    """Main entry point - CLI initialization and account creation (runs after CC is started)."""
    parser = argparse.ArgumentParser(description="CycleCloud CLI Initialization and Account Setup (runs after CC is started)")

    parser.add_argument("--tenantId", dest="tenantId", help="Tenant ID of the Azure subscription")
    parser.add_argument("--username", dest="username", default="cc_admin", help="The local admin user for CycleCloud")
    parser.add_argument("--password", dest="password", default="", help="The password for the CycleCloud UI user")
    parser.add_argument("--useManagedIdentity", dest="useManagedIdentity", action="store_true",
                        help="Use Managed Identity rather than a Service Principal")
    parser.add_argument("--useWorkloadIdentity", dest="useWorkloadIdentity", action="store_true",
                        help="Use Workload Identity rather than a Service Principal")
    parser.add_argument("--webServerSslPort", dest="webServerSslPort", default=8443, help="CycleCloud HTTPS port")
    parser.add_argument("--entraEnabled", dest="entraEnabled", action="store_true", help="Enable Entra ID authentication")
    parser.add_argument("--entraObjectId", dest="entraObjectId", default=None, help="Entra object ID")
    parser.add_argument("--noDefaultAccount", dest="noDefaultAccount", action="store_true",
                        help="Do not configure a default CycleCloud Account")
    parser.add_argument("--azureSovereignCloud", dest="azureSovereignCloud", default="public",
                        help="Azure Region [china|germany|public|usgov]")
    parser.add_argument("--applicationId", dest="applicationId", help="Application ID of the Service Principal")
    parser.add_argument("--applicationSecret", dest="applicationSecret", help="Application Secret of the Service Principal")
    parser.add_argument("--storageAccount", dest="storageAccount", help="The storage account to use as a CycleCloud locker")
    parser.add_argument("--storageManagedIdentity", dest="storageManagedIdentity", default=None,
                        help="Managed Identity for storage access")
    parser.add_argument("--resourceGroup", dest="resourceGroup", help="The resource group for CycleCloud cluster resources")
    parser.add_argument("--dryrun", dest="dryrun", action="store_true", help="Dry run mode for testing")

    args = parser.parse_args()

    safe_args = {k: ('***' if k == 'password' else v) for k, v in vars(args).items()}
    print("Account setup arguments: %s" % safe_args)

    try:
        cyclecloud_account_setup(args.username, args.password, args.webServerSslPort,
                                 args.useManagedIdentity, args.useWorkloadIdentity, args.tenantId,
                                 args.entraEnabled, args.entraObjectId,
                                 args.noDefaultAccount, args.azureSovereignCloud,
                                 args.applicationId, args.applicationSecret,
                                 args.storageAccount, args.storageManagedIdentity,
                                 args.resourceGroup, args.dryrun)
    finally:
        clean_up()


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print("Account setup failed: %s" % e)
        raise
