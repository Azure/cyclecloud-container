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

Similarly the image can be launched as an Azure Container instance (using
existing resource group, location and preferred container and dns names). We
have SSL certificate generation included so if you specify the arguments twice,
once for az cli and again to set environment variables, then the container is
able to establish valid SSL certificates, automatically.  

```
#!/bin/bash
ResourceGroup="rg-name"
Location="westus2"
CIName="ci-name"
CIDNSName="ci-name"
FQDN="https://${CIDNSName}.${Location}.azurecontainer.io"

az container create -g ${ResourceGroup} --location ${Location} \
  --name ${CIName} --dns-name-label ${CIDNSName} \
  --image mvrequa/cc-beta:latest \
  --ip-address public --ports 80 443 \
  --cpu 2 --memory 4 \
  -e JAVA_HEAP_SIZE=2048 FQDN=${FQDN} 
```

This command will launch the container and the cyclecloud UI will be available
at: `https://${CIDNSName}.${Location}.azurecontainer.io`.

### Recover the SSH keypair

CycleCloud creates a keypair to be used for administrative access to nodes.  This keypair will be printed to the stdout of the container image and should be retained.  In the Azure Container Instance this is in the _Container_ menu under the _Logs_ tab.

### Autoconfig
To bring up an Azure CycleCloud container with a user pre-created, add the
following environment variables to the docker run command:

    $ docker run -m 4G -p 80:80 -p 443:443 \
    -e "JAVA_HEAP_SIZE=2048" \
    -e CYCLECLOUD_AUTOCONFIG=true \
    -e CYCLECLOUD_USERNAME=$YOUR-USER-NAME \
    -e CYCLECLOUD_PASSWORD=$PASSWORD \
    -e CYCLECLOUD_USER_PUB_KEY=$SSH_PUBLIC_KEY
    myrepo/cyclecloud:$ver 
    ```

With this, all clusters nodes started will have this user created and the SSH
public key staged in their authorized_keys file. You can also login to the
CycleCloud web interface using the username and password as credentials.