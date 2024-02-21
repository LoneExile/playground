FROM ubuntu:22.04 as builder

RUN apt-get update  \
  && apt-get install -y python3 python3-venv libaugeas0 jq curl unzip

FROM builder as certbot

RUN python3 -m venv /opt/certbot
RUN /opt/certbot/bin/pip install --upgrade pip
RUN /opt/certbot/bin/pip install certbot
RUN ln -s /opt/certbot/bin/certbot /usr/bin/certbot
RUN certbot register --email apinant@tuta.io --agree-tos --no-eff-email

RUN	curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
RUN	unzip awscliv2.zip && ./aws/install

FROM certbot 

RUN cd /etc/letsencrypt/accounts/acme-v02.api.letsencrypt.org/directory/* && \
  cat private_key.json | jq -r '{"e": .e, "kty": "RSA", "n": .n}' > /jwk.json
# python3 -c "import json, base64, hashlib; print(base64.urlsafe_b64encode(hashlib.sha256(json.dumps(json.load(open('jwk.json')), separators=(',', ':')).encode('utf-8')).digest()).decode('utf-8').rstrip('='))"

ARG AWS_ACCESS_KEY_ID=''
ARG AWS_SECRET_ACCESS_KEY=''
ARG AWS_REGION=''
ARG BUCKET=''
ARG DOMAIN=''

RUN aws s3api create-bucket --bucket "$BUCKET" --create-bucket-configuration LocationConstraint="$AWS_REGION"  2>/dev/null || true
RUN aws s3 cp /jwk.json s3://$BUCKET/jwk.json

RUN certbot certonly --standalone -d $DOMAIN --non-interactive --agree-tos
RUN aws s3 cp /etc/letsencrypt/live/$DOMAIN s3://$BUCKET/ --recursive

## make it run forevever
CMD ["tail", "-f", "/dev/null"]

