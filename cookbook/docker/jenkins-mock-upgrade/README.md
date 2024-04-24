# Jenkins

## Initial Setup

```bash
service jenkins start && ufw allow 8080

cat /var/log/jenkins/jenkins.log
```

## Upgrading Jenkins

```bash
service jenkins stop

# find the current version (./usr/share/java/jenkins.war)
# find . -name "*jenkins*" | grep war

mv jenkins.war jenkins.war.old

# Get the version you want
# https://updates.jenkins.io/download/war/
wget https://updates.jenkins.io/download/war/{version}/jenkins.war

service jenkins start
```

or use update.sh

```bash
./update.sh 2.442
```
