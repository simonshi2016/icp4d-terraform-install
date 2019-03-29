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
        software-properties-common python3-pip -y && \
        pip3 install netaddr && \
        apt-get install -y nmap psmisc
COPY ./install_az.sh /install_az.sh
RUN chmod a+x /install_az.sh 
RUN /install_az.sh
COPY terraform/terraform /usr/bin
COPY ../terraform-icp-azure /terraform/terraform-icp-azure
COPY ../terraform-icp-aws /terraform/terraform-icp-aws
COPY ../terraform-module-icp-deploy /terraform/terraform-module-icp-deploy
COPY install.sh /install.sh
RUN echo y | ssh-keygen -f ~/.ssh/id_rsa -q -N "" 
RUN chmod a+x run.sh
ENTRYPOINT ["/bin/bash","/install.sh"]
