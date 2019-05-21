FROM ubuntu:18.04
RUN apt-get update -y && \
DEBIAN_FRONTEND=noninteractive apt-get install \
        iputils-ping \
        openssh-client \
        expect \
        openssl \
        sshpass \
        rsync \
        vim \
        wget \
        software-properties-common python3-pip -y && \
        pip3 install netaddr && \
        apt-get install -y nmap psmisc
COPY ./icp4d-terraform-install/install_az.sh /install/install_az.sh
COPY ./icp4d-terraform-install/install_aws.sh /install/install_aws.sh
COPY ./icp4d-terraform-install/resources.sh /install/resources.sh
RUN chmod a+x /install/install_az.sh 
RUN chmod a+x /install/install_aws.sh
RUN /install/install_az.sh
RUN /install/install_aws.sh
COPY ./icp4d-terraform-install/terraform/terraform /usr/bin
COPY ./terraform-module-icp-deploy /terraform/terraform-module-icp-deploy
COPY ./terraform-icp-azure /terraform/terraform-icp-azure
COPY ./terraform-icp-aws /terraform/terraform-icp-aws
WORKDIR /terraform/terraform-icp-azure/templates/icp-ee-as
RUN terraform init
WORKDIR /terraform/terraform-icp-aws
RUN terraform init
COPY ./icp4d-terraform-install/install.sh /install/install.sh
RUN echo y | ssh-keygen -f ~/.ssh/id_rsa -q -N "" 
WORKDIR /install
RUN chmod a+x /install/install.sh
ENTRYPOINT ["/install/install.sh"]
