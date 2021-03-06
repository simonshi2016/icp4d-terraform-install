#! /bin/bash

echo "Installing az.."
apt-get install apt-transport-https lsb-release software-properties-common dirmngr libunwind-dev -y

AZ_REPO=$(lsb_release -cs)
echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ $AZ_REPO main" | \
    tee /etc/apt/sources.list.d/azure-cli.list

apt-key --keyring /etc/apt/trusted.gpg.d/Microsoft.gpg adv \
     --keyserver packages.microsoft.com \
     --recv-keys BC528686B50D79E339D3721CEB3E94ADBE1229CF
apt-get update
apt-get install azure-cli

echo "Installing AzCopy.."
cd /tmp
wget -O azcopy.tar.gz https://aka.ms/downloadazcopylinux64
tar -xf azcopy.tar.gz
./install.sh > /tmp/azcopy_install.log
