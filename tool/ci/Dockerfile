FROM ubuntu:18.04

# Copy tool/ci/* files.
WORKDIR /home/ruby
COPY . .

ENV RUBY_INSTALLED_COMPILER gcc-8
ENV RUBY_INSTALLED_OPENSSL_VERSION 1.1.1

# Set the DEBIAN_FRONTEND to install tzdata.
# Install git and sudo for convenience.
RUN apt-get update -qq && \
  export DEBIAN_FRONTEND=noninteractive && \
  apt-get install -y --no-install-recommends -qq \
  autoconf \
  bison \
  build-essential \
  ca-certificates \
  curl \
  git \
  gzip \
  libffi-dev \
  libssl-dev \
  netbase \
  patch \
  pkg-config \
  openssl \
  ruby \
  software-properties-common \
  sudo \
  tzdata \
  zlib1g-dev
RUN add-apt-repository -y ppa:ubuntu-toolchain-r/test && \
  apt-get update -qq && \
  apt-get install -qq "${RUBY_INSTALLED_COMPILER}"
RUN apt-get clean all
# Set any time zone to pass the test.
RUN ln -snf /usr/share/zoneinfo/Japan /etc/localtime
RUN dpkg-reconfigure --frontend noninteractive tzdata

RUN ./install_openssl.sh "${RUBY_INSTALLED_OPENSSL_VERSION}"
# Copy certificates files to pass the test on source installed OpenSSL.
RUN cp -rp /usr/lib/ssl "/opt/openssl/openssl-${RUBY_INSTALLED_OPENSSL_VERSION}/"

ENTRYPOINT ["/home/ruby/init.sh"]
