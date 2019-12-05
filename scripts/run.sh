#!/bin/bash

if [[ -n "${JAVA_HEAP_SIZE}" ]]; then
    echo "webServerMaxHeapSize=${JAVA_HEAP_SIZE}M" >> $CS_ROOT/config/cycle_server.properties
fi

# Setup SSH keypair for Azure CycleCloud
CS_USER=cycle_server
SSH_DIR=$CS_ROOT/.ssh
mkdir $SSH_DIR

SSH_KEYNAME="cyclecloud.pem"
ssh-keygen -t rsa -q -f $SSH_DIR/${SSH_KEYNAME} -N ""
chmod 600 $SSH_DIR/${SSH_KEYNAME}
chown ${CS_USER}:${CS_USER} -R $SSH_DIR
echo "Private Key for admin access to nodes.  Retain for cyclecloud cli and ssh access."
cat $SSH_DIR/${SSH_KEYNAME}

# Setup the azure storage share for logs and backups
if [ -d "$BACKUPS_DIRECTORY" ]; then
  mv $CS_ROOT/logs $BACKUPS_DIRECTORY/
  ln -s $BACKUPS_DIRECTORY/logs $CS_ROOT/
  chown cycle_server:cycle_server $CS_ROOT/logs
  mv $CS_ROOT/data/backups $BACKUPS_DIRECTORY/ || true
  mkdir $BACKUPS_DIRECTORY/backups || true
  ln -s $BACKUPS_DIRECTORY/backups $CS_ROOT/data/
  chown cycle_server:cycle_server $CS_ROOT/data/backups
fi

$CS_ROOT/cycle_server start --wait

if  [ -z ${FQDN+x} ] ; then
  echo "skipping LetsEncrypt dns"
else
  ${CS_ROOT}/cycle_server keystore automatic --accept-terms ${FQDN} 
fi

CYCLECLOUD_AUTOCONFIG=$(echo $CYCLECLOUD_AUTOCONFIG | tr '[:upper:]' '[:lower:]')

if [ "$CYCLECLOUD_AUTOCONFIG" = "true" ];then
    if [ -z $CYCLECLOUD_USERNAME ] || [ -z $CYCLECLOUD_PASSWORD ] || [ -z $CYCLECLOUD_USER_PUB_KEY ];then
        print STDERR "ERROR: CYCLECLOUD_AUTOCONFIG is set to true, but CYCLECLOUD_USERNAME, CYCLECLOUD_PASSWORD or CYCLECLOUD_USER_PUB_KEY is not defined"
        exit 1
    fi

    user_name=${CYCLECLOUD_USERNAME}
    cyclecloud_password=${CYCLECLOUD_PASSWORD}
    user_public_key=${CYCLECLOUD_USER_PUB_KEY}

    credential_name="${user_name}/${user_name}-publickey"

    cat <<EOF > /tmp/initial_data.json
[
    {
        "AdType": "Application.Setting",
        "Name": "cycleserver.installation.complete",
        "Value": true
    },
    {
        "AdType": "Application.Setting",
        "Name": "cycleserver.installation.initial_user",
        "Value": "$user_name"
    },
    {
        "AdType": "AuthenticatedUser",
        "Name": "$user_name",
        "RawPassword": "$cyclecloud_password",
        "Superuser": true
    },
    {
        "PublicKey": "$user_public_key",
        "AdType": "Credential",
        "CredentialType": "PublicKey",
        "Name": "$credential_name"
    }
]
EOF

    cp /tmp/initial_data.json $CS_ROOT/config/data/ 

    cat /tmp/initial_data.json 
    sleep 5s
    ls $CS_ROOT/config/data/ 
    rm -f /tmp/initial_data.json

fi

while true
do
  sleep 60
  $CS_ROOT/cycle_server status || exit 
done


