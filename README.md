# build
- install docker
- build the terraform installer docker
docker build -t installer .
- run installer docker
./run_install.sh <AZURE_CLIENT_ID> <AZURE_CLIENT_SECRET> <AZURE_SUBSCRIPTION_ID> <AZURE_TENENT_ID>
