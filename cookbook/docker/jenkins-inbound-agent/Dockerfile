FROM node:18 AS nodejs
FROM golang:1.21.0 AS golang
FROM jenkins/inbound-agent:bookworm-jdk17 AS builder

RUN addgroup -S nonroot \
  && adduser -S nonroot -G nonroot

USER nonroot

COPY --from=nodejs /usr/local/bin/node /usr/local/bin/node
COPY --from=golang /usr/local/go /usr/local/go

CMD ["tail", "-f", "/dev/null"]
