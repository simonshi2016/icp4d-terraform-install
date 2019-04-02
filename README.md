# build
- install docker
- build the terraform installer docker
docker build -t tf-installer -f ./Dockerfile ..

- run installer docker
- -g aws: generate install.tfvars for aws
- -i azure: install into azure
- -f icp4d installer name
./run_install.sh [-g aws] [-i azure] [-f installer_name]

