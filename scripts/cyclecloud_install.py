#!/usr/bin/python3
"""
CycleCloud pre-start configuration.
Writes config data files and generates cycle_server.properties.
"""

import os
import argparse
import json
import random
from string import ascii_uppercase, ascii_lowercase, digits
from subprocess import CalledProcessError, check_output
from os import fdopen, remove
from shutil import rmtree, move
from tempfile import mkstemp, mkdtemp


tmpdir = mkdtemp()
print("Creating temp directory {} for installing CycleCloud".format(tmpdir))
cycle_root = "/opt/cycle_server"
cs_cmd = cycle_root + "/cycle_server"


def clean_up():
    """Clean up temporary directory."""
    rmtree(tmpdir)


def _distribution_method_record():
    """Return the distribution method record for CycleCloud."""
    return {
        "Category": "system",
        "Status": "internal",
        "AdType": "Application.Setting",
        "Description": "CycleCloud distribution method e.g. marketplace, container, manual.",
        "Value": "container",
        "Name": "distribution_method"
    }


def _installation_complete_record():
    """Return the installation complete record."""
    return {
        "AdType": "Application.Setting",
        "Name": "cycleserver.installation.complete",
        "Value": True
    }


def _initial_user_record(username):
    """Return the initial user record."""
    return {
        "AdType": "Application.Setting",
        "Name": "cycleserver.installation.initial_user",
        "Value": username
    }


def _write_config_data(data, filename):
    """Write data as JSON to a temp file, set ownership, and move to config/data."""
    data_file = os.path.join(tmpdir, filename)
    with open(data_file, 'w') as fp:
        json.dump(data, fp)
    _catch_sys_error(["chown", "cycle_server:cycle_server", data_file])
    _catch_sys_error(["mv", data_file, "/opt/cycle_server/config/data/"])


def _as_bool(value):
    """Convert common truthy/falsey values to bool."""
    if isinstance(value, bool):
        return value
    return str(value).strip().lower() in ("1", "true", "yes", "on")


def configure_force_delete(force_delete_vms, force_delete_vmss):
    """Persist force delete application settings in CycleCloud."""
    force_delete_data = [
        {
            "AdType": "Application.Setting",
            "Name": "cyclecloud.force_delete.vm",
            "Value": _as_bool(force_delete_vms)
        },
        {
            "AdType": "Application.Setting",
            "Name": "cyclecloud.force_delete.vmss",
            "Value": _as_bool(force_delete_vmss)
        }
    ]
    _write_config_data(force_delete_data, "force_delete.json")


def generate_password_string():
    """Generate a random password string."""
    random_pw_chars = ([random.choice(ascii_lowercase) for _ in range(20)] +
                       [random.choice(ascii_uppercase) for _ in range(20)] +
                       [random.choice(digits) for _ in range(10)])
    random.shuffle(random_pw_chars)
    return ''.join(random_pw_chars)


def setup_local_account_data(admin_user, password, public_key=None):
    """Write local admin account data to config/data (pre-start).
    
    Returns the password used (either provided or generated).
    """
    if password:
        print('Password specified, using it as the admin password')
        cyclecloud_admin_pw = password
    else:
        cyclecloud_admin_pw = generate_password_string()

    account_data = [
        _initial_user_record(admin_user),
        _distribution_method_record(),
        _installation_complete_record()
    ]

    # Create login user account
    login_user = {
        "AdType": "AuthenticatedUser",
        "Name": admin_user,
        "RawPassword": cyclecloud_admin_pw,
        "Superuser": True
    }
    if public_key:
        login_user["PublicKey"] = public_key
    account_data.append(login_user)

    _write_config_data(account_data, "account_data.json")
    return cyclecloud_admin_pw


def _catch_sys_error(cmd_list):
    """Execute a system command and catch errors."""
    try:
        output = check_output(cmd_list)
        print(cmd_list)
        print(output)
        return output
    except CalledProcessError as e:
        print("Error with cmd: %s" % e.cmd)
        print("Output: %s" % e.output)
        raise


def setup_entra(entra_tenant_id, entra_client_id, entra_object_id, entra_auth_endpoint,
                cyclecloud_username="cc-vm-mi", entra_uid=19000):
    """Configure Entra ID authentication for CycleCloud (pre-start via config/data)."""
    print("Configuring Entra ID authentication for CycleCloud")

    if not all([entra_tenant_id, entra_client_id, entra_object_id, entra_auth_endpoint]):
        raise ValueError("Missing required Entra ID configuration. Please provide "
                         "entra_tenant_id, entra_client_id, entra_object_id, and entra_auth_endpoint.")

    entra_tenant_setting = {
        "Category": "Authorization",
        "AdType": "Application.Setting",
        "Description": "The tenant ID to use for Entra ID authentication",
        "Label": "Tenant ID",
        "Value": entra_tenant_id,
        "Name": "authentication.entra.tenantid",
        "ParameterType": "String"
    }

    entra_client_setting = {
        "Category": "Authorization",
        "AdType": "Application.Setting",
        "Description": "The client ID (application ID) to use for Entra ID authentication",
        "Label": "Client ID",
        "Value": entra_client_id,
        "Name": "authentication.entra.clientid",
        "ParameterType": "String"
    }

    entra_endpoint_setting = {
        "Category": "Authorization",
        "AdType": "Application.Setting",
        "Description": "The Entra ID authentication endpoint to use, including the protocol.",
        "Label": "Endpoint",
        "Value": entra_auth_endpoint,
        "Name": "authentication.entra.endpoint",
        "ParameterType": "String"
    }

    entra_enabled_setting = {
        "Category": "Authorization",
        "AdType": "Application.Setting",
        "Description": "If set to true, use Entra ID for authentication",
        "Value": True,
        "Name": "authentication.entra.enabled",
        "ParameterType": "Boolean"
    }

    service_account = {
        "Authentication": "internal",
        "EntraTID": entra_tenant_id,
        "UID": entra_uid,
        "EntraOID": entra_object_id,
        "Superuser": True,
        "NodeAccessDisabled": True,
        "AdType": "AuthenticatedUser",
        "Roles": ["Administrator", "User", "Cluster Creator"],
        "NodeUserName": cyclecloud_username,
        "ServiceAccount": True,
        "Name": cyclecloud_username,
        "ForcePasswordReset": False
    }

    entra_data = [
        entra_tenant_setting,
        entra_client_setting,
        entra_endpoint_setting,
        entra_enabled_setting,
        _installation_complete_record(),
        _distribution_method_record(),
        _initial_user_record(cyclecloud_username),
        service_account
    ]

    _write_config_data(entra_data, "entra_auth.json")


def modify_cs_config(options):
    """Modify CycleCloud server system properties file."""
    print("Editing CycleCloud server system properties file")
    cs_config_file = cycle_root + "/config/cycle_server.properties"

    fh, tmp_cs_config_file = mkstemp()
    with fdopen(fh, 'w') as new_config:
        with open(cs_config_file) as cs_config:
            for line in cs_config:
                if line.startswith('webServerMaxHeapSize='):
                    new_config.write('webServerMaxHeapSize={}\n'.format(options['webServerMaxHeapSize']))
                elif line.startswith('webServerPort='):
                    new_config.write('webServerPort={}\n'.format(options['webServerPort'] if options['webServerPort'] else 8080))
                elif line.startswith('webServerSslPort='):
                    new_config.write('webServerSslPort={}\n'.format(options['webServerSslPort'] if options['webServerSslPort'] else 8443))
                elif line.startswith('webServerClusterPort'):
                    new_config.write('webServerClusterPort={}\n'.format(options['webServerClusterPort'] if options['webServerClusterPort'] else 9443))
                elif line.startswith('webServerEnableHttps='):
                    new_config.write('webServerEnableHttps={}\n'.format(str(options['webServerEnableHttps']).lower() if options['webServerEnableHttps'] else 'true'))
                elif line.startswith('webServerHostname'):
                    continue
                elif line.startswith('webServerJvmOptions='):
                    jvm_options = os.environ.get('CYCLECLOUD_WEBSERVER_JVM_OPTIONS', '')
                    if jvm_options:
                        new_config.write('webServerJvmOptions={}\n'.format(jvm_options))
                else:
                    new_config.write(line)

            new_config.write('\n\n')
            if 'webServerHostname' in options and options['webServerHostname']:
                new_config.write('webServerHostname={}\n'.format(options['webServerHostname']))

    remove(cs_config_file)
    move(tmp_cs_config_file, cs_config_file)
    _catch_sys_error(["chown", "cycle_server:cycle_server", cs_config_file])





def main():
    """Main entry point - pre-start configuration only."""
    parser = argparse.ArgumentParser(description="CycleCloud Pre-Start Configuration")

    parser.add_argument("--webServerMaxHeapSize", dest="webServerMaxHeapSize", default='4096M', help="CycleCloud max heap")
    parser.add_argument("--webServerPort", dest="webServerPort", default=8080, help="CycleCloud HTTP port")
    parser.add_argument("--webServerSslPort", dest="webServerSslPort", default=8443, help="CycleCloud HTTPS port")
    parser.add_argument("--webServerClusterPort", dest="webServerClusterPort", default=9443, help="CycleCloud cluster port")
    parser.add_argument("--webServerHostname", dest="webServerHostname", default="", help="Override CycleCloud hostname")
    parser.add_argument("--generateCsConfig", dest="generateCsConfig", action="store_true",
                        help="Generate a cyclecloud config file from environment variables")
    parser.add_argument("--username", dest="username", default="cc_admin", help="The local admin user for CycleCloud")
    parser.add_argument("--password", dest="password", default="", help="The password for the CycleCloud UI user")
    parser.add_argument("--publickey", dest="publickey", default="", help="The public SSH key for the CycleCloud admin user")
    parser.add_argument("--dryrun", dest="dryrun", action="store_true", help="Dry run mode for testing")
    parser.add_argument("--entraEnabled", dest="entraEnabled", action="store_true", help="Enable Entra ID authentication")
    parser.add_argument("--entraTenantId", dest="entraTenantId", default=None, help="Entra tenant ID")
    parser.add_argument("--entraClientId", dest="entraClientId", default=None, help="Entra client ID")
    parser.add_argument("--entraObjectId", dest="entraObjectId", default=None, help="Entra object ID")
    parser.add_argument("--entraAuthEndpoint", dest="entraAuthEndpoint", default=None, help="Entra auth endpoint")
    parser.add_argument("--entraUsername", dest="entraUsername", default="cc-vm-mi", help="Entra service account username")
    parser.add_argument("--entraUID", dest="entraUID", type=int, default=19000, help="Entra service account UID")
    parser.add_argument("--forceDeleteVms", dest="forceDeleteVms", default="true",
                        help="Enable/disable force delete for VMs [true|false]")
    parser.add_argument("--forceDeleteVmss", dest="forceDeleteVmss", default="true",
                        help="Enable/disable force delete for VMSS [true|false]")

    args = parser.parse_args()

    safe_args = {k: ('***' if k == 'password' else v) for k, v in vars(args).items()}
    print("Configuration arguments: %s" % safe_args)

    try:
        if args.generateCsConfig:
            modify_cs_config(options={
                'webServerMaxHeapSize': args.webServerMaxHeapSize,
                'webServerPort': args.webServerPort,
                'webServerSslPort': args.webServerSslPort,
                'webServerClusterPort': args.webServerClusterPort,
                'webServerEnableHttps': True,
                'webServerHostname': args.webServerHostname
            })

        if args.entraEnabled:
            setup_entra(args.entraTenantId, args.entraClientId, args.entraObjectId, args.entraAuthEndpoint,
                        args.entraUsername, args.entraUID)
        else:
            setup_local_account_data(args.username, args.password, args.publickey)

        configure_force_delete(args.forceDeleteVms, args.forceDeleteVmss)

    finally:
        clean_up()


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print("Deployment failed: %s" % e)
        raise
