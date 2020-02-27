#!/bin/bash
set -x

for filename in cyclecloud*amd64.deb; do
    dpkg --force-all -i ./${filename} 
done

echo '/usr/local/openjdk-8' > /opt/cycle_server/config/java_home

# Copy components
if [ $(ls -A components/)i ]; then
    chown cycle_server:cycle_server components/*
    mv components/* $CS_ROOT/components/
fi

# Copy records
if [ $(ls -A records/) ]; then
    chown cycle_server:cycle_server records/*
    mv records/* $CS_ROOT/records/
fi  

cat << EOF > $CS_ROOT/config/data/distro-method-container.txt
AdType = "Application.Setting"
Name = "distribution_method"
Category = "system"
Status = "internal"
Value = "container"
Description = "CycleCloud distribution method e.g. marketplace, container, manual."
EOF

# Update properties

sed -i 's/webServerMaxHeapSize\=2048M/webServerMaxHeapSize\=4096M/' $CS_ROOT/config/cycle_server.properties
sed -i 's/webServerPort\=8080/webServerPort\=80/' $CS_ROOT/config/cycle_server.properties
sed -i 's/webServerSslPort\=8443/webServerSslPort\=443/' $CS_ROOT/config/cycle_server.properties
sed -i 's/webServerEnableHttps\=false/webServerEnableHttps=true/' $CS_ROOT/config/cycle_server.properties

ls -l $CS_ROOT/components
# Clenaup install dir
rm -rf pwd

$CS_ROOT/cycle_server start 
$CS_ROOT/cycle_server await_startup
$CS_ROOT/cycle_server execute 'update Application.Setting set Value = undefined where Name == "site_id" || Name == "reported_version"'
service cycle_server stop
