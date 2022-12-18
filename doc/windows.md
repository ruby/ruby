# Windows

## Building Ruby

The easiest build environment is just a standard [RubyInstaller-Devkit installation](https://rubyinstaller.org/) and [git-for-windows](https://gitforwindows.org/). You might like to use [VSCode](https://code.visualstudio.com/) as an editor.

Ruby core development can be done either in Windows `cmd` like:

```
ridk enable ucrt64

pacman -S --needed bison %MINGW_PACKAGE_PREFIX%-openssl %MINGW_PACKAGE_PREFIX%-libyaml %MINGW_PACKAGE_PREFIX%-readline

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

pacman -S --needed bison $MINGW_PACKAGE_PREFIX-openssl $MINGW_PACKAGE_PREFIX-libyaml $MINGW_PACKAGE_PREFIX-readline

cd /c/
mkdir work
cd work
git clone https://github.com/ruby/ruby
cd ruby

./autogen.sh
./configure -C --disable-install-doc
make
```
