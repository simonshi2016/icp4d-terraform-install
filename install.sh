#!/bin/bash
 
INSTALLER_DIR=/icp4d_installer
TERRAFORM_DIR=/terraform
TERRAFORM_DIR_AWS=$TERRAFORM_DIR/terraform-icp-aws
TERRAFORM_DIR_AZURE=$TERRAFORM_DIR/terraform-icp-azure/templates/icp-ee-as

source /install/resources.sh

# validate install.tfvars
function validate_azure {
    map_start=0
    while read line; do 
        if [[ ! $line =~ ^#.* ]] && [[ ! -z "$line" ]];then
            key=$(echo $line | awk -F= '{print $1}')
            value=$(echo $line | awk -F= '{print $2}')

            if [[ "$value" == "{" ]];then
                map_start=$((map_start+1))
                continue
            fi

            if [[ "$key" == "}" ]];then
                if [[ $map_start -lt 1 ]];then
                    echo "wrong map configuration block"
                    return 1
                fi
                map_start=$((map_start-1))
                continue
            fi

            # to support potential list
            if [[ "${value:0:1}" == '"' ]] && [[ "${value: -1}" == '"' ]];then
                value=${value:1:-1}
            fi

            if [[ "$value" == "" ]];then
                echo "$key is empty"
                return 1
            fi

            case $key in
                location)
                    if [[ ! $value =~ .*\ .* ]];then
                        echo "Wrong azure region format: i.e West US"
                        return 1
                    fi
                    ;;
                ssh_public_key)
                    echo $value > sshkey
                    ssh-keygen -l -f sshkey > /dev/null 2>&1
                    if [[ $? -ne 0 ]];then
                        rm -rf sshkey
                        echo "ssh_public_key is not a valid ssh public key"
                        return 1
                    fi
                    rm -rf sshkey
                    ;;
                subscription_id)
                    subscription_id=$value;;
                tenant_id)
                    tenant_id=$value;;
                aadClientId)
                    client_id=$value;;
                aadClientSecret)
                    client_secret=$value;;
            esac
        fi  
    done < $INSTALLER_DIR/install.tfvars

    if [[ $map_start -ne 0 ]];then
        echo "wrong map configuration block"
        return 1
    fi

    if which az > /dev/null;then
        az login --service-principal -u $client_id -p $client_secret --tenant $tenant_id > /dev/null
        if [[ $? -ne 0 ]];then
            echo "please provide the correct client_id, client_secret and tenant_id"
            return 1
        fi

        az account set --subscription $subscription_id > /dev/null
        if [[ $? -ne 0 ]];then
            echo "please provide the correct subscription ID"
            return 1
        fi

        role=$(az role assignment list --assignee $client_id --query [0].roleDefinitionName -otsv)
        if [[ "$role" != "Contributor" ]];then
            echo "please ensure service principle $client_id used for creating azure resources has 'Contributor' role assigned"
            return 1
        fi

        get_cluster_azure $TERRAFORM_DIR_AZURE/variables.tf $INSTALLER_DIR/install.tfvars
        echo -e "\e[1;34mPlease make sure that your account has enough quota to create the resources, would you like to continue(y|N)?\e[0m"
        read answer
        if [[ "$answer" == "y" ]] || [[ "$answer" == "Y" ]];then
            return 0
        else
            return 1
        fi
    fi
}

function validate_aws {
    map_start=0
    while read line; do 
        if [[ ! $line =~ ^#.* ]] && [[ ! -z "$line" ]];then
            key=$(echo $line | awk -F= '{print $1}')
            value=$(echo $line | awk -F= '{print $2}')

            if [[ "$value" == "{" ]];then
                map_start=$((map_start+1))
                continue
            fi

            if [[ "$key" == "}" ]];then
                if [[ $map_start -lt 1 ]];then
                    echo "wrong map configuration block"
                    return 1
                fi
                map_start=$((map_start-1))
                continue
            fi

            # to support potential list
            if [[ "${value:0:1}" == '"' ]] && [[ "${value: -1}" == '"' ]];then
                value=${value:1:-1}
            fi

            if [[ "$value" == "" ]];then
                echo "$key is empty"
                return 1
            fi

            case $key in
                aws_region)
                    if [[ ! $value =~ .*\-.*\-[0-9] ]];then
                        echo "Wrong aws region format: i.e. us-east-2"
                        return 1
                    fi
                    aws_region=$value;;
                aws_access_key)
                    aws_access_key=$value;;
                aws_secret_key)
                    aws_secret_key=$value;;
                key_name)
                    key_name=$value;;
            esac
        fi  
    done < $INSTALLER_DIR/install.tfvars

    if [[ $map_start -ne 0 ]];then
        echo "wrong map configuration block"
        return 1
    fi

    if which aws > /dev/null;then
        aws configure set aws_access_key_id $aws_access_key
        aws configure set aws_secret_access_key $aws_secret_key
        aws configure set default.region $aws_region

        aws ec2 describe-key-pairs --key-names=$key_name > /dev/null
        if [[ $? -ne 0 ]];then
            return 1
        fi

        checkAwsPermissions
        if [[ $? -ne 0 ]];then
            echo -e "\e[1;34mwould you like to continue(y|N)?\e[0m"
            read answer
            if [[ "$answer" != "y" ]] && [[ "$answer" != "Y" ]];then
                return 1
            fi
        fi

        get_cluster_aws $TERRAFORM_DIR_AWS/variables.tf $INSTALLER_DIR/install.tfvars
        echo -e "\e[1;34mPlease make sure that your account has enough quota to create the resources, would you like to continue(y|N)?\e[0m"
        read answer
        if [[ "$answer" != "y" ]] && [[ "$answer" != "Y" ]];then
            return 1
        fi
    fi
}

function uninstall() {
    if [[ $uninstall -ne 1 ]];then
        return 1
    fi

    if [[ ! -d $INSTALLER_DIR ]];then
        echo "to uninstall, please run: 
        docker run -v $(pwd):/icp4d_installer -it tf-installer -u [aws|azure]"
        return 1
    fi

    if [[ ! -f $INSTALLER_DIR/terraform.tfstate ]] || [[ ! -d $INSTALLER_DIR/.terraform ]];then
        echo "terraform backup information not found, please delete resource from portal manually"
        return 1
    fi

    if [[ ! -f $INSTALLER_DIR/install.tfvars ]];then
        echo "install.tfvars folder is missing, please delete resource from portal manually"
        return 1
    fi

    if [[ "$cloud" == "aws" ]];then
        cd $TERRAFORM_DIR_AWS
        TERRAFORM_DIR=$TERRAFORM_DIR_AWS
    elif [[ "$cloud" == "azure" ]];then
        cd $TERRAFORM_DIR_AZURE
        TERRAFORM_DIR=$TERRAFORM_DIR_AZURE
    else
        echo "cloud $cloud is not supported"
        return 1
    fi

    if [[ ! -d $TERRAFORM_DIR/.terraform ]];then
        cp -r $INSTALLER_DIR/.terraform .
    fi

    cp $INSTALLER_DIR/terraform.tfstate .

    echo "destroying cluster..."
    terraform destroy -var-file=$INSTALLER_DIR/install.tfvars -auto-approve
    if [[ $? -eq 0 ]];then
        rm -rf $INSTALLER_DIR/.terraform
        rm -rf $INSTALLER_DIR/terraform.tfstate
    else
        return $?
    fi
}

function checkAwsPermissions() {
    user_admin=0
    grp_admin=0
    username=$(aws iam list-access-keys --query AccessKeyMetadata[0].UserName --output text)
    user_inline=$(aws iam list-user-policies --user-name $username --query "PolicyNames" --output text)
    user_attached=$(aws iam list-attached-user-policies --user-name $username --query "AttachedPolicies[].PolicyName" --output text)
    for p in ${user_attached[@]};do
        if [[ "$p" == "AdministratorAccess" ]];then
            user_admin=1
            break
        fi
    done
    groups=$(aws iam list-groups-for-user --user-name $username --query 'Groups[].GroupName' --output text)
    declare -a group_inline
    declare -a group_attached

    for g in ${groups[@]};do
        group_inline["$g"]=$(aws iam list-group-policies --group-name $g --query "PolicyNames" --output text)
        group_attached["$g"]=$(aws iam list-attached-group-policies --group-name $g --query "AttachedPolicies[].PolicyName" --output text)
        for p in ${group_attached[@]};do
            if [[ "$p" == "AdministratorAccess" ]];then
                grp_admin=1
                break
            fi
        done
    done

    aws_resources=("EC2Instances"" "EBSVolume" "NetworkInterface" "SecurityGroups" "Route53" "VPC" "ELB" "LBTargetGroups" "EFS" "Subnet" "NATGateway" "InternetGateway" "ElasticIP" "IAMrole" "InstanceProfile" "S3" AutoscalingGroup" "Lambda")
    if [[ $user_admin -ne 1 ]] && [[ $grp_admin -ne 1 ]];then
        echo -e "\e[1;31m\"AdministratorAccess\" policy not found in your current user/group policies:\e[0m"
        echo "user inline policies:"
        echo "$user_inline"
        echo "user attached policies:"
        echo "$user_attached"
        for g in ${groups[@]};do
            echo "group '$g' inline policies:"
            echo "${group_inline["$g"]}"
            echo "group '$g' attached policies:"
            echo "${group_attached["$g"]}"
        done
        
        echo -e "\e[1;34mplease make sure you have enough permission to create the following aws resources:\e[0m"
        echo
        for r in ${aws_resources[@]}; do
            echo $r
        done

        return 1
    fi

    return 0
}

generate_conf=0
install=0
extract=1
accept_license=0
uninstall=0
TERMS_AND_CONDITIONS_URL="http://www14.software.ibm.com/cgi-bin/weblap/lap.pl?la_formnum=&li_formnum=L-KMRY-B2632F&title=IBM+Cloud+Private+for+Data+-+Enterprise+Edition+V1.1.0.1+(bundles+ICP+Foundation)&l=en"

while getopts g:i:f:nau: arg
do
  case $arg in
    g) generate_conf=1
       cloud=$OPTARG;;
    i) install=1
       cloud=$OPTARG;;
    f) installer=$OPTARG;;
    a) accept_license=1;;
    n) extract=0;;
    u) uninstall=1
       cloud=$OPTARG;;
    ?) echo "usage: 
generate install.tfvars file:
    docker run -v \$(pwd):/icp4d_installer tf-installer -g <azure|aws>
to install:
    docker run -v \$(pwd):/icp4d_installer -it tf-installer -i <azure|aws> -f <installer_name> -a
to uninstall:
    docker run -v \$(pwd):/icp4d_installer -it tf-installer -u <azure|aws>"
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
    echo 'installation configuration template file install.tfvars has been generated under current directory,
please enter information and make sure icp4d installer is copied to the current directory, if you install addon modules,
please create modules directory and put modules into it, to start install run the following command:
"docker run -v $(pwd):/icp4d_installer -it tf-installer -i <azure|aws> -f <installer_name> -a"'
    exit 0
fi

if [[ $uninstall -eq 1 ]];then
    uninstall
    exit $?
fi

if [[ $install -ne 1 ]];then
    echo "to accept license ($TERMS_AND_CONDITIONS_URL) and install,run: 
docker run -v $(pwd):/icp4d_installer -it tf-installer -i <azure|aws> -f <installer_name> -a"
    exit 1
fi

if [[ $accept_license -ne 1 ]];then
    echo "Please append -a to accept license, license can be viewed here: $TERMS_AND_CONDITIONS_URL"
    exit 1
fi

if [[ ! -f $INSTALLER_DIR/install.tfvars ]];then
    echo "please provide install.tfvars configuration file, template can be generated by running 
docker run -t -v \$(pwd):$INSTALLER_DIR --net=host tf-installer -g azure"
    exit 0
else
    sed -i '/image_location=/,${d}' $INSTALLER_DIR/install.tfvars
fi

echo "Initializing the enviroment, please wait..."

if [[ "$cloud" == "azure" ]];then
    validate_azure
    if [[ $? -ne 0 ]];then
        echo "azure validation exited"
        exit 1
    fi
elif [[ "$cloud" == "aws" ]];then
    validate_aws
    if [[ $? -ne 0 ]];then
        echo "aws validation exited"
        exit 1
    fi
else
    echo "please specify the cloud with -i <aws|azure>"
    exit 1
fi

if [[ "$installer" == "" ]] || [[ ! -f $INSTALLER_DIR/$installer ]];then
    echo "please provide icp4d installer in the current directory: -f icp_installer_name"
    exit 1
fi

avail=$(df --output=avail -BG $INSTALLER_DIR | grep -v 'Avail' | cut -dG -f1)
if [[ $avail -lt 300 ]];then
    echo "disk space needs to have at least 300G"
    exit 1
fi

# extrac icp4d installer -i aws/azure
if [[ $extract -eq 1 ]];then
    chmod a+x $INSTALLER_DIR/$installer
    cd $INSTALLER_DIR
    ./$installer --extract-only --accept-license
    if [[ $? -ne 0 ]];then
        echo "unable to extract $installer, please make sure $installer file is not corrupted"
        exit 1
    fi
else
    if [[ ! -d $INSTALLER_DIR/InstallPackage ]];then
        echo "please ensure installer has been extracted properly"
        exit 1
    fi
fi

icp_installer_loc=$(ls $INSTALLER_DIR/InstallPackage/ibm-cloud-private-x86_64-*)
if [[ $? -ne 0 ]];then
    echo "icp4d installer was not extracted properly"
    exit 1
fi
icp_filename=$(basename $icp_installer_loc)
icp_version=$(echo $icp_filename|grep -P "\d\.\d\.\d" -o)
inception_image="ibmcom/icp-inception-amd64:${icp_version}-ee"
icp_docker_loc=$(ls $INSTALLER_DIR/InstallPackage/icp-docker-*)
if [[ $? -ne 0 ]];then
    echo "icp4d installer was not extracted properly"
    exit 1
fi

echo "image_location=\"$icp_installer_loc\"" >> $INSTALLER_DIR/install.tfvars
echo "image_location_icp4d=\"$INSTALLER_DIR/$installer\"" >> $INSTALLER_DIR/install.tfvars
echo "icp_inception_image=\"$inception_image\"" >> $INSTALLER_DIR/install.tfvars

if [[ "$cloud" == "aws" ]];then
    echo "docker_package_location=\"$icp_docker_loc\"" >> $INSTALLER_DIR/install.tfvars
    cd $TERRAFORM_DIR_AWS
    TERRAFORM_DIR=$TERRAFORM_DIR_AWS
fi

if [[ "$cloud" == "azure" ]];then
    # needed for rhel only
    echo "image_location_docker=\"$icp_docker_loc\"" >> $INSTALLER_DIR/install.tfvars
    cd $TERRAFORM_DIR_AZURE
    TERRAFORM_DIR=$TERRAFORM_DIR_AZURE
fi

if [[ -d $INSTALLER_DIR/.terraform ]];then
    rm -rf $INSTALLER_DIR/.terraform
fi

if [[ -f $INSTALLER_DIR/terraform.tfstate ]];then
    rm -rf $INSTALLER_DIR/terraform.tfstate
fi

terraform init
terraform apply -var-file=$INSTALLER_DIR/install.tfvars -auto-approve

if [[ -f $TERRAFORM_DIR/terraform.tfstate ]];then
    cp $TERRAFORM_DIR/terraform.tfstate $INSTALLER_DIR
fi

if [[ -d $TERRAFORM_DIR/.terraform ]];then
    cp -r $TERRAFORM_DIR/.terraform $INSTALLER_DIR
fi


