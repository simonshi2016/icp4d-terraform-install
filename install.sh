#!/bin/bash
set -x
 
INSTALLER_DIR=/icp4d_installer
TERRAFORM_DIR=/terraform

if [ $# -lt 1 ];then
    echo "usage: $0 [-g aws] [-i azure] [-f installer_name]"
    exit 1
fi

generate_conf=0
install=0
skipcheck=0
extract=1
while getopts g:i:f:sn arg
do
  case $arg in
    g) generate_conf=1
       cloud=$OPTARG;;
    i) install=1
       cloud=$OPTARG;;
    f) installer=$OPTARG;;
    s) skipcheck=1;;
    n) extract=0;;
    ?) echo "usage: $0 [-g aws] [-i azure] [-f installer_name]"
       exit 1
        ;;
  esac
done
shift $(($OPTIND-1)) 

# generate install.tfvars file
if [[ $generate_conf -eq 1 ]];then
    if [[ "$cloud" == "aws" ]];then
        cp $TERRAFORM_DIR/terraform-icp-aws/install.conf $INSTALLER_DIR/install.tfvars
    elif [[ "$cloud" == "azure" ]];then
        cp $TERRAFORM_DIR/terraform-icp-azure/templates/icp-ee-as/install.conf $INSTALLER_DIR/install.tfvars
    else
        echo "not yet supported"
        exit 1
    fi
    exit 0
fi

if [[ $install -ne 1 ]];then
    exit 1
fi

# validate install.tfvars

# extrac icp4d installer -i aws/azure
if [[ $skipcheck -ne 1 ]];then
    avail=$(df --output=avail -BG $INSTALLER_DIR | grep -v 'Avail' | cut -dG -f1)
    if [[ $avail -lt 150 ]];then
        echo "disk space needs to have at least 150G"
        exit 1
    fi
fi

if [[ $extract -eq 1 ]];then
    chmod a+x $INSTALLER_DIR/$installer
    cd $INSTALLER_DIR
    ./$installer --extract-only --accept-license
fi

icp_installer_loc=$(ls $INSTALLER_DIR/InstallPackage/ibm-cloud-private-x86_64-*)
icp_filename=$(basename $icp_installer_loc)
icp_version=$(echo $icp_filename|grep -P "\d\.\d\.\d" -o)
inception_image="ibmcom/icp-inception-amd64:${icp_version}-ee"

echo "image_location=\"$icp_installer_loc\"" >> $INSTALLER_DIR/install.tfvars
echo "image_location_icp4d=\"$INSTALLER_DIR/$installer\"" >> $INSTALLER_DIR/install.tfvars
echo "icp_inception_image=\"$inception_image\"" >> $INSTALLER_DIR/install.tfvars

# run terraform, upload icp installer
cd /terraform/terraform-icp-azure/templates/icp-ee-as
terraform init
terraform apply -var-file=/$INSTALLER_DIR/install.tfvars -auto-approve
