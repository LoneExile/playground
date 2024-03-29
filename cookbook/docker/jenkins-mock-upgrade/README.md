# Jenkins

## Initial Setup

```bash
service jenkins start

sudo ufw allow 8080
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
