FROM ubuntu:22.04 as builder

RUN apt-get update  \
        && apt-get install -y stressapptest

FROM builder

CMD ["stressapptest", "-s", "360", "-M", "256", "-m", "8", "-W"]

# # Create a script to sleep for 1 minute and then run stressapptest
# RUN echo "#!/bin/bash\nsleep 60\nexec stressapptest -s 360000 -M 600 -m 8 -W" > /entrypoint.sh \
#         && chmod +x /entrypoint.sh

# # Set the script as the entrypoint
# ENTRYPOINT ["/entrypoint.sh"]
