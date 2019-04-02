#/bin/bash
set -x
 
INSTALLER_DIR=/icp4d_installer
TERRAFORM_DIR=/terraform

if [ $# -ne 3 ];then
    echo "usage: $0 [-g aws] [-i azure] [-f installer_name]"
    exit 1
fi

while getopts g:i:f: arg
do
  case $arg in
    g) generate_conf=1
       cloud=$OPTARG;;
    i) install=1
       cloud=$OPTARG;;
    f) installer=$OPTARG;;
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
avail=$(df --output=avail -BG ./ | grep -v 'Avail' | cut -dG -f1)
if [[ $avail -lt 150 ]];then
    echo "disk space needs to have at least 150G"
    exit 1
fi

$INSTALLER_DIR/$installer --extract-only --accept-license

icp_installer_loc=$(ls $INSTALLER_DIR/InstallPackage/ibm-cloud-private-x86_64-*)

echo "image_location=$icp_installer_loc" >> $INSTALLER_DIR/install.tfvars
echo "image_location_icp4d=$INSTALLER_DIR/$installer" >> $INSTALLER_DIR/install.tfvars

# run terraform, upload icp installer
terraform init
terraform apply -var-file=/$INSTALLER_DIR/install.tfvars -auto-approve
