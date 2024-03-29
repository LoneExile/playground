FROM ubuntu:22.04 as builder

RUN apt-get update && apt-get install -y openssh-server dnsutils telnet inetutils-ping

RUN useradd -rm -d /home/sftp_user -s /bin/bash -G sudo -u 10001 sftp_user 
RUN echo "sftp_user:1234" | chpasswd 

RUN mkdir /var/run/sshd

RUN sed 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' -i /etc/pam.d/sshd

ENV NOTVISIBLE "in users profile"
RUN echo "export VISIBLE=now" >> /etc/profile

EXPOSE 22
CMD ["/usr/sbin/sshd", "-D"]

RUN mkdir -p /var/sftp/uploads
RUN chown root:root /var/sftp
RUN chmod 755 /var/sftp
RUN chown sftp_user:sftp_user /var/sftp/uploads


RUN echo '\n\
        Match User sftp_user  \n\
        ForceCommand internal-sftp \n\ 
        PasswordAuthentication yes \n\ 
        ChrootDirectory /var/sftp \n\ 
        PermitTunnel no  \n\ 
        AllowAgentForwarding no \n\ 
        AllowTcpForwarding no \n\ 
        X11Forwarding no ' >> /etc/ssh/sshd_config 

