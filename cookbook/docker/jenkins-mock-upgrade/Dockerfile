FROM ubuntu:22.04 as build
EXPOSE 8080

RUN apt-get update && apt-get install -y wget gnupg2 ufw
RUN wget -q -O /usr/share/keyrings/jenkins-keyring.asc https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key
RUN echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" | tee /etc/apt/sources.list.d/jenkins.list > /dev/null
RUN apt-get update && apt-get install -y jenkins
RUN apt-get install -y openjdk-11-jdk vim

CMD ["tail", "-f", "/dev/null"]
