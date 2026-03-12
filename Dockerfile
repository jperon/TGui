FROM tarantool/tarantool:3

RUN apt-get update && apt-get install -y --no-install-recommends git build-essential wget unzip gettext po4a && rm -rf /var/lib/apt/lists/*

# Install the HTTP server rock
RUN tt rocks install http

# Install lpeglabel (superset de lpeg, disponible dans les rocks Tarantool)
# et créer un shim lpeg.lua pour la compatibilité avec MoonScript
RUN tt rocks install lpeglabel && \
    mkdir -p /usr/local/share/tarantool/ && \
    echo 'return require("lpeglabel")' > /usr/local/share/tarantool/lpeg.lua

