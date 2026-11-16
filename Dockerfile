FROM tarantool/tarantool:3

RUN apt-get update && apt-get install -y --no-install-recommends git build-essential wget unzip gettext po4a libzstd-dev && rm -rf /var/lib/apt/lists/*

# Install the HTTP server rock
# Le serveur par défaut (rocks.tarantool.org) redirige vers un bucket S3 signé
# que tt rocks ne sait pas suivre : on installe depuis luarocks.org.
RUN tt rocks install --server=https://luarocks.org http

# Install lpeglabel (superset de lpeg, disponible dans les rocks Tarantool)
# et créer un shim lpeg.lua pour la compatibilité avec MoonScript
RUN tt rocks install --server=https://luarocks.org lpeglabel && \
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


# MoonScript 0.8.0 — analyseur natif (moonscript.parse.native) pour le LuaJIT
# de Tarantool. Les sources viennent du sous-module backend/vendor/moonscript
# (épinglé sur v0.8.0) ; le module compilé est installé dans le package.cpath
# de Tarantool (/usr/local/lib64/tarantool/?.so), donc hors du montage
# read-only de ./backend. Repli pur Lua non nécessaire : build-essential et
# les en-têtes LuaJIT de l'image (/usr/include/tarantool) suffisent.
COPY backend/vendor/moonscript/moonscript/parse/native.c /tmp/moonscript-native.c
RUN mkdir -p /usr/local/lib64/tarantool/moonscript/parse && \
    gcc -shared -O2 -fPIC -I/usr/include/tarantool \
      -o /usr/local/lib64/tarantool/moonscript/parse/native.so /tmp/moonscript-native.c && \
    rm -f /tmp/moonscript-native.c
