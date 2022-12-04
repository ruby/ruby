# Distribution

This document outlines the expected way to distribute Ruby, with a specific focus on building Ruby packages for operating system distributions.

## Building a Ruby Tarball

The standard way to build a package for distribution is to build a tarball. This tarball includes all the related files need to build and install Ruby correctly. This includes the Ruby source code, the Ruby standard library, and the Ruby documentation.

```bash
$ ./autogen.sh
$ ./configure -C
$ make
$ make dist
```

This will create several tarball in the `dist` directory. The tarball will be named e.g. `ruby-<version>.tar.gz` (several different compression formats will be generated).

### Official Releases

The tarball for official releases is created by the release manager. The release manager will run the above commands to create the tarball. The release manager will then upload the tarball to the [Ruby website](https://www.ruby-lang.org/en/downloads/).

Downstream distributors should use the official release tarballs as part of their build process. This ensures that the tarball is created in a consistent way, and that the tarball is crytographically verified.

## Building a Ruby Package

Most distributions have a tool to build packages from a tarball. For example, Debian has `dpkg-buildpackage` and Fedora has `rpmbuild`. These tools will take the tarball and build a package for the distribution.

```bash
$ pkgver=3.1.3
$ curl https://cache.ruby-lang.org/pub/ruby/${pkgver:0:3}/ruby-${pkgver}.tar.xz --output ruby-${pkgver}.tar.xz
$ tar xpvf ruby-${pkgver}.tar.xz
$ cd ruby-${pkgver}
$ ./configure
$ make
$ make install
```

## Updating the Ruby Standard Library

The Ruby standard library is a collection of Ruby files that are included with Ruby. These files are used to provide the basic functionality of Ruby. The standard library is located in the `lib` directory and is distributed as part of the Ruby tarball.

Occasionally, the standard library needs to be updated, for example a security issue might be found in a default gem or standard gem. There are two main ways that Ruby would update this code.

### Releasing an Updated Ruby Gem

Normally, the Ruby gem maintainer will release an updated gem. This gem can be installed alongside the default gem. This allows the user to update the gem without having to update Ruby.

### Releasing a New Ruby Version

If the update is critical, then the Ruby maintainers may decide to release a new version of Ruby. This new version will include the updated standard library.
