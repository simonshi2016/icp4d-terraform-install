function get_string_default_value(){
    local variable_file=$1
    local key=$2

    local default_value=$(sed -n '/variable "'"$key"'"/{:start /\}/!{N;b start};p}' $variable_file | grep -P "default\s*=" | awk -F= '{print $2}' | awk '{$1=$1;print}')
    
    if [[ "${default_value:0:1}" == '"' ]];then
        default_value=$(echo $default_value | awk -F\" '{print $2}')
    fi
    echo $default_value
}

function get_string_value(){
    local variable_file=$1
    local install_file=$2
    local key=$3
    
    local default_value=$(get_string_default_value $variable_file $key)

    local value=$(grep -P "^$key\s*=" $install_file)
    if [[ $? -eq 0 ]];then
        value=$(echo $value | awk -F= '{print $2}' | awk '{$1=$1;print}')
        if [[ "${value:0:1}" == '"' ]];then
            value=$(echo $value | awk -F\" '{print $2}')
        fi
    fi

    value=${value:-$default_value}
    echo $value
}

function get_list_default_values() {
    local variable_file=$1
    local key=$2

    local default_value=$(sed -n '/variable "'"$key"'"/{:start /\}/!{N;b start};p}' $variable_file | grep -P "default\s*=" | awk -F= '{print $2}' | awk '{$1=$1;print}')
    
    if [[ "${default_value:0:1}" == '[' ]];then
        default_value=$(echo $default_value | awk -F"[" '{print $2}' | awk -F"]" '{print $1}' | tr ',' ' ')
    fi

    echo $default_value
}

function get_list_values() {
    local variable_file=$1
    local install_file=$2
    local key=$3
    
    local default_value=$(get_list_default_values $variable_file $key)
    local value=$(grep -P "^$key\s*=" $install_file)
    if [[ $? -eq 0 ]];then
        value=$(echo $value | awk -F= '{print $2}' | awk '{$1=$1;print}')
        if [[ "${value:0:1}" == '[' ]];then
            value=$(echo $value | awk -F"[" '{print $2}' | awk -F"]" '{print $1}' | tr ',' ' ')
        fi
    fi
    value=${value:-$default_value}
    echo $value
}

function get_map_default_values() {
    local variable_file_content=$1
    local map_var=$2
    shift 2
    local map_keys=($@)
    local var_start=0
    local map_start=0
    map_values_default=()

    while read line; do
        if [[ "$line" =~ ^#.* ]] || [[ -z "$line" ]];then
            continue
        fi

        key=$(echo "$line" | awk -F= '{print $1}' | awk '{$1=$1;print}')
        value=$(echo "$line" | awk -F= '{print $2}' | awk '{$1=$1;print}')

        if [[ $var_start -eq 0 ]] && ! echo $key | grep -P "variable\s+\"$map_var\"\s+\{" > /dev/null 2>&1;then
            continue
        fi

        if echo $key | grep -P "variable\s+\"$map_var\"\s+\{" > /dev/null 2>&1;then
            var_start=$((var_start+1))
            continue
        fi

        if [[ $map_start -eq 0 ]] && [[ "$key" != "}" ]] && [[ "$key" != "default" ]];then
            continue
        fi

        if [[ "$key" == "default" ]] && [[ "$value" == "{" ]];then
            map_start=$((map_start+1))
            continue
        fi

        if [[ "$key" == "}" ]];then
            if [[ $map_start -eq 0 ]];then
                var_start=$((var_start-1))
                if [[ $var_start -eq 0 ]];then
                    return 0
                fi
            else
                map_start=$((map_start-1))
                continue
            fi
        elif echo $key | grep -P "variable\s+\"";then
            echo "map block not properly closed"
            return 1
        fi

        #if [[ "${value:0:1}" == '"' ]] && [[ "${value: -1}" == '"' ]];then
        if [[ "${value:0:1}" == '"' ]];then
            value=$(echo $value | awk -F\" '{print $2}')
        fi

        for i in ${!map_keys[@]};do
            if [[ "$key" == "${map_keys[$i]}" ]];then
                map_values_default[$i]=$value
                break
            fi
        done
    done <<< "$variable_file_content"
}

function get_map_install_values() {
    local install_file_content=$1
    local map_var=$2
    shift 2
    local map_keys=($@)
    local map_start=0
    local count=0
    map_values=()

    while read line;do
        if [[ "$line" =~ ^#.* ]] || [[ -z "$line" ]];then
            continue
        fi

        key=$(echo "$line" | awk -F= '{print $1}' | awk '{$1=$1;print}')
        value=$(echo "$line" | awk -F= '{print $2}' | awk '{$1=$1;print}')

        if [[ $map_start -eq 0 ]] && [[ "$key" != "$map_var" ]];then
            continue
        fi

        if [[ "$key" == "$map_var" ]] && [[ "$value" == "{" ]];then
            map_start=$((map_start+1))
            continue
        fi

        if [[ "$key" == "}" ]];then
            if [[ $map_start -lt 1 ]];then
                echo "wrong map configuration block"
                exit 1
            fi
            map_start=$((map_start-1))
            if [[ $map_start -eq 0 ]];then
                return 0
            fi
            continue
        fi

        if [[ "${value:0:1}" == '"' ]];then
            value=$(echo $value | awk -F\" '{print $2}')
        fi

        for i in ${!map_keys[@]};do
            if [[ "$key" == "${map_keys[$i]}" ]];then
                map_values[$i]=$value
                break
            fi
        done
    done <<< "$install_file_content"

}

function get_map_values() {
    local variable_file_content=$1
    local install_file_content=$2
    shift 2
    get_map_default_values "$variable_file_content" $@
    get_map_install_values "$install_file_content" $@

    local map_keys=($@)
    for i in ${!map_keys[@]};do
        local value=${map_values[$i]}
        local default=${map_values_default[$i]}
        map_values[$i]=${value:-$default}
    done
}

function get_cluster_aws() {
    declare -A cluster_vm
    local variable_file=$1
    local install_file=$2
    local variable_file_content=$(cat $variable_file)
    local install_file_content=$(cat $install_file)
    
    get_map_values "$variable_file_content" "$install_file_content" worker nodes

    local worker_nodes=${map_values[0]:-0}
    local volumes=0
    for n in bastion master worker proxy;do
        get_map_values "$variable_file_content" "$install_file_content" $n nodes type disk docker_vol ibm_vol data_vol
        nodes=${map_values[0]:-0}
        vm_type=${map_values[1]}
        disk=${map_values[2]:-0}
        docker_vol=${map_values[3]:-0}
        ibm_vol=${map_values[4]:-0}
        data_vol=${map_values[5]:-0}
        if [[ "$n" == "master" ]] && [[ $worker_nodes -ne 0 ]];then
            data_vol=0
        fi
        
        if [[ "$vm_type" != "" ]];then
           cluster_vm[$vm_type]=$((${cluster_vm[$vm_type]:-0}+$nodes))
        fi
        vol_per_node=$((disk+docker_vol+ibm_vol+data_vol))
        volumes=$((volumes+vol_per_node*nodes))
    done

    echo "The following number of resources will be created:"
    echo "Instances:"
    Num_Instances=0
    for k in ${!cluster_vm[@]};do
        if [[ ${cluster_vm[$k]} -gt 0 ]];then
            echo "  $k: ${cluster_vm[$k]}"
            Num_Instances=$((Num_Instances+${cluster_vm[$k]}))
        fi
    done

    echo "EBS Volumes: $volumes G"

    Num_EFS=2
    icp4d_storage_efs=$(get_string_value $variable_file $install_file icp4d_storage_efs)
    if [[ $icp4d_storage_efs -eq 1 ]];then
        Num_EFS=$((Num_EFS+1))
    fi
    echo "EFS: $Num_EFS"
    
    av_zones=($(get_list_values $variable_file $install_file azs))
    Num_Zones=${#av_zones[@]}

    Num_IamInstanceProfile=1
    Num_IamRole=1
    Num_IamRolePolicy=1
    echo "IAM Instance Profile: $Num_IamInstanceProfile"
    echo "  Role: $Num_IamRole"
    echo "  Role Policy: $Num_IamRolePolicy"

    Num_ELB=2
    Num_ElbListener=9
    Num_ElbTargetGroup=$Num_ElbListener
    echo "ELB: $Num_ELB"
    echo "  Listener: $Num_ElbListener"
    echo "  Target Groups: $Num_ElbListener"

    Num_VPC=1
    Num_NGW=$Num_Zones
    Num_IGW=1
    Num_Route=1
    Num_RouteTable=$((Num_Zones+Num_IGW))
    Num_Subnet=$((Num_Zones+Num_NGW))
    Num_NIC=$((Num_EFS*Num_Zones+Num_ELB*Num_Zones+Num_Instances))
    Num_SG=5

    echo "VPC: $Num_VPC"
    echo "  Route: $Num_Route"
    echo "  Route Tables: $Num_RouteTable"
    echo "  Endpoints: 2"
    echo "  Elastic IPs: $Num_Zones"
    echo "  NAT Gateways: $Num_Zones"
    echo "  Internet Gateways: $Num_IGW" 
    echo "  Subnets: $Num_Subnet"
    echo "  Network Interfaces: $Num_NIC"
    echo "  Security Groups: $Num_SG"

    Num_Route53=1
    echo "Route 53 Zones: $Num_Route53"

    Num_S3Bucket=3
    echo "S3 Bucket: $Num_S3Bucket"
}

function get_cluster_azure() {
    declare -A cluster_vm
    local variable_file=$1
    local install_file=$2
    local variable_file_content=$(cat $variable_file)
    local install_file_content=$(cat $install_file)
    
    get_map_values "$variable_file_content" "$install_file_content" worker nodes
    local worker_nodes=${map_values[0]:-0}

    declare -A volumes
    for n in boot master worker proxy;do
        keys=(nodes vm_size \
              os_disk_type os_disk_size docker_disk_type docker_disk_size etcd_data_type etcd_data_size etcd_wal_type etcd_wal_size \
              ibm_disk_type ibm_disk_size data_disk_type data_disk_size)
        get_map_values "$variable_file_content" "$install_file_content" $n ${keys[@]}
        nodes=${map_values[0]:-0}
        vm_type=${map_values[1]}
        if [[ "$vm_type" != "" ]];then
           cluster_vm[$vm_type]=$((${cluster_vm[$vm_type]:-0}+$nodes))
        fi
        NumDisks=6
        for ((i=2;i<2+NumDisks*2;i+=2));do
            disk_type=${map_values[$i]}
            disk_size=${map_values[$((i+1))]:-0}
            disk_size=$((disk_size*nodes))
            if [[ "$n" == "master" ]] && [[ $worker_nodes -ne 0 ]] && [[ "${keys[$i]}" == "data_disk_type" ]];then
                disk_size=0
            fi

            if [[ "$disk_type" != "" ]];then
                volumes[$disk_type]=$((volumes[$disk_type]+$disk_size))
            fi
        done
    done

    echo "The following number of resources will be created:"
    Num_ResourceGroup=1
    echo "Resource Group:  1"

    echo "Instances:"
    Num_Instances=0
    for k in ${!cluster_vm[@]};do
        if [[ ${cluster_vm[$k]} -gt 0 ]];then
            echo "  $k: ${cluster_vm[$k]}"
            Num_Instances=$((Num_Instances+${cluster_vm[$k]}))
        fi
    done

    echo "Disks:"
    for k in ${!volumes[@]};do
        if [[ ${volumes[$k]} -gt 0 ]];then
            echo "  $k: ${volumes[$k]}G"
        fi
    done

    Num_AS=4
    echo "Availability Sets:  $Num_AS"

    Num_LB=1
    Num_BackendPool=2
    echo "Load Balancer:  $Num_LB"
    echo "  LB Backend Address Pool:  $Num_BackendPool"

    Num_Ports=0
    ports=($(get_list_values $variable_file $install_file master_lb_ports))
    Num_Ports=${#ports[@]}
    ports=($(get_list_values $variable_file $install_file master_lb_additional_ports))
    Num_Ports=$((Num_Ports+${#ports[@]}))
    ports=($(get_list_values $variable_file $install_file proxy_lb_ports))
    Num_Ports=$((Num_Ports+${#ports[@]}))
    ports=($(get_list_values $variable_file $install_file proxy_lb_additional_ports))
    Num_Ports=$((Num_Ports+${#ports[@]}))
    ports=($(get_list_values $variable_file $install_file master_lb_ports_udp))
    Num_Ports=$((Num_Ports+${#ports[@]}))
    echo "  LB Rules:  $Num_Ports"

    Num_VNet=1
    echo "Virtual Network:  $Num_VNet"
    Num_RouteTable=1
    echo "  Route Table:  $Num_RouteTable"
    Num_Subnets=2
    echo "  Subnets:  $Num_Subnets"
    Num_NIC=$Num_Instances
    echo "  Network Interfaces:  $Num_NIC"
    Num_SG=
    Num_PIP=$((Num_LB+1))
    echo "  Public IPs: $Num_PIP"
    Num_StorageAccount=2
    echo "Storage Account:  $Num_StorageAccount"
}
