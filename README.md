# build
- install docker
- build the terraform installer docker
docker build -t tf-installer -f ./Dockerfile ..

- run installer docker
- -g aws: generate install.tfvars for aws
- -i azure: install into azure
- -f icp4d installer name

# to get usage:
docker run -t tf-installer 
# to generate install.tfvars for azure
docker run -t -v $(pwd):/icp4d_installer --net=host tf-installer -g azure
# to install azure
docker run -t -v $(pwd):/icp4d_installer --net=host tf-installer -i azure -f <installer.x86_64.build>

