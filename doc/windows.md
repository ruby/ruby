# Windows

Ruby supports a few native build platforms for Windows.

* mswin: Build using Microsoft Visual C++ compiler with vcruntimeXXX.dll
* mingw-msvcrt: Build using compiler for Mingw with msvcrtXX.dll
* mingw-ucrt: Build using compiler for Mingw with Windows Universal CRT

## Building Ruby using Mingw with UCRT

The easiest build environment is just a standard [RubyInstaller-Devkit]
installation and [git-for-windows]. You might like to use [VSCode] as an
editor.

### Build examples

Ruby core development can be done either in Windows `cmd` like:

```batch
ridk install
ridk enable ucrt64

pacman -S --needed %MINGW_PACKAGE_PREFIX%-openssl %MINGW_PACKAGE_PREFIX%-libyaml %MINGW_PACKAGE_PREFIX%-libffi

mkdir c:\work\ruby
cd /d c:\work\ruby

git clone https://github.com/ruby/ruby src

sh ./src/autogen.sh

mkdir build
cd build
sh ../src/configure -C --disable-install-doc
make
```

or in MSYS2 `bash` like:

```bash
ridk install
ridk enable ucrt64
bash

pacman -S --needed $MINGW_PACKAGE_PREFIX-openssl $MINGW_PACKAGE_PREFIX-libyaml $MINGW_PACKAGE_PREFIX-libffi

mkdir /c/work/ruby
cd /c/work/ruby

git clone https://github.com/ruby/ruby src

./src/autogen.sh
cd build
../src/configure -C --disable-install-doc
make
```

If you have other MSYS2 environment via other package manager like `scoop`, you need to specify `$MINGW_PACKAGE_PREFIX` is `mingw-w64-ucrt-x86_64`.
And you need to add `--with-opt-dir` option to `configure` command like:

```batch
sh ../../ruby/configure -C --disable-install-doc --with-opt-dir=C:\Users\username\scoop\apps\msys2\current\ucrt64
```

[RubyInstaller-Devkit]: https://rubyinstaller.org/
[git-for-windows]: https://gitforwindows.org/
[VSCode]: https://code.visualstudio.com/

## Building Ruby using Visual C++

### Requirement

1.  Windows 10/Windows Server 2016 or later.

2.  Visual C++ 14.0 (2015) or later.

    **Note** if you want to build x64 version, use native compiler for
    x64.

    The minimum requirement is here:
      * VC++/MSVC on VS 2017/2019 version build tools.
        * Visual Studio 2022 17.13.x is broken. see https://bugs.ruby-lang.org/issues/21167
      * Windows 10/11 SDK
        * 10.0.26100 is broken, 10.0.22621 is recommended. see https://bugs.ruby-lang.org/issues/21255

3.  Please set environment variable `INCLUDE`, `LIB`, `PATH`
    to run required commands properly from the command line.
    These are set properly by `vcvarall*.bat` usually.

    **Note** building ruby requires following commands.

    * `nmake`
    * `cl`
    * `ml`
    * `lib`
    * `dumpbin`

4.  If you want to build from GIT source, following commands are required.
    * `git`
    * `ruby` 3.0 or later

    You can use [scoop](https://scoop.sh/) to install them like:

    ```batch
    scoop install git ruby
    ```

    The windows version of `git` configured with `autocrlf` is `true`. The Ruby
    test suite may fail with `autocrlf` set to `true`. You can set it to `false`
    like:

    ```batch
    git config --global core.autocrlf false
    ```

5.  You need to install required libraries using [vcpkg](https://vcpkg.io/) on
    directory of ruby repository like:

    ```batch
    vcpkg --triplet x64-windows install
    ```

6.  Enable Command Extension of your command line.  It's the default behavior
    of `cmd.exe`.  If you want to enable it explicitly, run `cmd.exe` with
    `/E:ON` option.

### How to compile and install

1.  Execute `win32\configure.bat` on your build directory.
    You can specify the target platform as an argument.
    For example, run `configure --target=i686-mswin32`.
    You can also specify the install directory.
    For example, run `configure --prefix=<install_directory>`.
    Default of the install directory is `/usr` .

2.  If you want to append to the executable and DLL file names,
    specify `--program-prefix` and `--program-suffix`, like
    `win32\configure.bat --program-suffix=-$(MAJOR)$(MINOR)`.

    Also, the `--install-name` and `--so-name` options specify the
    exact base names of the executable and DLL files, respectively,
    like `win32\configure.bat --install-name=$(RUBY_BASE_NAME)-$(MAJOR)$(MINOR)`.

    By default, the name for the executable without a console window
    is generated from the _RUBY_INSTALL_NAME_ specified as above by
    replacing `ruby` with `rubyw`.  If you want to make it different
    more, modify _RUBYW_INSTALL_NAME_ directly in the Makefile.

3.  You need specify vcpkg directory to use `--with-opt-dir`
    option like `win32\configure.bat --with-opt-dir=C:/vcpkg_installed/x64-windows`

4.  Run `nmake up` if you are building from GIT source.

5.  Run `nmake`

6.  Run `nmake prepare-vcpkg` with administrator privilege if you need to
    copy vcpkg installed libraries like `libssl-3-x64.dll` to the build directory.

7.  Run `nmake check`

8.  Run `nmake install`

### Build examples

* Build on the ruby source directory.

    ```
    ruby source directory:  C:\ruby
    build directory:        C:\ruby
    install directory:      C:\usr\local
    ```

    ```batch
    C:
    cd \ruby
    win32\configure --prefix=/usr/local
    nmake
    nmake check
    nmake install
    ```

* Build on the relative directory from the ruby source directory.

    ```
    ruby source directory:  C:\ruby
    build directory:        C:\ruby\mswin32
    install directory:      C:\usr\local
    ```

    ```batch
    C:
    cd \ruby
    mkdir mswin32
    cd mswin32
    ..\win32\configure --prefix=/usr/local
    nmake
    nmake check
    nmake install
    ```

* Build on the different drive.

    ```
    ruby source directory:  C:\src\ruby
    build directory:        D:\build\ruby
    install directory:      C:\usr\local
    ```

    ```batch
    D:
    cd D:\build\ruby
    C:\src\ruby\win32\configure --prefix=/usr/local
    nmake
    nmake check
    nmake install DESTDIR=C:
    ```

* Build x64 version (requires native x64 VC++ compiler)

    ```
    ruby source directory:  C:\ruby
    build directory:        C:\ruby
    install directory:      C:\usr\local
    ```

    ```batch
    C:
    cd \ruby
    win32\configure --prefix=/usr/local --target=x64-mswin64
    nmake
    nmake check
    nmake install
    ```

### Bugs

You can **NOT** use a path name that contains any white space characters
as the ruby source directory, this restriction comes from the behavior
of `!INCLUDE` directives of `NMAKE`.

You can build ruby in any directory including the source directory,
except `win32` directory in the source directory.
This is restriction originating in the path search method of `NMAKE`.

### Dependency management

Ruby uses [vcpkg](https://vcpkg.io/) to manage dependencies on mswin platform.

You can update and install it under the build directory like:

```batch
nmake update-vcpkg # Update baseline version of vcpkg
nmake install-vcpkg # Install vcpkg from build directory
```


## Icons

Any icon files(`*.ico`) in the build directory, directories specified with
_icondirs_ make variable and `win32` directory under the ruby
source directory will be included in DLL or executable files, according
to their base names.
    $(RUBY_INSTALL_NAME).ico or ruby.ico   --> $(RUBY_INSTALL_NAME).exe
    $(RUBYW_INSTALL_NAME).ico or rubyw.ico --> $(RUBYW_INSTALL_NAME).exe
    the others                             --> $(RUBY_SO_NAME).dll

Although no icons are distributed with the ruby source, you can use
anything you like. You will be able to find many images by search engines.
For example, followings are made from [Ruby logo kit]:

* Small [favicon] in the official site

* [vit-ruby.ico] or [icon itself]

[Ruby logo kit]: https://cache.ruby-lang.org/pub/misc/logo/ruby-logo-kit.zip
[favicon]: https://www.ruby-lang.org/favicon.ico
[vit-ruby.ico]: http://ruby.morphball.net/vit-ruby-ico_en.html
[icon itself]: http://ruby.morphball.net/icon/vit-ruby.ico
