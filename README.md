# CycleCloud container distribution

---
## Prerequisites

A CycleCloud linux `deb` package is required to build a container image.  This can
be downloaded from the official AzureCycleCloud 
[download center page](https://www.microsoft.com/en-us/download/details.aspx?id=57182).

Once downloaded, copy the `deb` package to the top level of this project.

## Build

No special arguments are needed to build the docker image.  At the top level of
this project, run:

    docker build . -t myrepo/cyclecloud:$ver

### Customization

The build process can utilize custom:

  - Custom CycleCloud components by adding them to a `./components` directory.
  - Custom CycleCloud records by adding them to a `./records` directory.

The image build process will configure the installation with these resources
included. 

To build a customized AzureCycleCloud container image:

1. Download the CycleCloud installer from the Azure download site, place in top
   level project directory
2. Add any custom records to a `./records` directory.
3. Add any custom components to a `./components` directory.
4. Build the container image.

### Runtime

#### Notice
_If the CycleCloud service fails the container process will terminate and all 
cluster data will be lost. No persistent storage options are currently available in this project._

The container runs the web application available for http (80) and http (8443). 
Since CycleCloud is running a JVM, the HeapSize of the JVM and the
memory allocated to the container should be coordinate.  We recommend setting
HeapSize to 1/2 the container memory allocation.  This can be done with the
`docker run -m` flag and an environment variable `JAVA_HEAP_SIZE` specified in
`MB`.

    docker run -m 2G -e "JAVA_HEAP_SIZE=1024" -p 8080:80 -p 8443:443 myrepo/cyclecloud:$ver

### Supported versions

Supported versions can be found in the product [dockerhub page](https://hub.docker.com/r/microsoft/azure-cyclecloud/). 
The image can be launched as an Azure Container instance (using
existing resource group, location and preferred container and dns names). We
have SSL certificate generation included so if you specify the arguments twice,
once for az cli and again to set environment variables, then the container is
able to establish valid SSL certificates, automatically. 

```bash
#!/bin/bash
ResourceGroup="rg-name"
Location="westus2"
CIName="ci-name"
CIDNSName="ci-name"

az container create -g ${ResourceGroup} --location ${Location} \
  --name ${CIName} --dns-name-label ${CIDNSName} \
  --image mcr.microsoft.com/hpc/azure-cyclecloud \
  --ip-address public --ports 80 443 \
  --cpu 2 --memory 4 \
  -e JAVA_HEAP_SIZE=2048
```

This command will launch the container and the cyclecloud UI will be available
at: `https://${CIDNSName}.${Location}.azurecontainer.io`.

You can optionally add an additional environment variable for the 
fully qualified domain name, in which case CycleCloud will try to 
create valid SSL certificates:

```bash
FQDN="https://${CIDNSName}.${Location}.azurecontainer.io"
...
-e JAVA_HEAP_SIZE=2048 FQDN=${FQDN} 
```

### Recover the SSH keypair

CycleCloud creates a keypair to be used for administrative access to nodes.  This keypair will be printed to the stdout of the container image and should be retained.  In the Azure Container Instance this is in the _Container_ menu under the _Logs_ tab.

A unique ssh keypair for the container appear in the standard output of
the container process.  As the message indicates, retain this keypair for
admin access to the CycleCloud clusters.

```
Private Key for admin access to nodes.  Retain for cyclecloud cli and ssh access.
-----BEGIN RSA PRIVATE KEY-----
MIIJKAIBAAKCAgEAhdhrHdfirGEEsps2R+EZP5Zq/2TLA/JQPNYwFtcTvA0cJ3O0
wRR/U8HdDswFpAvj2T00ptQqWFb7prMB1/5ualKFjYkJ/7Azxx13F+qWh3z14dDq
xwUPhQleZ9XPaIAYDew5eGibxuaFbkXmmxWsacW1K9hXFwXnq58Rs23Q/x4/xw08
FDcIvh7FjR6h13zOj6He0sRW7z0myRgj88nPziiWYB5pm9jykHnNUWiYwYssSuDX
...
IfDYB4iMRwKiJdXIs773U6JtuoRWj5IbcIjxdK6YzayyTZJJw3ejEWl2F6aSrMvs
W7d1HjlAz0LMqNLV3XLTThXXxK5dOBbExDYvE2KQe/6Wf9ZSfLAr8BcZe+PXPESX
mVa3tFI9HfSz2qjsB1YLRfZYiMR+BzCI9uOyu9bIu2VLUX1fjgIDJ6XYtcOQAJP0
6y5HC9t1sZuhiaYHQvkh0YUTLZejch4BCzd9EknsccHxEjU+Fbf8CVjm1ZU=
-----END RSA PRIVATE KEY-----
```

### Autoconfig
To bring up an Azure CycleCloud container with a user pre-created, add the
following environment variables to the docker run command:

    $ docker run -m 4G -p 80:80 -p 443:443 \
    -e "JAVA_HEAP_SIZE=2048" \
    -e CYCLECLOUD_AUTOCONFIG=true \
    -e CYCLECLOUD_USERNAME=$YOUR-USER-NAME \
    -e CYCLECLOUD_PASSWORD=$PASSWORD \
    -e CYCLECLOUD_USER_PUB_KEY=$SSH_PUBLIC_KEY
    mcr.microsoft.com/hpc/azure-cyclecloud 
    ```

With this, all clusters nodes started will have this user created and the SSH
public key staged in their authorized_keys file. You can also login to the
CycleCloud web interface using the username and password as credentials.