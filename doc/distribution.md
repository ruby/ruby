# Distribution

This document outlines the expected way to distribute Ruby, with a specific focus on building Ruby packages.

## Getting the Ruby Tarball

### Official Releases

The tarball for official releases is created by the release manager. The release manager uploads the tarball to the [Ruby website](https://www.ruby-lang.org/en/downloads/).

Downstream distributors should use the official release tarballs as part of their build process. This ensures that the tarball is created in a consistent way, and that the tarball is crytographically verified.

### Using the nightly tarball for testing

See the Snapshots section of the [Ruby website](https://www.ruby-lang.org/en/downloads/).

### Building a manual snapshot tarball for testing

This can be useful if the nightly tarball does not have all changes yet.

At Ruby source tree cloned using git:
```sh-session
$ ./autogen.sh
$ ./configure -C
$ make
$ make dist
```

This will create several tarball in the `tmp` directory. The tarball will be named e.g. `ruby-<version>.tar.gz` (several different compression formats will be generated).

## Building the Tarball

See [Building Ruby](contributing/building_ruby.md).

## Updating the Ruby Standard Library

The Ruby standard library is a collection of Ruby files that are included with Ruby. These files are used to provide the basic functionality of Ruby. The standard library is located in the `lib` directory and is distributed as part of the Ruby tarball.

Occasionally, the standard library needs to be updated, for example a security issue might be found in a default gem or standard gem. There are two main ways that Ruby would update this code.

### Releasing an Updated Ruby Gem

Normally, the Ruby gem maintainer will release an updated gem. This gem can be installed alongside the default gem. This allows the user to update the gem without having to update Ruby.

### Releasing a New Ruby Version

If the update is critical, then the Ruby maintainers may decide to release a new version of Ruby. This new version will include the updated standard library.
