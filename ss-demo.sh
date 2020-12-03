#!/bin/sh
# Script to run through the scale set demo
# https://docs.microsoft.com/en-us/azure/virtual-machine-scale-sets/tutorial-use-custom-image-cli

export LANG=C
export LC_ALL=C

set -ex

do_deps() {
    if ! az --version
    then
      if test -d /Library
      then
        brew install azure-cli
      else
        sudo apt-get update
        sudo apt-get install ca-certificates curl apt-transport-https lsb-release gnupg
        curl -sL https://packages.microsoft.com/keys/microsoft.asc |
            gpg --dearmor |
            sudo tee /etc/apt/trusted.gpg.d/microsoft.gpg > /dev/null
        AZ_REPO=$(lsb_release -cs)
        echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ $AZ_REPO main" |
        sudo tee /etc/apt/sources.list.d/azure-cli.list
        sudo apt-get update
        sudo apt-get install azure-cli
      fi
      az login
    fi

    if ! jq --version
    then
      if test -d /Library
      then
        brew install jq
      else
        sudo apt-get update
        sudo apt-get install -y jq
      fi
    fi
}

do_src() {
    az group create --name myResourceGroup --location eastus

    az vm create \
      --resource-group myResourceGroup \
      --name myVM \
      --image ubuntults \
      --admin-username azureuser \
      --generate-ssh-keys

    ip=$(az vm show -d -g myResourceGroup -n myVM --query publicIps -o tsv)
    sleep 5
    ssh -o StrictHostKeyChecking=no azureuser@$ip sudo apt install -y nginx
}

do_gallery_mk() {
    az group create --name myGalleryRG --location eastus
    az sig create --resource-group myGalleryRG --gallery-name myGallery
}

do_iv_mk() {
    az sig image-definition create \
       --resource-group myGalleryRG \
       --gallery-name myGallery \
       --gallery-image-definition myImageDefinition \
       --publisher myPublisher \
       --offer myOffer \
       --sku mySKU \
       --os-type Linux \
       --os-state specialized

    az vm get-instance-view -g myResourceGroup -n myVM --query id 

    VMID=$(az vm get-instance-view -g myResourceGroup -n myVM --query id | tr -d '"')
    az sig image-version create \
        --resource-group myGalleryRG \
        --gallery-name myGallery \
        --gallery-image-definition myImageDefinition \
        --gallery-image-version 1.0.0 \
        --target-regions "southcentralus=1" "eastus=1" \
        --managed-image $VMID
}

do_ss_mk() {
    IDID=$(az sig image-definition list --resource-group myGalleryRG --gallery-name myGallery | jq '.[0].id' | tr -d '"' )
    az vmss create \
       --resource-group myResourceGroup \
       --name myScaleSet \
       --image $IDID
       --specialized
}

do_delete() {
    set +e
    az sig image-version delete \
      --resource-group myGalleryRG \
      --gallery-name myGallery \
      --gallery-image-definition myImageDefinition \
      --gallery-image-version 1.0.0
    az sig image-definition delete \
      --resource-group myGalleryRG \
      --gallery-name myGallery \
      --gallery-image-definition myImageDefinition
    az sig delete --resource-group myGalleryRG --gallery-name myGallery
    az vm delete \
      --yes \
      --resource-group myResourceGroup \
      --name myVM
    az vm delete \
      --yes \
      --resource-group myResourceGroup \
      --name myVM
    az group delete \
      --yes \
      --name myResourceGroup
}

usage() {
  echo "Usage: sh azdemo.sh cmd"
  echo "e.g.   sh azdemo.sh all    (does everything but delete)"
  echo "cmds: all deps src gallery-mk iv-mk ss-mk delete"
}

case "$1" in
help|-h|--help) usage;;
deps) do_deps;;
src) do_src;;
gallery-mk) do_gallery_mk;;
iv-mk) do_iv_mk;;
ss-mk) do_ss_mk;;
delete) do_delete;;
all) do_deps && do_src && do_gallery_mk && do_iv_mk && do_ss_mk;;
*) echo "bad cmd $1"; usage; exit 1;;
esac
