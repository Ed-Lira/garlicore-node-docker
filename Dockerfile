FROM node:6.17.0-stretch-slim

#Prepare apt-get
RUN apt-get update

#Install dependencies for node and Garlicoin
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

#Garlicoin needs boost 1.58.0 which needs to be built from source and installed
RUN mkdir -pv /tmp/boostinst && \
  cd /tmp/boostinst/ && \
  wget -c 'http://sourceforge.net/projects/boost/files/boost/1.58.0/boost_1_58_0.tar.bz2/download' && \
  tar xf download && \
  ls && \
  cd boost_1_58_0/ && \
  ./bootstrap.sh --help && \
  ./bootstrap.sh --show-libraries && \
  ./bootstrap.sh && \
  checkinstall ./b2 install

#Garlicoin needs berkeley-db 4.8 which needs to be built from source and installed
RUN mkdir /tmp/berkeley && \
  cd /tmp/berkeley/ && \
  wget -c 'https://download.oracle.com/berkeley-db/db-4.8.30.NC.tar.gz' && \
  tar -zxvf db-4.8.30.NC.tar.gz && \
  cd db-4.8.30.NC/ && \
  sed -i 's/\(__atomic_compare_exchange\)/\1_db/' dbinc/atomic.h && \
  cd build_unix/ && \
  ../dist/configure --prefix=/usr \
  --enable-compat185 \
  --enable-dbm       \
  --disable-static   \
  --enable-cxx && \
  make && \
  make docdir=/usr/share/doc/db-4.8.30 install

#Fix ownership of berkeley db library
RUN chown -v -R root:root \
  /usr/bin/db_* \
  /usr/include/db_cxx.h \
  /usr/lib/libdb*.so \
  /usr/share/doc/db-4.8.30

RUN TEMP_DEB="$(mktemp)" && \
  wget -O "$TEMP_DEB" 'http://security.debian.org/debian-security/pool/updates/main/o/openssl/libssl1.0.0_1.0.1t-1+deb8u12_amd64.deb' && \
  dpkg -i "$TEMP_DEB" && \
  rm -f "$TEMP_DEB"

#Install libevent dependencies for Garlicoin
RUN apt-get install -y libevent-pthreads-2.0-5 libevent-2.0-5

#Install zeromq
RUN wget http://download.zeromq.org/zeromq-4.0.5.tar.gz && \
tar xvzf zeromq-4.0.5.tar.gz && \
apt-get install -y libtool pkg-config build-essential autoconf automake uuid-dev && \
cd zeromq-4.0.5 && \
./configure && \
make install && \
ldconfig && \
ldconfig -p | grep zmq

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

#Download Garlicoin-Core and symlink it to where garlicoin-node expects it to be
# TODO: In the future this can be built from source. We're already doing a lot of work
# to make sure all the needed dependencies are available.
# The trade-off is an increase in the time to build this image. On the other hand 
# it would make this image more suitable for development work on garlicoin-core. And allow for dev "end-user" updates of
# the garlicoin-core version in lieu of regular releases.
# Stretch goal: this can be made configurable, either just extracting a release or building a commit/branch/tag
RUN mkdir ./garlicoin-core && \
  wget -c https://github.com/garlicoin-project/Garlicoin/releases/download/v0.16.0.2-garlicore/garlicoin-0.16.0.2-x86_64-linux-gnu.tar.gz -O - | tar -xz -C ./garlicoin-core && \
  chmod +x ./garlicoin-core/garlicoind && \
  ln ./garlicoin-core/garlicoind ./node_modules/.bin/garlicoind
  
RUN ls ./garlicoin-core
RUN ls -l ./node_modules/.bin/garlicoind

VOLUME /root/garlicoin-node/data
