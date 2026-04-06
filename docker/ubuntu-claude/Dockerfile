FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Base tools + Node.js 20.x
RUN apt-get update && \
    apt-get install -y curl ca-certificates git && \
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Claude Code
RUN npm install -g @anthropic-ai/claude-code

CMD ["/bin/bash"]
