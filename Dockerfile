FROM debian:bookworm-slim

WORKDIR /app

RUN apt update && \
    apt install -y curl jq && \
    apt clean

COPY script.sh script.sh

CMD ["/bin/bash", "script.sh"]