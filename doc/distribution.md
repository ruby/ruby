# Distribution

This document outlines the expected way to distribute Ruby, with a specific focus on building Ruby packages for operating system distributions.

## Building a Ruby Tarball

The standard way to build a package for distribution is to build a tarball. This tarball includes all the related files need to build and install Ruby correctly. This includes the Ruby source code, the Ruby standard library, and the Ruby documentation.

```shell
$ ./autogen.sh
$ mkdir /tmp/fakeroot
$ ./configure -C --prefix=/tmp/fakeroot
$ make
$ make dist
```

This will create a tarball in the `dist` directory. The tarball will be named `ruby-<version>.tar.gz`.

## Updating the Ruby Standard Library

The Ruby standard library is a collection of Ruby files that are included with Ruby. These files are used to provide the basic functionality of Ruby. The standard library is located in the `lib` directory and is distributed as part of the Ruby tarball.

Occasionally, the standard library needs to be updated, for example a security issue might be found in a default gem or standard gem. There are two main ways that Ruby would update this code.

### Releasing an Updated Ruby Gem

Normally, the Ruby gem maintainer will release an updated gem. This gem can be installed alongside the default gem. This allows the user to update the gem without having to update Ruby.

### Releasing a New Ruby Version

If the update is critical, then the Ruby maintainers may decide to release a new version of Ruby. This new version will include the updated standard library.
