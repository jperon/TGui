FROM tarantool/tarantool:3

RUN apt-get update && apt-get install -y --no-install-recommends git build-essential && rm -rf /var/lib/apt/lists/*

# Install the HTTP server rock
RUN tt rocks install http
