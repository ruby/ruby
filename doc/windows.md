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

```
ridk enable ucrt64

pacman -S --needed %MINGW_PACKAGE_PREFIX%-openssl %MINGW_PACKAGE_PREFIX%-libyaml %MINGW_PACKAGE_PREFIX%-libffi

cd c:\
mkdir work
cd work
git clone https://github.com/ruby/ruby

cd c:\work\ruby
sh autogen.sh
sh configure  -C --disable-install-doc
make
```

or in MSYS2 `bash` like:

```
ridk enable ucrt64
bash

pacman -S --needed $MINGW_PACKAGE_PREFIX-openssl $MINGW_PACKAGE_PREFIX-libyaml $MINGW_PACKAGE_PREFIX-libffi

cd /c/
mkdir work
cd work
git clone https://github.com/ruby/ruby
cd ruby

./autogen.sh
./configure -C --disable-install-doc
make
```

[RubyInstaller-Devkit]: https://rubyinstaller.org/
[git-for-windows]: https://gitforwindows.org/
[VSCode]: https://code.visualstudio.com/

## Building Ruby using Visual C++

### Requirement

1.  Windows 7 or later.

2.  Visual C++ 12.0 (2013) or later.

    **Note** if you want to build x64 version, use native compiler for
    x64.

3.  Please set environment variable `INCLUDE`, `LIB`, `PATH`
    to run required commands properly from the command line.

    **Note** building ruby requires following commands.

    * nmake
    * cl
    * ml
    * lib
    * dumpbin

4.  If you want to build from GIT source, following commands are required.
    * patch
    * sed
    * ruby 2.0 or later

    You can use [scoop](https://scoop.sh/) to install them like:

    ```
    scoop install git ruby sed patch
    ```

5. You need to install required libraries using [vcpkg](https://vcpkg.io/) like:

    ```
    vcpkg --triplet x64-windows install openssl libffi libyaml zlib
    ```

6.  Enable Command Extension of your command line.  It's the default behavior
    of `cmd.exe`.  If you want to enable it explicitly, run `cmd.exe` with
    `/E:ON` option.

### How to compile and install

1.  Execute `win32\configure.bat` on your build directory.
    You can specify the target platform as an argument.
    For example, run `configure --target=i686-mswin32`
    You can also specify the install directory.
    For example, run `configure --prefix=<install_directory>`
    Default of the install directory is `/usr` .
    The default _PLATFORM_ is `i386-mswin32_`_MSRTVERSION_ on 32-bit
    platforms, or `x64-mswin64_`_MSRTVERSION_ on x64 platforms.
    _MSRTVERSION_ is the 2- or 3-digits version of the Microsoft
    Runtime Library.

2.  Change _RUBY_INSTALL_NAME_ and _RUBY_SO_NAME_ in `Makefile`
    if you want to change the name of the executable files.
    And add _RUBYW_INSTALL_NAME_ to change the name of the
    executable without console window if also you want.

3.  You need specify vcpkg directory to use `--with-opt-dir`
    option like `configure --with-opt-dir=C:\vcpkg\installed\x64-windows`

4.  Run `nmake up` if you are building from GIT source.

5.  Run `nmake`

6.  Run `nmake check`

7.  Run `nmake install`

### Build examples

* Build on the ruby source directory.

    ```
    ruby source directory:  C:\ruby
    build directory:        C:\ruby
    install directory:      C:\usr\local
    ```

    ```
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

    ```
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

    ```
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

    ```
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
