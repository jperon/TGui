FROM tarantool/tarantool:3

RUN apt-get update && apt-get install -y --no-install-recommends git build-essential wget unzip gettext po4a libzstd-dev && rm -rf /var/lib/apt/lists/*

# Install the HTTP server rock
RUN tt rocks install http

# Install lpeglabel (superset de lpeg, disponible dans les rocks Tarantool)
# et créer un shim lpeg.lua pour la compatibilité avec MoonScript
RUN tt rocks install lpeglabel && \
    mkdir -p /usr/local/share/tarantool/ && \
    echo 'return require("lpeglabel")' > /usr/local/share/tarantool/lpeg.lua

# Install compression libraries for YAML snapshot compression
RUN tt rocks install --server=https://luarocks.org LibDeflate && \
    tt rocks install --server=https://luarocks.org base64

# Install luajit-zstd for ZSTD compression
RUN wget https://github.com/sjnam/luajit-zstd/archive/v0.2.3.tar.gz && \
    tar -xzf v0.2.3.tar.gz && \
    cd luajit-zstd-0.2.3 && \
    cp zstd.lua /opt/tarantool/.rocks/share/tarantool/zstd.lua && \
    cd .. && rm -rf luajit-zstd-0.2.3 v0.2.3.tar.gz

