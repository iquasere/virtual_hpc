FROM rockylinux:9

RUN yum install https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm -y && \
    yum update -y && \
    yum install -y htop && \
    yum install -y procps && \
    yum install -y net-tools && \
    yum install -y iproute && \
    yum install -y nano && \
    dnf update -y && \
    dnf install -y systemd sudo && \
    dnf clean all

RUN mkdir -p /run/lock

CMD ["/usr/sbin/init"]

EXPOSE 22
