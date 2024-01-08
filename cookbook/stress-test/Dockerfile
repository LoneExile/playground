FROM ubuntu:22.04 as builder

RUN apt-get update  \
        && apt-get install -y stressapptest

FROM builder

CMD ["stressapptest", "-s", "360", "-M", "256", "-m", "8", "-W"]



