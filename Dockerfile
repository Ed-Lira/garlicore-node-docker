FROM ubuntu:xenial AS build_step

RUN set -ex ; \
    mkdir -p /garlicoin ; \
    apt-get update -y    ; \
     	apt-get install -yq \
        git                 \
        build-essential     \
        libtool             \
        autotools-dev       \
        automake            \
        pkg-config          \
        libssl-dev          \
        libevent-dev        \
        bsdmainutils        \
        libboost-all-dev    \
        libzmq3-dev \
		software-properties-common ; \ 
	add-apt-repository ppa:bitcoin/bitcoin ; \ 
	apt-get update ; \
	apt-get install -yq libdb4.8-dev libdb4.8++-dev

RUN git clone https://github.com/garlicoin-project/garlicoin.git

RUN set -ex ; \
	cd /garlicoin ; \
	./autogen.sh ; \
	./configure --with-gui=no --disable-tests --disable-gui-tests; \ 
    make clean ; \
	make

FROM node:6.17.0-stretch-slim

#Prepare apt-get
RUN apt-get update

#Install dependencies for node
RUN apt-get install -y \
  g++ \
  gcc-6 \
  make \
  python \
  python-dev \
  gettext-base \
  jq \
  patch \
  git \
  tar \
  lbzip2 \
  devscripts \
  build-essential \
  autotools-dev \
  libicu-dev \
  libbz2-dev \
  checkinstall \
  && \
  wget https://github.com/Yelp/dumb-init/releases/download/v1.2.1/dumb-init_1.2.1_amd64.deb && \
  dpkg -i dumb-init_*.deb

#Expose Garlicoin ports
EXPOSE 3001 9333 19335

#Install NPM dependencies and apply patch
WORKDIR /root/garlicoin-node
COPY garlicore-node ./
RUN npm config set package-lock false && \
  npm install && \
  cat logo_insight_garlicoin.patch | patch -p1 -d node_modules/insight-grlc-ui

#Clean up some unneeded files to reduce image size
RUN apt-get purge -y \
  g++ make python && \
  apt-get autoclean && \
  apt-get autoremove -y && \
  rm -rf \
  node_modules/garlicore-node/test \
  node_modules/garlicore-node/bin/garlicoin-*/bin/garlicoin-qt \
  node_modules/garlicore-node/bin/garlicoin-*/bin/test_garlicoin \
  node_modules/garlicore-node/bin/garlicoin-*.tar.gz \
  /dumb-init_*.deb \
  /root/.npm \
  /root/.node-gyp \
  /tmp/* \
  /var/lib/apt/lists/*

#Set environment variables
ENV GARLICOIN_LIVENET 0
ENV API_ROUTE_PREFIX "api"
ENV UI_ROUTE_PREFIX ""

ENV API_CACHE_ENABLE 1

ENV API_LIMIT_ENABLE 1
ENV API_LIMIT_WHITELIST "127.0.0.1 ::1"
ENV API_LIMIT_BLACKLIST ""

ENV API_LIMIT_COUNT 10800
ENV API_LIMIT_INTERVAL 10800000

ENV API_LIMIT_WHITELIST_COUNT 108000
ENV API_LIMIT_WHITELIST_INTERVAL 10800000

ENV API_LIMIT_BLACKLIST_COUNT 0
ENV API_LIMIT_BLACKLIST_INTERVAL 10800000

#Set health check based on status of sync REST call
HEALTHCHECK --interval=5s --timeout=5s --retries=5 CMD curl -s "http://localhost:3001/{$API_ROUTE_PREFIX}/sync" | jq -r -e ".status==\"finished\""

#Prep entrypoints
RUN chmod +x ./garlicore-node-entrypoint.sh
ENTRYPOINT ["/usr/bin/dumb-init", "--", "./garlicore-node-entrypoint.sh"]

RUN ls

COPY --from=build_step /garlicoin/src/garlicoin* /usr/local/bin/
COPY --from=build_step /usr/lib/x86_64-linux-gnu/ /usr/lib/x86_64-linux-gnu/
COPY --from=build_step /usr/lib/libdb_cxx-4.8.so /usr/lib/libdb_cxx-4.8.so
COPY --from=build_step /lib/x86_64-linux-gnu/libcrypto.so.1.0.0 /lib/x86_64-linux-gnu/libcrypto.so.1.0.0

RUN ls /usr/local/bin/

RUN ln /usr/local/bin/garlicoind ./node_modules/.bin/garlicoind
  
RUN ls -l ./node_modules/.bin/garlicoind

VOLUME /root/garlicoin-node/data
