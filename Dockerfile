#syntax=docker/dockerfile:1
FROM mcr.microsoft.com/mirror/docker/library/ubuntu:24.04

WORKDIR /cs-install

ENV CS_UID=1169
ENV CS_GID=1169
ENV CS_ROOT=/opt/cycle_server

ARG DEBIAN_FRONTEND=noninteractive
ARG REPO_STREAM=stable

# Download azcopy and JMX Prometheus agent
ADD https://aka.ms/downloadazcopy-v10-linux /tmp/azcopy_linux.tar.gz
ADD --checksum=sha256:7d61f737fd661610ccc14aea79764faa1ea94a340cbc8f0029b3d2edea3d80c1 \
    https://repo1.maven.org/maven2/io/prometheus/jmx/jmx_prometheus_javaagent/1.0.1/jmx_prometheus_javaagent-1.0.1.jar \
    /cs-install/jmx_prometheus_javaagent-1.0.1.jar

# Update system and install base dependencies
RUN apt clean \
    && apt update -y \
    && apt upgrade -y \
    && apt install -y apt-utils openjdk-8-jre-headless less vim wget gnupg2 unzip libncurses-dev ca-certificates curl apt-transport-https lsb-release python3

# Configure Microsoft repositories for Azure CLI and CycleCloud
RUN wget -qO - https://packages.microsoft.com/keys/microsoft.asc | apt-key add - \
    && echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ $(lsb_release -cs) main" > /etc/apt/sources.list.d/azure-cli.list \
    && apt update -y \
    && apt install -y azure-cli

# Extract azcopy and install it
RUN tar xzf /tmp/azcopy_linux.tar.gz -C /tmp/ \
    && mv /tmp/azcopy_linux*/azcopy /usr/local/bin/azcopy \
    && rm -rf /tmp/azcopy_linux*

# Configure CycleCloud repository and install python3-venv
RUN echo "deb https://packages.microsoft.com/repos/cyclecloud ${REPO_STREAM} main" > /etc/apt/sources.list.d/cyclecloud.list \
    && apt install -y python3-venv \
    && update-alternatives --install /usr/bin/python python /usr/bin/python3 1 \
    && apt update -y

# Create cycle_server user and group BEFORE installing cyclecloud8
RUN groupadd -g ${CS_GID} cycle_server \
    && useradd -u ${CS_UID} -g ${CS_GID} -m -d /opt/cycle_server cycle_server

# Install CycleCloud 8
RUN apt install -y cyclecloud8

# Initialize and purge sensitive data
RUN ${CS_ROOT}/cycle_server start \
    && ${CS_ROOT}/cycle_server await_startup \
    && ${CS_ROOT}/cycle_server execute 'purge where AdType in { "AuthenticatedUser", "Credential", "AuthenticatedSession", "Application.Task", "Cloud.ChefNodeData", "Event", "ClusterEvent", "NodeEvent", "ClusterMetrics", "NodeMetrics", "Application.FileStore", "Application.Insight", "StorageSetting", "SystemAspect", "Application.Tunnel" }' \
    && ${CS_ROOT}/cycle_server stop \
    && rm -f ${CS_ROOT}/.ssh/* \
    && rm -f ${CS_ROOT}/logs/*

# Update CycleCloud configuration
RUN sed -i 's/webServerMaxHeapSize=2048M/webServerMaxHeapSize=4096M/' ${CS_ROOT}/config/cycle_server.properties \
    && sed -i 's/webServerEnableHttps=false/webServerEnableHttps=true/' ${CS_ROOT}/config/cycle_server.properties

# Install CycleCloud CLI system-wide
RUN cd /tmp \
    && unzip ${CS_ROOT}/tools/cyclecloud-cli.zip \
    && cd /tmp/cyclecloud-cli-installer \
    && ./install.sh --system \
    && rm -rf /tmp/cyclecloud-cli-installer

# Stash a copy of the cycle_server data and work directories for persistent volume initialization
RUN echo "Stashing a copy of the cycle_server data and work directories..." \
    && mkdir -p /opt_cycle_server/ \
    && cp -a ${CS_ROOT}/data /opt_cycle_server/ \
    && cp -a ${CS_ROOT}/work /opt_cycle_server/ \
    && chown -R cycle_server:cycle_server /opt_cycle_server

# Copy scripts into the container
ADD ./scripts /cs-install/scripts
RUN chmod +x /cs-install/scripts/run_cyclecloud.sh \
    && chmod +x /cs-install/scripts/cyclecloud_account.py \
    && chown -R cycle_server:cycle_server /cs-install

# Run as unprivileged cycle_server user (UID 1169)
USER cycle_server

# Set entrypoint to the run script
ENTRYPOINT ["/cs-install/scripts/run_cyclecloud.sh"]
