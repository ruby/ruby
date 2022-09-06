# MJIT

This document has some tips that might be useful when you work on MJIT.

## Supported platforms

The following platforms are either tested on CI or assumed to work.

* OS: Linux, macOS
* Arch: x86\_64, aarch64, arm64, i686, i386

### Not supported

The MJIT support for the following platforms is no longer maintained.

* OS: Windows (mswin, MinGW), Solaris
* Arch: SPARC, s390x

### Architectures

## Bindgen

If you see an "MJIT bindgen" GitHub Actions failure, please commit the `git diff` shown on the failed job.

Refer to the following instructions for doing the same thing locally.
Similar to `make yjit-bindgen`, `make mjit-bindgen` requires libclang.
See also: [mjit-bindgen.yml](../.github/workflows/mjit-bindgen.yml)

macOS seems to have libclang by default, but I'm not sure how to deal with 32bit architectures.
For now, you may generate c\_64.rb with a 64bit binary, and then manually modify c\_32.rb accordingly.

### x86\_64-linux

```sh
sudo apt install \
  build-essential \
  libssl-dev libyaml-dev libreadline6-dev \
  zlib1g-dev libncurses5-dev libffi-dev \
  libclang1
./autogen.sh
./configure --enable-yjit=dev_nodebug --disable-install-doc
make -j
make mjit-bindgen
```

### i686-linux

```sh
sudo dpkg --add-architecture i386
sudo apt install \
  crossbuild-essential:i386 \
  libssl-dev:i386 libyaml-dev:i386 libreadline6-dev:i386 \
  zlib1g-dev:i386 libncurses5-dev:i386 libffi-dev:i386 \
  libclang1:i386
./autogen.sh
./configure --disable-install-doc
make -j
make mjit-bindgen
```

Note that you cannot run x86\_64 bindgen with an i686 binary, and vice versa.
Also, when you install libclang1:i386, libclang1 will be uninstalled.
You can have only either of these at a time.

## Local development

### Always run make install

Always run `make install` before running MJIT. It could easily cause a SEGV if you don't.
MJIT looks for the installed header for security reasons.

### --mjit-debug vs --mjit-debug=-ggdb3

`--mjit-debug=[flags]` allows you to specify arbitrary flags while keeping other compiler flags like `-O3`,
which is useful for profiling benchmarks.

`--mjit-debug` alone, on the other hand, disables `-O3` and adds debug flags.
If you're debugging MJIT, what you need to use is not `--mjit-debug=-ggdb3` but `--mjit-debug`.
