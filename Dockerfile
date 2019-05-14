FROM ubuntu:16.04

RUN apt-get update && apt-get install -y \
  build-essential autoconf libtool \
  git \
  ruby \
  pkg-config \
  libffi-dev \
  libffi6 \
  && apt-get clean

RUN apt-get install -y \
  cmake \
  gdb \
  valgrind

RUN apt-get install -y wget

RUN apt-get install -y libssl-dev \
  libgdbm3 \
  libgdbm-dev \
  libedit-dev \
  libedit2 \
  bison \
  hugepages \
  leaktracer

ENTRYPOINT /usr/bin/hugeadm --thp-never && /bin/bash
