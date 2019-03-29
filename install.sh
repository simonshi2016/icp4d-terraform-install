#/bin/bash
set -x
 
INSTALLER_DIR=/icp4d_installer
TERRAFORM_DIR=/terraform

if [ $# -ne 2 ];then
    echo "usage: $0 [-g aws] [-i azure]"
    exit 1
fi

while getopts g:i: arg
do
  case $arg in
    g) generate_conf=1
       cloud=$OPTARG;;
    i) install=1
       cloud=$OPTARG;;
    ?) echo "usage: $0 [-g aws] [-i azure]"
       exit 1
        ;;
  esac
done
shift $(($OPTIND-1)) 

# generate install.tfvars file
if [[ $generate_conf -eq 1 ]];then
    if [[ "$cloud" == "aws"]];then
        cp $TERRAFORM_DIR/terraform-icp-aws/install.conf $INSTALLER_DIR/install.tfvars
    elif [[ "$cloud" == "azure" ]];then
        cp $TERRAFORM_DIR/terraform-icp-azure/icp-ee-as/install.conf $INSTALLER_DIR/install.tfvars
    else
        echo "not yet supported"
        exit 1
    fi
fi

# validate install.tfvars

# extrac icp4d installer -i aws/azure

# upload icp installer

# update install.tfvars for installer location and keys

# run terraform
terraform init
terraform plan -var-file=/icp4d_installer/install.tfvars

# upload icp4d installer and install