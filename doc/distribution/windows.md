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

1.  Windows 10 version 1809 (build 17763)/Windows Server 2019 or later.

2.  Visual C++ 14.15 (Visual Studio 2017 version 15.8) or later.

    **Note** if you want to build x64 version, use native compiler for
    x64.

    The minimum requirement is here:
      * VC++/MSVC build tools on VS 2017 version 15.8 or later.
      * Windows 10/11 SDK

    You can install Visual Studio Build Tools with `winget`.
    `win32\install-buildtools.cmd` is a batch file to install the
    minimum requirements excluding the IDE etc.

3.  Please set environment variable `INCLUDE`, `LIB`, `PATH` to run
    required commands properly from the command line.  These are set
    properly by `vsdevcmd.bat` or `vcvarall*.bat` usually. You can run
    the following command to set them in your command line.

    To native build:

    ```
    cmd /k win32\vssetup.cmd
    ```

    To cross build arm64 binary:

    ```
    cmd /k win32\vssetup.cmd -arch=arm64
    ```

    To cross build x64 binary:

    ```
    cmd /k win32\vssetup.cmd -arch=x64
    ```

    This batch file is a wrapper of `vsdevcmd.bat` and options are
    passed to it as-is.  `win32\vssetup.cmd -help` for other command
    line options.

    **Note** building ruby requires following commands.

    * `nmake`
    * `cl`
    * `ml`
    * `lib`
    * `dumpbin`

4.  If you want to build from GIT source, following commands are required.
    * `git`
    * `ruby` 3.1 or later

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

7.  Some tests in `nmake check` create symbolic links.  Enable
    [Developer Mode](https://learn.microsoft.com/windows/apps/get-started/developer-mode-features-and-debugging)
    (Settings > System > For developers) so that they do not fail with
    `Permission denied @ rb_file_s_symlink`.

8.  If you want to build YJIT, `rustc` with the `x86_64-pc-windows-msvc`
    target is required.  YJIT is enabled with `--enable-yjit` of
    `win32\configure.bat`, and is supported only on x64 and only in
    YJIT's release mode, without the dev and stats builds.
    `--enable-yjit` accepts only `yes` or `no`.  A YJIT
    build does not install the static library.

9.  If you want to build with clang-cl instead of `cl`, clang-cl 15 or
    later is required.  It is the "C++ Clang Compiler for Windows"
    component (`Microsoft.VisualStudio.Component.VC.Llvm.Clang`) of
    Visual Studio 2022 version 17.4 or later.  `win32\vssetup.cmd`
    adds `clang-cl` to `PATH` when the component is installed.  You can
    add it to the installed Build Tools with Visual Studio Installer, or
    from the command line like:

    ```batch
    "%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\setup.exe" modify --installPath "%ProgramFiles(x86)%\Microsoft Visual Studio\18\BuildTools" --add Microsoft.VisualStudio.Component.VC.Llvm.Clang --passive
    ```

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

4.  If you want to build with clang-cl, specify `CC=clang-cl` like
    `win32\configure.bat CC=clang-cl`.  The installed ruby also uses
    clang-cl to build extension libraries, so installing gems with C
    extensions requires clang-cl too.

5.  Run `nmake up` if you are building from GIT source.

6.  Run `nmake`

7.  Run `nmake prepare-vcpkg` with administrator privilege if you need to
    copy vcpkg installed libraries like `libssl-3-x64.dll` to the build directory.

8.  Run `nmake check`

9.  Run `nmake install`

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

* Build x64 version with clang-cl

    ```
    ruby source directory:  C:\ruby
    build directory:        C:\ruby
    install directory:      C:\usr\local
    ```

    ```batch
    C:
    cd \ruby
    win32\configure --prefix=/usr/local CC=clang-cl
    nmake
    nmake check
    nmake install
    ```

### Building with GNU make

`nmake` cannot run jobs in parallel. `win32\configure.bat --with-gnu-make` writes `GNUmakefile` instead of `Makefile`, so that you can build with `make -j`. This is experimental, and `nmake` stays the default.

GNU make 4.4 or later built for native Windows is required. `win32\install-gnumake.cmd` downloads the GNU make release, verifies its SHA256, builds it with `cl`, and puts `make.exe` in `.gnumake` under the ruby source directory, or in the directory given as its argument.

```batch
C:
cd \ruby
win32\install-gnumake.cmd
set PATH=C:\ruby\.gnumake;%PATH%
win32\configure --prefix=/usr/local --with-opt-dir=C:/ruby/vcpkg_installed/x64-windows --with-gnu-make
make -j16
make check
make install
```

Use `make` in place of `nmake` for the other targets in this document too, such as `make up`, `make prepare-vcpkg` and `make update-vcpkg`.

The installed ruby also builds extension libraries with `make` found in `PATH`, not with `nmake`. Before installing gems with C extensions, copy `make.exe` from `.gnumake` to a directory in `PATH`, such as the `bin` directory of the install directory, since `make install` does not install it.

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


## Windows Defender Firewall

Some tests listen on all interfaces, and Windows Defender Firewall shows a security alert dialog when an executable at a path it has no rule for does so. If you keep the same build directory, run `win32\firewall.cmd` there once, and the dialog no longer interrupts the tests. It adds rules that block inbound connections to `ruby.exe` and `rubyw.exe` in that directory, so the tests are not exposed to other machines, while connections from the same machine still work.

```batch
cd /d D:\build\ruby
C:\src\ruby\win32\firewall.cmd
```

It restarts itself as administrator when not elevated. It also takes the build directory as an argument. When you no longer need the rules, delete them with `-delete`.

```batch
C:\src\ruby\win32\firewall.cmd -delete D:\build\ruby
```

If you build in a new worktree for each task, as coding agents often do, every worktree meets the dialog. A `post-checkout` hook in `.git/hooks` registers each worktree when `git worktree add` creates it, before its first build, and skips worktrees that already have the rules. The script elevates itself, so the hook runs without stopping when User Account Control is set to never notify.

```sh
#!/bin/sh
top=$(git rev-parse --show-toplevel) || exit 0
fw="$top/win32/firewall.cmd"
[ -f "$fw" ] || exit 0
dir=$(cygpath -w "$top")
netsh advfirewall firewall show rule name="Ruby build directory $dir" >/dev/null 2>&1 && exit 0
cmd //c "$(cygpath -w "$fw")" "$dir" >/dev/null 2>&1
exit 0
```

Otherwise each new worktree asks for administrator privilege. To avoid that, register once from an elevated prompt a task that runs the script for every worktree with the highest privileges, and replace the `cmd` line of the hook with `schtasks //run //tn ruby-firewall >/dev/null 2>&1`. The task runs without asking.

```batch
schtasks /create /tn ruby-firewall /sc once /st 00:00 /rl highest /tr "cmd /c for /d %D in (C:\src\worktrees\*) do C:\src\ruby\win32\firewall.cmd %D"
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
For example, the following are made from [Ruby logo kit]:

* Small [favicon] in the official site

* [vit-ruby.ico] or [icon itself]

[Ruby logo kit]: https://cache.ruby-lang.org/pub/misc/logo/ruby-logo-kit.zip
[favicon]: https://www.ruby-lang.org/favicon.ico
[vit-ruby.ico]: http://ruby.morphball.net/vit-ruby-ico_en.html
[icon itself]: http://ruby.morphball.net/icon/vit-ruby.ico
