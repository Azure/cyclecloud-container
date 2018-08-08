#!/bin/bash
set -x

for filename in cyclecloud*amd64.deb; do
    apt install ./${filename}
done

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

# Update properties

sed -i 's/webServerMaxHeapSize\=2048M/webServerMaxHeapSize\=4096M/' $CS_ROOT/config/cycle_server.properties
sed -i 's/webServerPort\=8080/webServerPort\=80/' $CS_ROOT/config/cycle_server.properties
sed -i 's/webServerSslPort\=8443/webServerSslPort\=443/' $CS_ROOT/config/cycle_server.properties
sed -i 's/webServerEnableHttps\=false/webServerEnableHttps=true/' $CS_ROOT/config/cycle_server.properties

ls -l $CS_ROOT/components
# Clenaup install dir
rm -rf pwd
