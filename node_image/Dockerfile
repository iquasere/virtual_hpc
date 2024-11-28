FROM rockylinux:9

RUN dnf update -y && \
    dnf install -y systemd sudo && \
    dnf clean all

RUN mkdir -p /run/lock

CMD ["/usr/sbin/init"]

EXPOSE 22
