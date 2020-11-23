dnl Process this file with autoconf to produce a configure script.
AC_INIT()
{
AC_CONFIG_AUX_DIR(tool)
AC_CONFIG_MACRO_DIRS(tool/m4)

AC_PREREQ(2.67)

tooldir="$srcdir/tool"

dnl   override AC_CHECKING
dnl   placed here due to aclocal(1)'s
dnl   ignoring this definition in separate files
AC_DEFUN([AC_CHECKING],[dnl
AC_REQUIRE([_COLORIZE_RESULT_PREPARE])dnl
AS_MESSAGE([checking ${msg_checking}$1${msg_reset}...])])dnl

AC_DISABLE_OPTION_CHECKING

AC_ARG_VAR([cflags], [additional CFLAGS (ignored when CFLAGS is given)])
AC_ARG_VAR([cppflags], [additional CPPFLAGS (ignored when CPPFLAGS is given)])
AC_ARG_VAR([cxxflags], [additional CXXFLAGS (ignored when CXXFLAGS is given)])

: "environment section" && {
HAVE_BASERUBY=yes
BASERUBY_VERSION=
AC_ARG_WITH(baseruby,
	AS_HELP_STRING([--with-baseruby=RUBY], [use RUBY as baseruby; RUBY is the pathname of ruby]),
	[AS_CASE(["$withval"],
	    [*ruby*],[BASERUBY=$withval],
	    [no],[HAVE_BASERUBY=no],
	    [AC_MSG_ERROR(need ruby)])
	],
	[
		AC_PATH_PROG([BASERUBY], [ruby], [false])
	])
AS_IF([test "$HAVE_BASERUBY" != no -a "`RUBYOPT=- $BASERUBY --disable=gems -e 'print 42 if RUBY_VERSION > "2.2"' 2>/dev/null`" = 42], [
    BASERUBY="$BASERUBY --disable=gems"
    BASERUBY_VERSION=`$BASERUBY -v`
    $BASERUBY -C "$srcdir" tool/downloader.rb -d tool -e gnu config.guess config.sub >&AS_MESSAGE_FD
], [
    BASERUBY="echo executable host ruby is required.  use --with-baseruby option.; false"
    HAVE_BASERUBY=no
])
AC_SUBST(BASERUBY)
AC_SUBST(HAVE_BASERUBY)

: ${GIT=git}
HAVE_GIT=yes
AC_ARG_WITH(git,
	AS_HELP_STRING([--without-git], [never use git]),
	[AS_CASE([$withval],
	    [no],  [GIT=never-use HAVE_GIT=no],
	    [yes], [],
	    [GIT=$withval])])
AS_IF([test x"$HAVE_GIT" = xyes], [command -v "$GIT" > /dev/null || HAVE_GIT=no])
AC_SUBST(GIT)
AC_SUBST(HAVE_GIT)

eval `sed -n -e ['s/^@%:@define RUBY_[A-Z_]*VERSION_\([A-Z][A-Z][A-Z_0-9]*\) \([0-9][0-9]*\)$/\1=\2/p'] \
      -e ['s/^@%:@define \(RUBY_PATCHLEVEL\) \(.*\)/\1=\2/p'] \
     $srcdir/include/ruby/version.h $srcdir/version.h`
for v in MAJOR MINOR TEENY; do
    AS_IF([eval "test \"\$$v\" = ''"], [
	AC_MSG_ERROR(could not determine $v number from version.h)
    ])
done
AC_SUBST(MAJOR)
AC_SUBST(MINOR)
AC_SUBST(TEENY)
AC_SUBST(RUBY_API_VERSION, '$(MAJOR).$(MINOR)')
AC_SUBST(RUBY_PROGRAM_VERSION, '$(MAJOR).$(MINOR).$(TEENY)')

AS_IF([test "$program_prefix" = NONE], [
  program_prefix=
])
AS_IF([test "$prefix" -ef .], [
  AC_MSG_ERROR(--prefix cannot be the current working directory.)
])
RUBY_BASE_NAME=`echo ruby | sed "$program_transform_name"`
RUBYW_BASE_NAME=`echo rubyw | sed "$program_transform_name"`
AC_SUBST(RUBY_BASE_NAME)
AC_SUBST(RUBYW_BASE_NAME)
AC_SUBST(RUBY_VERSION_NAME, '${RUBY_BASE_NAME}-${ruby_version}')

dnl checks for alternative programs
AC_CANONICAL_BUILD
AC_CANONICAL_HOST
AC_CANONICAL_TARGET
AC_ARG_PROGRAM
RUBY_RM_RECURSIVE
AC_ARG_WITH(gcc,
	AS_HELP_STRING([--without-gcc], [never use gcc]),
	[
	AS_CASE([$withval],
	    [no],  [: ${CC=cc}],
	    [yes], [: ${CC=gcc}],
	           [CC=$withval])])
dnl If the user switches compilers, we can't believe the cache
AS_IF([test ! -z "$ac_cv_prog_CC" -a ! -z "$CC" -a "$CC" != "$ac_cv_prog_CC"], [
  AC_MSG_ERROR(cached CC is different -- throw away $cache_file
(it is also a good idea to do 'make clean' before compiling))
])
AS_CASE(["${build_os}"], [linux*|cygwin*], [
    AC_CHECK_TOOLS([CC], [gcc clang cc])
], [
    # OpenBSD wants to prefer cc over gcc.
    # See https://github.com/ruby/ruby/pull/2443
    AC_CHECK_TOOLS([CC], [cl.exe clang cc gcc c99 /usr/ucb/cc])
])

AC_ARG_VAR([AR],       [Archiver command])
AC_ARG_VAR([AS],       [Assembler command])
AC_ARG_VAR([CC],       [C compiler command])
AC_ARG_VAR([CXX],      [C++ compiler command])
AC_ARG_VAR([LD],       [Linker command])
AC_ARG_VAR([NM],       [Symbol list command])
AC_ARG_VAR([OBJCOPY],  [Objcopy command])
AC_ARG_VAR([OBJDUMP],  [Objdump command])
AC_ARG_VAR([RANLIB],   [Ranlib command])
AC_ARG_VAR([STRIP],    [Strip command])

# We don't want to bother things like `ccache gcc`, `clang -shared-libgcc`, ...
set rb_dummy ${CC}
rb_CC=$2
AS_CASE(["/${rb_CC} "],
[*@<:@\ /@:>@"cc "*], [
    # Don't try g++/clang++ when CC=cc
    AC_CHECK_TOOLS([CXX],    [cl.exe CC c++])
],
[*icc*],              [
    # Intel C++ has interprocedural optimizations.  It tends to come with its
    # own linker etc.
    AC_CHECK_TOOL([AR],      [`echo "${rb_CC}" | sed s/icc/xiar/`])
    AC_CHECK_TOOL([CXX],     [`echo "${rb_CC}" | sed s/icc/icpc/`])
    AC_CHECK_TOOL([LD],      [`echo "${rb_CC}" | sed s/icc/xild/`])
],
[*gcc*],              [
    # Dito for GCC.
    AC_CHECK_TOOL([LD],      [`echo "${rb_CC}" | sed s/gcc/ld/`])
    AC_CHECK_TOOL([AR],      [`echo "${rb_CC}" | sed s/gcc/gcc-ar/`])
    AC_CHECK_TOOL([CXX],     [`echo "${rb_CC}" | sed s/gcc/g++/`])
    AC_CHECK_TOOL([NM],      [`echo "${rb_CC}" | sed s/gcc/gcc-nm/`])
    AC_CHECK_TOOL([RANLIB],  [`echo "${rb_CC}" | sed s/gcc/gcc-ranlib/`])
],
[*clang*],            [
    # Dito for LLVM.  Note however that llvm-as is a LLVM-IR to LLVM bitcode
    # assembler that does not target your machine native binary.
    : ${LD:="${CC}"}         # ... try -fuse-ld=lld ?
    AC_CHECK_TOOL([AR],      [`echo "${rb_CC}" | sed s/clang/llvm-ar/`])
#   AC_CHECK_TOOL([AS],      [`echo "${rb_CC}" | sed s/clang/llvm-as/`])
    AC_CHECK_TOOL([CXX],     [`echo "${rb_CC}" | sed s/clang/clang++/`])
    AC_CHECK_TOOL([NM],      [`echo "${rb_CC}" | sed s/clang/llvm-nm/`])
    AC_CHECK_TOOL([OBJCOPY], [`echo "${rb_CC}" | sed s/clang/llvm-objcopy/`])
    AC_CHECK_TOOL([OBJDUMP], [`echo "${rb_CC}" | sed s/clang/llvm-objdump/`])
    AC_CHECK_TOOL([RANLIB],  [`echo "${rb_CC}" | sed s/clang/llvm-ranlib/`])
    AC_CHECK_TOOL([STRIP],   [`echo "${rb_CC}" | sed s/clang/llvm-strip/`])
])
AS_UNSET(rb_CC)
AS_UNSET(rb_dummy)

AS_CASE(["${build_os}"],
[solaris*], [
    AC_PATH_TOOL([LD], [ld], [/usr/ccs/bin/ld], [/usr/ccs/bin:$PATH])
],
[aix*], [
    AC_PATH_TOOL([NM], [nm], [/usr/ccs/bin/nm], [/usr/ccs/bin:$PATH])
])
AS_CASE(["${target_os}"],
[cygwin*|mingw*], [
    ac_cv_prog_ac_ct_OBJCOPY=":"
])

rb_test_CFLAGS=${CFLAGS+yes}
rb_test_CXXFLAGS=${CXXFLAGS+yes}

# BSD's ports and MacPorts prefix GNU binutils with 'g'
AC_PROG_CC_C99
AC_PROG_CXX
AC_PROG_CPP
AC_PROG_RANLIB
AC_CHECK_TOOLS([AR],      [gar ar])
AC_CHECK_TOOLS([AS],      [gas as])
AC_CHECK_TOOLS([LD],      [gld ld]) # ... try gold ?
AC_CHECK_TOOLS([NM],      [gnm nm])
AC_CHECK_TOOLS([OBJCOPY], [gobjcopy objcopy])
AC_CHECK_TOOLS([OBJDUMP], [gobjdump objdump])
AC_CHECK_TOOLS([STRIP],   [gstrip strip], [:])

AS_IF([test ! $rb_test_CFLAGS], [AS_UNSET(CFLAGS)]); AS_UNSET(rb_test_CFLAGS)
AS_IF([test ! $rb_test_CXXFLAGS], [AS_UNSET(CXXFLAGS)]); AS_UNSET(rb_save_CXXFLAGS)

AS_IF([test "${CXX}" = "g++" -a -z "${GXX}"], [
    # AC_PROG_CXX sets $CXX to "g++" when it purposefully finds that there is
    # _no_ g++.  This brain-damaged design must be worked around.  Thankfully,
    # similar thing doesn't happen for AC_PROG_CC.
    AC_MSG_NOTICE([C++ features disabled due to lack of a C++ compiler.])
    AS_UNSET(CXX)
])

test x"$target_alias" = x &&
target_os=`echo $target_os | sed 's/linux-gnu$/linux/;s/linux-gnu/linux-/'`
ac_install_sh='' # unusable for extension libraries.

AC_ARG_WITH(os-version-style,
	AS_HELP_STRING([--with-os-version-style=TYPE],
		       [OS version number for target and target_os [[full]]]
		       [(full|teeny|minor+0|minor|major+0|major|none)]),
	[os_version_style=$withval],
	[os_version_style=full
	    AS_CASE($target_os, [[*[0-9].*]],
		[AS_CASE([`/usr/bin/ruby -e 'puts RUBY_PLATFORM' 2>/dev/null`],
		    [[*-*[0-9].*.0]], [os_version_style=minor+0],
		    [[*-*[0-9].*.*]], [os_version_style=full],
		    [[*-*[0-9].0]  ], [os_version_style=major+0],
		    [[*-*[0-9].*]  ], [os_version_style=minor],
		    [[*-*[0-9]]    ], [os_version_style=major],
		)])
	])
os_version_style_transform=
AS_CASE("${os_version_style}",
	[full|teeny], [],
	[minor+0], [os_version_style_transform=['s/\([0-9]\.[0-9][0-9]*\)\.[0-9][.0-9]*$/\1.0/']],
	[minor],   [os_version_style_transform=['s/\([0-9]\.[0-9][0-9]*\)\.[0-9][.0-9]*$/\1/']],
	[major+0], [os_version_style_transform=['s/\([0-9]\)\.[0-9][.0-9]*$/\1.0/']],
	[major],   [os_version_style_transform=['s/\([0-9]\)\.[0-9][.0-9]*$/\1/']],
	[none],    [os_version_style_transform=['s/[0-9]*\.[0-9][.0-9]*$//']],
	[AC_MSG_ERROR(unknown --with-os-version-style: $withval)])
AS_IF([test -z "$target_alias" -a -n "$os_version_style_transform"],
	[
	target=`echo ${target} | sed "$os_version_style_transform"`
	target_os=`echo ${target_os} | sed "$os_version_style_transform"`
	])

AC_ARG_WITH(arch,
	AS_HELP_STRING([--with-arch=ARCHS],
		       [build an Apple/NeXT Multi Architecture Binary (MAB);
                          ARCHS is a comma-delimited list of architectures for
                          which to build; if this option is disabled or omitted
			  entirely, then the package will be built only for the
			  target platform]),
       [target_archs="$withval"], [unset target_archs])

AC_ARG_ENABLE(load-relative,
       AS_HELP_STRING([--enable-load-relative], [resolve load paths at run time]),
       [load_relative=$enableval])

dnl Checks for programs.

cflagspat=
test -z "$optflags" ||
    cflagspat="$cflagspat;s|"`eval echo '"'"${optflags}"'"' | sed 's/[[][|.*]]/\\&/g;s/^ */ /;s/ *$/ /'`'| |g'
test -z "$debugflags" ||
    cflagspat="$cflagspat;s|"`eval echo '"'"${debugflags}"'"' | sed 's/[[][|.*]]/\\&/g;s/^ */ /;s/ *$/ /'`'| |g'
test -z "$warnflags" ||
    cflagspat="$cflagspat;s|"`eval echo '"'"${warnflags}"'"' | sed 's/[[][|.*]]/\\&/g;s/^ */ /;s/ *$/ /'`'| |g'
AS_IF([test -z "${CFLAGS+set}"], [
    cflags=`echo " $cflags " | sed "$cflagspat;s/^ *//;s/ *$//"`
    orig_cflags="$cflags"
    cflags="$cflags "'${optflags} ${debugflags} ${warnflags}'
])
dnl AS_IF([test -z "${CXXFLAGS+set}"], [
dnl     cxxflags=`echo " $cxxflags " | sed "$cflagspat;s/^ *//;s/ *$//"`
dnl     orig_cxxflags="$cxxflags"
dnl     cxxflags="$cxxflags "'${optflags} ${debugflags} ${warnflags}'
dnl ])

AS_CASE(["$host_os:$build_os"],
[darwin*:darwin*], [
    # Following Apple deployed clang are broken
    # clang version 1.0 (http://llvm.org/svn/llvm-project/cfe/tags/Apple/clang-23 exported)
    # Apple clang version 2.0 (tags/Apple/clang-137) (based on LLVM 2.9svn)
    # Apple clang version 2.1 (tags/Apple/clang-163.7.1) (based on LLVM 3.0svn)
    AC_PREPROC_IFELSE(
	[AC_LANG_PROGRAM([
	    @%:@if defined __APPLE_CC__ && defined __clang_major__ && __clang_major__ < 3
	    @%:@error premature clang
	    @%:@endif
	])],
	[],
	[AC_MSG_ERROR([clang version 3.0 or later is required])])
])

AS_CASE(["$target_os"],
[darwin*], [
    AC_MSG_CHECKING(if minimum required OS X version is supported)
    AC_TRY_CPP([@%:@include <AvailabilityMacros.h>
	@%:@if MAC_OS_X_VERSION_MIN_REQUIRED < __MAC_10_5
	@%:@error pre OS X 10.5
	[!<===== pre OS X 10.5 =====>]
	@%:@endif
	],
	[macosx_min_required=yes],
	[AC_MSG_RESULT(no)
	AC_MSG_ERROR([Unsupported OS X version is required])])
    AC_MSG_RESULT(${macosx_min_required})
])

RUBY_MINGW32
AC_SUBST(GCC)
AC_SUBST(LD)
AS_IF([test "$GCC" = yes], [
    linker_flag=-Wl,
    : ${optflags=-O3}
    gcc_major=`echo =__GNUC__ | $CC -E -xc - | sed '/^=/!d;s///'`
    gcc_minor=`echo =__GNUC_MINOR__ | $CC -E -xc - | sed '/^=/!d;s///'`
    test -n "$gcc_major" || gcc_major=0
    test -n "$gcc_minor" || gcc_minor=0
    icc_version=`echo =__ICC | $CC -E -xc - | sed '/^=/!d;s///;/^__ICC/d'`
    test -n "$icc_version" || icc_version=0
    # RUBY_APPEND_OPTIONS(XCFLAGS, ["-include ruby/config.h" "-include ruby/missing.h"])
], [
    linker_flag=
])

AS_IF([test "$GCC" = yes -a "$gcc_major" -lt 3 ], [
    AC_MSG_ERROR([too old GCC])
])

RUBY_PROG_GNU_LD
RUBY_CPPOUTFILE

: ${OUTFLAG='-o '}
: ${COUTFLAG=${OUTFLAG}}
: ${CSRCFLAG=''}
AC_SUBST(OUTFLAG)
AC_SUBST(COUTFLAG)
AC_SUBST(CSRCFLAG)

: ${MJIT_CC=$CC}
AS_IF([test "x$cross_compiling" = xno], [
    AC_PATH_PROG([MJIT_CC], ${MJIT_CC})

    # if $CC is in /usr/lib/ccache/$CC, search original $CC (disable ccache)
    AS_IF([echo $RUBY_DEBUG | grep ci > /dev/null &&
           echo $MJIT_CC | grep ^/usr/lib/ccache > /dev/null], [
           PATH=`echo $PATH | sed "s/\/usr\/lib\/ccache://"` MJIT_CC=`which $CC`])

    AS_CASE([$target_os],
	[*mingw*], [command -v cygpath > /dev/null && MJIT_CC=`cygpath -ma $MJIT_CC`])
    shift 2
    MJIT_CC="$MJIT_CC${1+ }$*"
])

AS_CASE(["$build_os"],
  [darwin1*.*], [
    # Xcode linker warns for deprecated architecture and wrongly
    # installed TBD files.
    CC_WRAPPER=""
    echo 'int main(void) {return 0;}' > conftest.c
    AS_IF([$CC -framework Foundation -o conftest conftest.c 2>&1 |
	   grep '^ld: warning: text-based stub file' >/dev/null], [
	CC_WRAPPER=`cd -P "${tooldir}" && pwd`/darwin-cc
	CC="$CC_WRAPPER $CC"
    ])
    rm -fr conftest*
  ])

cc_version=
for option in --version -v -V -qversion; do
    cc_version_message=`$CC $option 2>&1`
    cc_version_status=$?
    AS_CASE($cc_version_status, [0], [:], [continue])
    AS_CASE($cc_version_message, [*Warning*], [continue])
    cc_version='$(CC) '$option
    break
done
AC_SUBST(CC_VERSION, $cc_version)
AC_SUBST(CC_VERSION_MESSAGE, $cc_version_message)

: ${DLDFLAGS="$LDFLAGS"}

RUBY_UNIVERSAL_ARCH
AS_IF([test "$target_cpu" != "$host_cpu" -a "$GCC" = yes -a "$cross_compiling" = no -a "${universal_binary:-no}" = no], [
    RUBY_DEFAULT_ARCH("$target_cpu")
])
host_os=$target_os
host_vendor=$target_vendor
host_cpu=$target_cpu
host=$target
host_alias=$target_alias

AC_CACHE_CHECK([for $AR flags], [rb_cv_arflags], [
    AS_IF([$AR rcD conftest.a > /dev/null 2>&1 && rm conftest.a],
	[rb_cv_arflags=rcD], [rb_cv_arflags=rcu])
])
AC_SUBST(ARFLAGS, ["$rb_cv_arflags "])
AC_SUBST(ASFLAGS)

AS_CASE(["$target_os"],
[cygwin*|mingw*], [
    AC_CHECK_TOOL(WINDRES, windres)
    AC_CHECK_TOOL(DLLWRAP, dllwrap)
    target=`echo $target | sed "s/^$target_cpu-/-/"`
    target_alias=`echo $target_alias | sed "s/^$target_cpu-/-/"`
    target_cpu=`echo $target_cpu | sed s/i.86/i386/`
    AS_CASE(["$target"], [-*], [ target="$target_cpu${target}"])
    AS_CASE(["$target_alias"], [-*], [ target_alias="$target_cpu${target_alias}"])
    AS_CASE(["$target_os"],
    [mingw*], [
	test "$rb_cv_msvcrt" = "" && unset rb_cv_msvcrt
	AC_CACHE_CHECK(for mingw32 runtime DLL, rb_cv_msvcrt, [
	AC_TRY_LINK([@%:@include <stdio.h>],
		    [FILE* volatile f = stdin; return 0;],
		    [rb_cv_msvcrt=`$OBJDUMP -p conftest$ac_exeext |
				   tr A-Z a-z |
				   sed -n '/^[[ 	]]*dll name: \(msvc.*\)\.dll$/{s//\1/p;q;}'`],
		    [rb_cv_msvcrt=msvcrt])
	test "$rb_cv_msvcrt" = "" && rb_cv_msvcrt=msvcrt])
	RT_VER=`echo "$rb_cv_msvcrt" | tr -cd [0-9]`
	test "$RT_VER" = "" && RT_VER=60
	AC_DEFINE_UNQUOTED(RUBY_MSVCRT_VERSION, $RT_VER)
	sysconfdir=
    ])
    : ${enable_shared=yes}
    ],
[hiuxmpp*], [AC_DEFINE(__HIUX_MPP__)])    # by TOYODA Eizi <toyoda@npd.kishou.go.jp>

AC_PROG_LN_S
AC_PROG_MAKE_SET
AC_PROG_INSTALL
AC_PROG_MKDIR_P
AS_IF([test "x$MKDIR_P" = "x -d"], [
  AS_IF([test x"$as_mkdir_p" != xfalse], [
    MKDIR_P='mkdir -p'
    echo "use 'mkdir -p' as MKDIR_P"
  ], [
    AC_MSG_ERROR([mkdir -p is required])
  ])
])
MAKEDIRS="$MKDIR_P"
AC_SUBST(MAKEDIRS)

AC_CHECK_PROG([DTRACE], [${ac_tool_prefix}dtrace], [${ac_tool_prefix}dtrace])
AS_IF([test "$cross_compiling:$ac_cv_prog_DTRACE" = no: -a -n "$ac_tool_prefix"], [
    AC_CHECK_PROG([DTRACE], [dtrace], [dtrace])
])

AC_CHECK_PROGS(DOT, dot)
AC_CHECK_PROGS(DOXYGEN, doxygen)

for prog in ${ac_tool_prefix:+${ac_tool_prefix}pkg-config} pkg-config; do
    AC_CHECK_PROG(PKG_CONFIG, $prog, [$prog], [], [],
        [`"$as_dir/$ac_word$ac_exec_ext" --print-errors --version > /dev/null 2>&1 || echo "$as_dir/$ac_word$ac_exec_ext"`])
    test -z "${PKG_CONFIG}" || break
done

# checks for UNIX variants that set C preprocessor variables
AC_USE_SYSTEM_EXTENSIONS

AC_MSG_CHECKING([whether it is Android])
AC_TRY_COMPILE([
	@%:@ifdef __ANDROID__
	@%:@error android
	@%:@endif
], [],
[AC_MSG_RESULT(no)],
[
	AC_MSG_RESULT(yes)
	target_os=${target_os}-android
	AC_MSG_CHECKING([for Android API version])
	AC_TRY_COMPILE([
		@%:@ifndef __ANDROID_API__
		@%:@error android
		@%:@endif
	], [],
	[AC_MSG_RESULT(defined by the compiler)],
	[
		rb_android_api=`getprop ro.build.version.sdk`
		AC_MSG_RESULT($rb_android_api)
		RUBY_APPEND_OPTIONS(CPPFLAGS, -D__ANDROID_API__=$rb_android_api)
	])
])

AC_SUBST(RM, ['rm -f'])
AC_SUBST(CP, ['cp'])
RMDIRS='$(top_srcdir)/tool/rmdirs'
RMDIR=rmdir
mkdir "rmdirs_$$_test" "rmdirs_$$_test/a"
rmdir --ignore-fail-on-non-empty "rmdirs_$$_test" 2>/dev/null &&
RMDIR='rmdir --ignore-fail-on-non-empty'
$RMDIR -p "rmdirs_$$_test/a" 2>/dev/null &&
{ test -d "rmdirs_$$_test" || RMDIRS="$RMDIR -p"; }
rmdir "rmdirs_$$_test/a" "rmdirs_$$_test" 2>/dev/null
AC_SUBST(RMDIR)
AC_SUBST(RMDIRS)
AC_SUBST(RMALL, ['rm -fr'])

AC_MSG_CHECKING([for cd using physical directory])
rm -fr conf$$.dir
mkdir conf$$.dir &&
(cd conf$$.dir && mkdir src build && cd src &&
$as_ln_s ../build . > /dev/null 2>&1 && cd build &&
for chdir in 'cd -P' 'PWD= cd'; do
    /bin/sh -c "$chdir ../src && echo '$chdir' > cdcmd" 2> /dev/null && break
done)
AS_IF([test -f conf$$.dir/src/cdcmd], [
    read CHDIR < conf$$.dir/src/cdcmd 2> /dev/null
], [
    CHDIR=cd
])
rm -fr conf$$.dir
AC_MSG_RESULT([$CHDIR])
AC_SUBST(CHDIR)
}

: "compiler section" && {
RUBY_WERROR_FLAG([
    AC_MSG_CHECKING([whether CFLAGS is valid])
    AC_TRY_COMPILE([], [],
	[AC_MSG_RESULT(yes)],
	[
	AC_MSG_RESULT(no)
	AC_MSG_ERROR([something wrong with CFLAGS="$CFLAGS"])
	]
    )

    AC_MSG_CHECKING([whether LDFLAGS is valid])
    {
	mkdir tmp.$$.try_link &&
	cd tmp.$$.try_link &&
	cp ../confdefs.h . &&
	echo '<?xml?><plist><dict><key>CFBundleIdentifier</key><string></string></dict></plist>' > Info.plist &&
	:
    } || AC_MSG_ERROR([failed to make temporary directory])
    AC_TRY_LINK([], [],
	[AC_MSG_RESULT(yes)],
	[
	cd .. && rm -fr tmp.$$.try_link
	AC_MSG_RESULT(no)
	AC_MSG_ERROR([something wrong with LDFLAGS="$LDFLAGS"])
	]
    )
    cd .. && rm -fr tmp.$$.try_link
])

: ${RPATHFLAG=''}
rpathflag=''
AS_IF([test x"${RPATHFLAG}" = x], [
    AS_CASE(["$target_os"],
	[hpux*], [AS_IF([test "$rb_cv_prog_gnu_ld" = no], [rpathflag='+b '])],
	[aix*], [rpathflag='-blibpath:'],
	[for rpathflag in -R "-rpath "; do
	    AS_CASE("$rpathflag",
		    [*" "], [AS_CASE(["${linker_flag}"],
				     [*,], [rpathflag=`echo "$rpathflag" | tr ' ' ,`])])
	    rpathflag="${linker_flag}${rpathflag}"
	    RUBY_TRY_LDFLAGS([${rpathflag}.], [], [rpathflag=])
	    AS_IF([test "x${rpathflag}" != x], [])
        done])
], [
    rpathflag=`echo "$RPATHFLAG" | sed 's/%.*//'`
])

RUBY_TRY_CFLAGS(-fdeclspec, [
  RUBY_APPEND_OPTIONS(CC, -fdeclspec)
  RUBY_APPEND_OPTIONS(MJIT_CC, -fdeclspec)
])
RUBY_TRY_CXXFLAGS(-fdeclspec, [RUBY_APPEND_OPTIONS(CXX, -fdeclspec)])

AS_CASE([$RUBY_PATCHLEVEL], [-*],
	[RUBY_DEVEL=yes], [RUBY_DEVEL=no])
particular_werror_flags=$RUBY_DEVEL
AC_ARG_ENABLE(werror,
	AS_HELP_STRING([--disable-werror],
		       [don't make warnings into errors
		       even if a compiler support -Werror feature
		       [[disabled by default unless development version]]]),
	[particular_werror_flags=$enableval])

rb_cv_warnflags="$warnflags"
AS_CASE(["$GCC:${warnflags+set}:${extra_warnflags:+set}:"],
[yes::*|yes:*:set:], [# GCC && (!warnflags || extra_warnflags)
    AS_IF([test $gcc_major -ge 4], [
	extra_warnflags="$extra_warnflags -Werror=extra-tokens"
    ])
    AS_IF([test $gcc_major -ge 5 -a $gcc_major -le 6], [
	extra_warnflags="$extra_warnflags -Wno-maybe-uninitialized"
    ])
    # ICC doesn't support -Werror=
    AS_IF([test $icc_version -gt 0], [
	particular_werror_flags=no
    ])
    for wflag in \
		 -Werror=deprecated-declarations \
		 -Werror=division-by-zero \
		 -Werror=duplicated-cond \
		 -Werror=implicit-function-declaration \
		 -Werror=implicit-int \
		 -Werror=misleading-indentation \
		 -Werror=pointer-arith \
		 -Werror=shorten-64-to-32 \
		 -Werror=write-strings \
		 -Wimplicit-fallthrough=0 \
		 -Wmissing-noreturn \
		 -Wno-cast-function-type \
		 -Wno-constant-logical-operand \
		 -Wno-long-long \
		 -Wno-missing-field-initializers \
		 -Wno-overlength-strings \
		 -Wno-packed-bitfield-compat \
		 -Wno-parentheses-equality \
		 -Wno-self-assign \
		 -Wno-tautological-compare \
		 -Wno-unused-parameter \
		 -Wno-unused-value \
		 -Wsuggest-attribute=format \
		 -Wsuggest-attribute=noreturn \
		 -Wunused-variable \
		 -diag-disable=175,188,1684,2259,2312 \
		 $extra_warnflags \
		 ; do
	AS_IF([test "$particular_werror_flags" != yes], [
	    wflag=`echo x$wflag | sed 's/^x-Werror=/-W/;s/^x//'`
	])
	ok=no
	RUBY_TRY_CFLAGS($wflag, [
	    RUBY_APPEND_OPTIONS(warnflags, $wflag)
	    ok=yes
	])
	AS_CASE([$ok:$wflag], [no:-Werror=*], [
	    wflag=`echo x$wflag | sed 's/^x-Werror=/-W/'`
	    RUBY_TRY_CFLAGS($wflag, [
		RUBY_APPEND_OPTIONS(warnflags, $wflag)
		particular_werror_flags=no
	    ])
	])
    done
    AS_CASE([" $warnflags "],[*" -Wno-missing-field-initializers "*], [wflag="-Wall -Wextra"],
                             [wflag=-Wall])
    RUBY_TRY_CFLAGS($wflag, [warnflags="$wflag${warnflags+ $warnflags}"])
    # Disable warnflags while conftest. -Werror=* flags might make bad OS capability guess.
    rb_cv_warnflags="$warnflags"
    warnflags=
])
RUBY_TRY_CFLAGS(-Qunused-arguments, [RUBY_APPEND_OPTIONS(rb_cv_wsuppress_flags, -Qunused-arguments)])
AC_COMPILE_IFELSE([
    AC_LANG_PROGRAM([
@%:@if !(defined(__SUNPRO_C)||defined(__SUNPRO_CC))
@%:@error not sunpro
@%:@endif],[])], [
    for e in \
        E_STATEMENT_NOT_REACHED \
        E_INIT_SIGN_EXTEND \
        E_INIT_DOES_NOT_FIT \
        E_INITIALIZATION_TYPE_MISMATCH
    do
        RUBY_TRY_CFLAGS([-erroff=${e}], [
            RUBY_APPEND_OPTIONS(rb_cv_warnflags, [-erroff=${e}])
        ])
    done
])

AC_ARG_WITH(compress-debug-sections,
	AS_HELP_STRING([--with-compress-debug-sections=type],
	    [enable debug section compression]),
	[compress_debug_sections=$withval], [compress_debug_sections=])

AS_IF([test "$GCC" = yes], [
    # -D_FORTIFY_SOURCE
    # When defined _FORTIFY_SOURCE, glibc enables some additional sanity
    # argument check. The performance drop is very little and Ubuntu enables
    # _FORTIFY_SOURCE=2 by default. So, let's support it for protecting us from
    # a mistake of silly C extensions.

    # TODO: check if link succeeds with _FORTIFY_SOURCE=2.
    AS_CASE(["$target_os"],
    [mingw*], [
	fortify_source=no
    ])
    AC_ARG_ENABLE(fortify_source,
		  AS_HELP_STRING([--disable-fortify-source],
				 [disable -D_FORTIFY_SOURCE=2 option, which causes link error on mingw]),
		  [fortify_source=$enableval])
    AS_IF([test "x$fortify_source" != xno], [
        RUBY_TRY_CFLAGS([$optflags -D_FORTIFY_SOURCE=2], [RUBY_APPEND_OPTION(XCFLAGS, -D_FORTIFY_SOURCE=2)], [],
                        [@%:@include <stdio.h>])
    ])

    : ${MJIT_HEADER_FLAGS='-P -dD'}

    # -fstack-protector
    AS_CASE(["$target_os"],
    [mingw*], [
	stack_protector=no
    ])
    AS_IF([test -z "${stack_protector+set}"], [
	AS_FOR(option, opt, [-fstack-protector-strong -fstack-protector], [
	    RUBY_TRY_CFLAGS(option, [stack_protector=yes])
	    AS_IF([test "x$stack_protector" = xyes], [
		RUBY_TRY_LDFLAGS(option, [], [stack_protector=])
	    ])
	    AS_IF([test "x$stack_protector" = xyes], [stack_protector=option; break])
	])
    ])
    AS_CASE(["$stack_protector"], [-*], [
	RUBY_APPEND_OPTION(XCFLAGS, $stack_protector)
	RUBY_APPEND_OPTION(XLDFLAGS, $stack_protector)
	RUBY_APPEND_OPTION(LDFLAGS, $stack_protector)
    ])

    AS_CASE("${compress_debug_sections:-zlib}",
    [none|no], [], [
    RUBY_TRY_LDFLAGS(${linker_flag}--compress-debug-sections=${compress_debug_sections:-zlib},
		     [compress_debug_sections=${compress_debug_sections:-zlib}],
		     [compress_debug_sections=no])
    ])
    AS_IF([test "x$compress_debug_sections" != xno], [
	RUBY_APPEND_OPTION(DLDFLAGS, ${linker_flag}--compress-debug-sections=$compress_debug_sections)
    ])

    AS_CASE(["$target_os"],[mingw*], [
      # On  Windows  platforms,   system  provided  headers  are  VC++
      # optimized.  That  is, C++  habits are often  contaminated into
      # various  headers.  Most frequent  situation is  the use  of //
      # comments.   We  bypass  ANSI   C  mode  for  them.   Otherwise
      # extension libs cannot include those headers.

      # Since math.h in some mingw64 wrongly declares frexp and modf
      # to be pure, the variables pointed by the second arguments are
      # considered uninitialized unexpectedly.
      AC_CACHE_CHECK([whether frexp and modf are broken],
	rb_cv_mingw64_broken_frexp_modf,
	[
	  save_CFLAGS="$CFLAGS"
	  AS_IF([test "$particular_werror_flags" = "yes"], [
	    CFLAGS="$CFLAGS -Werror=uninitialized"
	  ], [
	    CFLAGS="$CFLAGS -Werror -Wuninitialized"
	  ])
	  AC_TRY_COMPILE([@%:@include <math.h>
	    int foo(double x)
	    {
	      int exp;
	      frexp(x, &exp);
	      return exp;
	    }], [if (foo(0.0)) return 1;],
	    [rb_cv_mingw64_broken_frexp_modf=no],
	    [rb_cv_mingw64_broken_frexp_modf=yes])
	  CFLAGS="$save_CFLAGS"
	])
      AS_IF([test "$rb_cv_mingw64_broken_frexp_modf" = yes], [
	AC_DEFINE(RUBY_MINGW64_BROKEN_FREXP_MODF)
      ])
    ],
    [cygwin*|darwin*|netbsd*], [
      # need lgamma_r(), finite()
    ])

    # ANSI (no XCFLAGS because this is C only)
    AS_CASE(["$target_os"],
    [solaris*], [
      # Because "-std=gnu99" affects existence of functions on Solaris,
      # "-std=gnu99" will be appended to CPPFLAGS.
	for ansi_options in -std=gnu99; do
	    RUBY_TRY_CFLAGS(${ansi_options}, [
		RUBY_APPEND_OPTIONS(CPPFLAGS, ${ansi_options})
	    ], [ansi_options=])
	    test "x${ansi_options}" = x || break
	done
    ],
    [
      # ANSI (no XCFLAGS because this is C only)
      rb_tmp_std_check=`echo $CC $CFLAGS $optflags $warnflags $debugflags | fgrep std= | tr -d  '\015'`
      AS_IF([test "x$rb_tmp_std_check" = "x"],
      [
	for ansi_options in -std=gnu99; do
	    RUBY_TRY_CFLAGS(${ansi_options}, [
		RUBY_APPEND_OPTIONS(warnflags, ${ansi_options})
		RUBY_APPEND_OPTIONS(strict_warnflags, ${ansi_options})
	    ], [ansi_options=])
	    test "x${ansi_options}" = x || break
	done
      ])
    ])

    # suppress annoying -Wstrict-overflow warnings
    RUBY_TRY_CFLAGS(-fno-strict-overflow, [RUBY_APPEND_OPTION(XCFLAGS, -fno-strict-overflow)])

    test "${debugflags+set}" || {RUBY_TRY_CFLAGS(-ggdb3, [debugflags=-ggdb3])}
    test "${debugflags+set}" || {RUBY_TRY_CFLAGS(-ggdb, [debugflags=-ggdb])}
    test "${debugflags+set}" || {RUBY_TRY_CFLAGS(-g3, [debugflags=-g3])}
])
test $ac_cv_prog_cc_g = yes && : ${debugflags=-g}
AS_IF([test "x$RUBY_DEVEL" = xyes], [RUBY_APPEND_OPTION(XCFLAGS, -DRUBY_DEVEL=1)])

AS_IF([test "$GCC" = ""], [
    AS_CASE(["$target_os"],[aix*],[warnflags="$warnflags -qinfo=por" rb_cv_warnflags="$rb_cv_warnflags -qinfo=por"])
])
AS_IF([test "$GCC" = yes], [
    AS_IF([test "$gcc_major" -ge 4], [
	RUBY_TRY_CFLAGS(-fvisibility=hidden, [visibility_option=yes], [visibility_option=no])
    ])
    AC_SUBST(WERRORFLAG, "-Werror")
    AS_IF([test "$visibility_option" = yes], [
	RUBY_APPEND_OPTION(XCFLAGS, -fvisibility=hidden)
	AC_DEFINE(RUBY_SYMBOL_EXPORT_BEGIN, [_Pragma("GCC visibility push(default)")])
	AC_DEFINE(RUBY_SYMBOL_EXPORT_END,   [_Pragma("GCC visibility pop")])
    ], [
	RUBY_TRY_LDFLAGS([-Wl,-unexported_symbol,_Init_*], [visibility_option=ld], [visibility_option=no])
    ])
    test "$visibility_option" = no || OBJCOPY=:
])

AS_IF([test "$GCC" = yes], [
    # optflags

    AS_CASE(["$target_os"], [mingw*], [
	RUBY_TRY_CFLAGS(-fno-omit-frame-pointer, [optflags="${optflags+$optflags }-fno-omit-frame-pointer"])
	RUBY_TRY_CFLAGS(-static-libgcc, [static_libgcc=yes], [static_libgcc=no])
	AS_IF([test "$static_libgcc" = yes], [
	    RUBY_APPEND_OPTION(EXTLDFLAGS, -static-libgcc)
	])
    ])

    # disable fast-math
    for oflag in -fno-fast-math; do
	RUBY_TRY_CFLAGS($oflag, [RUBY_APPEND_OPTION(CFLAGS, $oflag)])
    done
    for oflag in -fexcess-precision=standard -fp-model\ precise; do
	RUBY_TRY_CFLAGS($oflag, [RUBY_APPEND_OPTION(XCFLAGS, $oflag)])
    done
])

AS_CASE(["$target_cpu"], [[i[3-6]86*]], [
    AC_CACHE_CHECK([for __sync_val_compare_and_swap], [rb_cv_gcc_compiler_cas], [
	AC_TRY_LINK([unsigned long atomic_var;],
	    [__sync_val_compare_and_swap(&atomic_var, 0, 1);],
	    [rb_cv_gcc_compiler_cas=yes],
	    [
	    save_CFLAGS="$CFLAGS" CFLAGS="$CFLAGS -march=i486"
	    AC_TRY_LINK([unsigned long atomic_var;],
		[__sync_val_compare_and_swap(&atomic_var, 0, 1);],
		[rb_cv_gcc_compiler_cas=i486],
		[rb_cv_gcc_compiler_cas=no])
	    CFLAGS="$save_CFLAGS"
	    ])
    ])
    AS_IF([test "$rb_cv_gcc_compiler_cas" = i486], [ARCH_FLAG="-march=i486"])
])

AC_ARG_WITH(opt-dir,
	AS_HELP_STRING([--with-opt-dir=DIR-LIST],
		       [add optional headers and libraries directories separated by $PATH_SEPARATOR]),
	[
		val=`echo "$PATH_SEPARATOR$withval" | sed "s|$PATH_SEPARATOR\([[^$PATH_SEPARATOR]*]\)| -I\1/include|g;s/^ //"`
		CPPFLAGS="$CPPFLAGS $val"
		val=`echo "$PATH_SEPARATOR$withval" | sed "s|$PATH_SEPARATOR\([[^$PATH_SEPARATOR]*]\)| -L\1/lib${rpathflag:+ $rpathflag\\\\1/lib}|g;s/^ //"`
		LDFLAGS="$LDFLAGS $val"
		LDFLAGS_OPTDIR="$val"
		OPT_DIR="$withval"
	], [OPT_DIR=])

test -z "${ac_env_CFLAGS_set}" -a -n "${cflags+set}" && eval CFLAGS="\"$cflags $ARCH_FLAG\""
test -z "${ac_env_CXXFLAGS_set}" -a -n "${cxxflags+set}" && eval CXXFLAGS="\"$cxxflags $ARCH_FLAG\""
}

AC_CACHE_CHECK([whether compiler has statement and declarations in expressions],
  rb_cv_have_stmt_and_decl_in_expr,
  [AC_TRY_COMPILE([],[ __extension__ ({ int a = 0; a; }); ],
  [rb_cv_have_stmt_and_decl_in_expr=yes],
  [rb_cv_have_stmt_and_decl_in_expr=no])])
AS_IF([test "$rb_cv_have_stmt_and_decl_in_expr" = yes], [
  AC_DEFINE(HAVE_STMT_AND_DECL_IN_EXPR)
])

: "header and library section" && {
AC_ARG_WITH(winnt-ver,
  AS_HELP_STRING([--with-winnt-ver=0xXXXX], [target Windows NT version (default to 0x0600)]),
  [with_winnt_ver="$withval"], [with_winnt_ver="0x0600"])
AS_CASE(["$target_os"],
[mingw*], [
  RUBY_APPEND_OPTION(CPPFLAGS, -D_WIN32_WINNT=$with_winnt_ver)
  RUBY_APPEND_OPTION(CPPFLAGS, -D__MINGW_USE_VC2005_COMPAT)
])

AS_CASE(["$target_os"],
[freebsd*], [
  AC_CACHE_CHECK([whether pthread should be enabled by default],
    rb_cv_enable_pthread_default,
    [AC_TRY_CPP([
#include <osreldate.h>
#if __FreeBSD_version < 502102
#error pthread should be disabled on this platform
#endif
      ],
      rb_cv_enable_pthread_default=yes,
      rb_cv_enable_pthread_default=no)])
  enable_pthread=$rb_cv_enable_pthread_default
  ],
[mingw*], [
  enable_pthread=no
  ],
[
  enable_pthread=yes
  ])

dnl Checks for libraries.
AS_CASE(["$target_os"],[*bsd*|dragonfly*],[],[ac_cv_func_daemon=no])

AS_UNSET(ORIG_LIBS)
POSTLINK=:
AC_SUBST(POSTLINK)
AS_CASE(["$target_os"],
[nextstep*], [	],
[openstep*], [	],
[rhapsody*], [	],
[darwin*], [
		ORIG_LIBS="$LIBS"
		RUBY_PREPEND_OPTION(LIBS, -lobjc)
		RUBY_APPEND_OPTIONS(CPPFLAGS, -D_XOPEN_SOURCE -D_DARWIN_C_SOURCE -D_DARWIN_UNLIMITED_SELECT -D_REENTRANT)
		AC_CACHE_CHECK([whether syscall(2) is deprecated], rb_cv_syscall_deprecated,
		    [RUBY_WERROR_FLAG([
			AC_TRY_COMPILE([@%:@include <unistd.h>],
				       [if (syscall(0)) return 1;],
			    [rb_cv_syscall_deprecated=no],
			    [rb_cv_syscall_deprecated=yes])])])
		AS_IF([test $rb_cv_syscall_deprecated = yes], [
		    ac_cv_func___syscall=no
		    ac_cv_func_syscall=no
		    ac_cv_header_sys_syscall_h=no
		    ac_cv_header_syscall_h=no
		])
		ac_cv_func_getcontext=no
		ac_cv_func_setcontext=no
		incs=`$CC -v -E -xc - < /dev/null 2>&1 | sed ['1,/^@%:@include </d;s/^ *//;s|[^./][^/]*/\.\./||g;/\/include$/!d;s||/lib|;/\/usr\/lib/d']`
		for d in `$CC -print-search-dirs | sed -e '/^libraries: */!d;s///' | tr : '\012' | fgrep -v /../ | sed -n 's|^\(/.*/lib\)/$|\1|p'`; do
		    incs=`echo "$incs" | fgrep -v "$d"`
		done
		for d in $incs; do
		    test -d "$d" && RUBY_APPEND_OPTIONS(LDFLAGS, "-L$d")
		done
		ac_cv_type_getgroups=gid_t # getgroups() on Rosetta fills garbage
		ac_cv_lib_crypt_crypt=no
		ac_cv_func_fdatasync=no # Mac OS X wrongly reports it has fdatasync()
		ac_cv_func_vfork=no
		AS_IF([test $gcc_major -lt 4 -o \( $gcc_major -eq 4 -a $gcc_minor -lt 3 \)], [
		    ac_cv_func___builtin_setjmp=no
		])
		with_setjmp_type=sigsetjmp # to hijack SIGCHLD handler
		AC_CACHE_CHECK(for broken crypt with 8bit chars, rb_cv_broken_crypt,
		    [AC_TRY_RUN([
#include <stdio.h>
#include <unistd.h>
#include <string.h>

void
broken_crypt(const char *salt, const char *buf1, const char *buf2)
{
#if 0
    printf("%.2x%.2x: %s -> %s\n", (unsigned char)salt[0], (unsigned char)salt[1],
	   buf1+2, buf2+2);
#endif
}

int
main()
{
    int i;
    char salt[2], buf[256], *s;
    for (i = 0; i < 128*128; i++) {
	salt[0] = 0x80 | (i & 0x7f);
	salt[1] = 0x80 | (i >> 7);
	strcpy(buf, crypt("", salt));
	if (strcmp(buf, s = crypt("", salt))) {
	    broken_crypt(salt, buf, s);
	    return 1;
	}
    }
    salt[0] = salt[1] = ' ';
    strcpy(buf, crypt("", salt));
    salt[0] = salt[1] = 0x80 | ' ';
    if (strcmp(buf, s = crypt("", salt))) {
	broken_crypt(salt, buf, s);
	return 1;
    }
    return 0;
}
],
		    rb_cv_broken_crypt=no,
		    rb_cv_broken_crypt=yes,
		    rb_cv_broken_crypt=yes)])
		AS_IF([test "$rb_cv_broken_crypt" = yes], [
		   AC_DEFINE(BROKEN_CRYPT, 1)
		])
		POSTLINK=""
		AC_CHECK_PROGS(codesign, codesign)
		AC_CHECK_PROGS(dsymutil, dsymutil)
		AS_IF([test -n "$codesign"], [
		    POSTLINK="{ test -z '\$(RUBY_CODESIGN)' || $codesign -s '\$(RUBY_CODESIGN)' -f \$@; }${POSTLINK:+; $POSTLINK}"
		])
		AS_IF([test -n "$dsymutil"], [
		    POSTLINK="$dsymutil \$@${POSTLINK:+; $POSTLINK}"
		])
		AS_IF([test -n "${POSTLINK}"], [
		    LINK_SO="$LINK_SO
\$(POSTLINK)"
		])
		AC_CHECK_HEADERS(crt_externs.h, [], [], [
		    #include <crt_externs.h>
		])
		],
[hpux*], [	LIBS="-lm $LIBS"
		ac_cv_c_inline=no],
[solaris*], [	LIBS="-lm $LIBS"
		ac_cv_func_vfork=no
		AC_MSG_CHECKING(whether _XOPEN_SOURCE is already given)
		AC_TRY_COMPILE([#include <unistd.h>
			#ifndef _XOPEN_SOURCE
			#error _XOPEN_SOURCE is not defined
			#endif
			], [],
		        [given_xopen_source=yes], [given_xopen_source=no])
		AC_MSG_RESULT($given_xopen_source)
		AS_IF([test $given_xopen_source = no], [
		  AC_MSG_CHECKING(appropriate _XOPEN_SOURCE value to define)
		  define_xopen_source=""
		  for tmp_xpg in 7 6 5; do
		    AS_IF([test x"$define_xopen_source" != x], [
		      break
		    ])
		    RUBY_WERROR_FLAG([AC_TRY_COMPILE([
			#define _XOPEN_SOURCE ${tmp_xpg}00
			#include <unistd.h>
			#ifndef _XPG${tmp_xpg}
			#error _XPG${tmp_xpg} should be defined by _XOPEN_SOURCE=${tmp_xpg}00
			#endif
			], [],
			[define_xopen_source=${tmp_xpg}00], [])
			])
		  done
		  AS_IF([test x"$define_xopen_source" = x], [
		    define_xopen_source=no
		  ])
		  AC_MSG_RESULT($define_xopen_source)
		  AS_IF([test x"$define_xopen_source" != xno], [
		    RUBY_APPEND_OPTIONS(CPPFLAGS, -D_XOPEN_SOURCE=$define_xopen_source)
		  ])
		])
		],
[haiku*], [
		LIBS="$LIBS" # m lib is include in root
		],
[cygwin*], [	ac_cv_header_langinfo_h=yes
		RUBY_APPEND_OPTIONS(CPPFLAGS, -D_XOPEN_SOURCE -D_GNU_SOURCE)
		AC_CHECK_FUNCS(cygwin_conv_path)
		AC_LIBOBJ([langinfo])
		],
[mingw*], [	LIBS="-lshell32 -lws2_32 -liphlpapi -limagehlp -lshlwapi $LIBS"
		ac_cv_header_a_out_h=no
		ac_cv_header_pwd_h=no
		ac_cv_header_utime_h=no
		ac_cv_header_sys_ioctl_h=no
		ac_cv_header_sys_param_h=no
		ac_cv_header_sys_resource_h=no
		ac_cv_header_sys_select_h=no
		ac_cv_header_sys_time_h=no
		ac_cv_header_sys_times_h=no
		ac_cv_header_sys_socket_h=no
		ac_cv_func_lstat=yes
		ac_cv_func_times=yes
		ac_cv_func_waitpid=yes
		ac_cv_func_fsync=yes
		ac_cv_func_seekdir=yes
		ac_cv_func_telldir=yes
		ac_cv_func_lchown=yes
		ac_cv_func_link=yes
		ac_cv_func_readlink=yes
		ac_cv_func_symlink=yes
		ac_cv_lib_crypt_crypt=no
		ac_cv_func_getpgrp_void=no
		ac_cv_func_memcmp_working=yes
		ac_cv_lib_dl_dlopen=no
		rb_cv_binary_elf=no
		rb_cv_negative_time_t=no
		ac_cv_func_fcntl=yes
		ac_cv_func_flock=yes
		ac_cv_func_gmtime_r=yes
		rb_cv_large_fd_select=yes
		ac_cv_type_struct_timeval=yes
                ac_cv_func_clock_gettime=yes
                ac_cv_func_clock_getres=yes
		ac_cv_func_malloc_usable_size=no
		ac_cv_type_off_t=yes
		ac_cv_sizeof_off_t=8
		AS_IF([test "$target_cpu" = x64], [
		    ac_cv_func___builtin_setjmp=yes
		    ac_cv_func_round=no
		    rb_cv_coroutine=yes
		])
		ac_cv_func_tgamma=no
		rb_cv_negative_time_t=yes
		AC_CHECK_TYPE([NET_LUID], [], [],
			      [@%:@include <winsock2.h>
			      @%:@include <iphlpapi.h>])
		AS_IF([test x"$ac_cv_type_NET_LUID" = xyes], [
		    AC_DEFINE(HAVE_TYPE_NET_LUID, 1)
		])
		AC_CHECK_FUNCS(_gmtime64_s)
		AC_CHECK_FUNCS(_wfreopen_s)
		AC_LIBOBJ([langinfo])
		],
[bsdi*], [	LIBS="-lm $LIBS"
		AC_DEFINE(BROKEN_SETREUID, 1)
		AC_DEFINE(BROKEN_SETREGID, 1)
                ac_cv_sizeof_rlim_t=8],
[freebsd*], [	LIBS="-lm $LIBS"
		ac_cv_func_getpeername=no
		ac_cv_func_getsockname=no
		ac_cv_func_shutdown=no
		ac_cv_func_close=no
		],
[netbsd*], [	LIBS="-lm $LIBS"
		],
[dragonfly*], [	LIBS="-lm $LIBS"
		],
[aix*],[	LIBS="-lm $LIBS"
		ac_cv_func_round=no
		ac_cv_func___builtin_setjmp=no
		],
[linux*],[	LIBS="-lm $LIBS"
		# __builtin_longjmp in ppc64* Linux does not restore
		# the TOC register (r2), which is problematic
		# when a global exit happens from JITted .so code.
		AS_CASE(["$target_cpu"], [powerpc64*], [
			ac_cv_func___builtin_setjmp=no
		])
		# With gcc-8's -fcf-protection, MJIT's __builtin_longjmp fails.
		AS_CASE(["$CC $CFLAGS "], [*" -fcf-protection "*], [cf_protection=yes], [cf_protection=no])
		AS_IF([test "$cf_protection" = yes], [
			ac_cv_func___builtin_setjmp=no
		])
		],
[	LIBS="-lm $LIBS"])
: ${ORIG_LIBS=$LIBS}

AS_IF([test -n "${CXX}"], [
    RUBY_WERROR_FLAG([
        AC_MSG_CHECKING([whether CXXFLAGS is valid])
        AC_LANG_PUSH(C++)
        AC_TRY_COMPILE([@%:@include <cstdio>], [], [AC_MSG_RESULT(yes)], [
            AC_MSG_RESULT(no)
            # The message mentions CXXFLAGS, but CPPFLAGS might also affects.
            AC_MSG_WARN([something wrong with CXXFLAGS="$CXXFLAGS"])
            CXX=false
        ])
        AC_LANG_POP(C++)
    ])
])

AC_CHECK_LIB(crypt, crypt)      # glibc (GNU/Linux, GNU/Hurd, GNU/kFreeBSD)
AC_CHECK_LIB(dl, dlopen)	# Dynamic linking for SunOS/Solaris and SYSV
AC_CHECK_LIB(dld, shl_load)	# Dynamic linking for HP-UX
AC_CHECK_LIB(socket, shutdown)  # SunOS/Solaris

dnl Checks for header files.
AC_HEADER_DIRENT
dnl AC_HEADER_STDC has been checked in AC_USE_SYSTEM_EXTENSIONS
AC_HEADER_STDBOOL
AC_HEADER_SYS_WAIT

AC_CHECK_HEADERS(a.out.h)
AC_CHECK_HEADERS(atomic.h)
AC_CHECK_HEADERS(copyfile.h)
AC_CHECK_HEADERS(direct.h)
AC_CHECK_HEADERS(grp.h)
AC_CHECK_HEADERS(fcntl.h)
AC_CHECK_HEADERS(float.h)
AC_CHECK_HEADERS(ieeefp.h)
AC_CHECK_HEADERS(intrinsics.h)
AC_CHECK_HEADERS(langinfo.h)
AC_CHECK_HEADERS(limits.h)
AC_CHECK_HEADERS(locale.h)
AC_CHECK_HEADERS(malloc.h)
AC_CHECK_HEADERS(malloc/malloc.h)
AC_CHECK_HEADERS(malloc_np.h)
AC_CHECK_HEADERS(net/socket.h)
AC_CHECK_HEADERS(process.h)
AC_CHECK_HEADERS(pwd.h)
AC_CHECK_HEADERS(sanitizer/asan_interface.h)
AC_CHECK_HEADERS(sanitizer/msan_interface.h)
AC_CHECK_HEADERS(setjmpex.h)
AC_CHECK_HEADERS(stdalign.h)
AC_CHECK_HEADERS(sys/attr.h)
AC_CHECK_HEADERS(sys/eventfd.h)
AC_CHECK_HEADERS(sys/fcntl.h)
AC_CHECK_HEADERS(sys/file.h)
AC_CHECK_HEADERS(sys/id.h)
AC_CHECK_HEADERS(sys/ioctl.h)
AC_CHECK_HEADERS(sys/mkdev.h)
AC_CHECK_HEADERS(sys/param.h)
AC_CHECK_HEADERS(sys/prctl.h)
AC_CHECK_HEADERS(sys/resource.h)
AC_CHECK_HEADERS(sys/select.h)
AC_CHECK_HEADERS(sys/sendfile.h)
AC_CHECK_HEADERS(sys/socket.h)
AC_CHECK_HEADERS(sys/syscall.h)
AC_CHECK_HEADERS(sys/sysmacros.h)
AC_CHECK_HEADERS(sys/time.h)
AC_CHECK_HEADERS(sys/times.h)
AC_CHECK_HEADERS(sys/uio.h)
AC_CHECK_HEADERS(sys/utime.h)
AC_CHECK_HEADERS(syscall.h)
AC_CHECK_HEADERS(time.h)
AC_CHECK_HEADERS(ucontext.h)
AC_CHECK_HEADERS(utime.h)
AC_CHECK_HEADERS(x86intrin.h)

AC_ARG_WITH([gmp],
  [AS_HELP_STRING([--without-gmp],
    [disable GNU GMP to accelerate Bignum operations])],
  [],
  [with_gmp=yes])
AS_IF([test "x$with_gmp" != xno],
  [AC_CHECK_HEADERS(gmp.h)
   AS_IF([test "x$ac_cv_header_gmp_h" != xno],
     AC_SEARCH_LIBS([__gmpz_init], [gmp],
       [AC_DEFINE(HAVE_LIBGMP, 1)]))])

AC_ARG_WITH([jemalloc],
  [AS_HELP_STRING([--with-jemalloc],[use jemalloc allocator])],
  [with_jemalloc=$withval], [with_jemalloc=no])
AS_IF([test "x$with_jemalloc" != xno],[
  AC_SEARCH_LIBS([malloc_conf], [jemalloc],
    [
      AC_DEFINE(HAVE_LIBJEMALLOC, 1)
      with_jemalloc=yes
    ],
    [test x$with_jemalloc = xyes && with_jemalloc=no])
  AC_CHECK_HEADER(jemalloc/jemalloc.h, [
    AC_DEFINE(RUBY_ALTERNATIVE_MALLOC_HEADER, [<jemalloc/jemalloc.h>])
  ],
  [test x$with_jemalloc = xyes && with_jemalloc=no])
  AS_IF([test "x$with_jemalloc" != xyes], [
    AC_CACHE_CHECK([for jemalloc with JEMALLOC_MANGLE], rb_cv_jemalloc_demangle,
      [AC_LINK_IFELSE([AC_LANG_PROGRAM([@%:@define JEMALLOC_MANGLE 1
      @%:@ifdef RUBY_ALTERNATIVE_MALLOC_HEADER
      @%:@include RUBY_ALTERNATIVE_MALLOC_HEADER
      @%:@else
      @%:@include <jemalloc.h>
      @%:@endif], [return !&malloc_conf])],
      [rb_cv_jemalloc_demangle=yes],
      [rb_cv_jemalloc_demangle=no])
    ])
  ])
  AS_IF([test "x$rb_cv_jemalloc_demangle" = xyes], [
    AC_DEFINE(JEMALLOC_MANGLE)
    with_jemalloc=yes
  ])
  AS_CASE(["$with_jemalloc"],
    [yes],
    [
      AC_DEFINE(HAVE_MALLOC_CONF)
      ac_cv_func_malloc_usable_size=yes
    ],
    [no],
    [AC_MSG_ERROR([jemalloc requested but not found])
  ])
])

dnl check for large file stuff
mv confdefs.h confdefs1.h
: > confdefs.h
AC_SYS_LARGEFILE
# On 32-bit Solaris, it is safe to define _LARGEFILE_SOURCE
# which is not added by AC_SYS_LARGEFILE.
AS_IF([test x"$enable_largefile" != xno], [
  AS_CASE(["$target_os"], [solaris*], [
    AC_MSG_CHECKING([wheather _LARGEFILE_SOURCE should be defined])
    AS_CASE(["${ac_cv_sys_file_offset_bits}:${ac_cv_sys_large_files}"],
      ["64:"|"64:no"|"64:unknown"], [
	# insert _LARGEFILE_SOURCE before _FILE_OFFSET_BITS line
	# that is the same order as "getconf LFS_CFLAGS" output
	mv confdefs.h largefile0.h
	: > confdefs.h
	AC_DEFINE(_LARGEFILE_SOURCE)
	cat largefile0.h >> confdefs.h
	rm largefile0.h
	AC_MSG_RESULT([yes])
      ], [AC_MSG_RESULT([no])])
  ])
])
mv confdefs.h largefile.h
mv confdefs1.h confdefs.h
cat largefile.h >> confdefs.h

AS_CASE(["$target_os"],
    [aix*], [
    AS_CASE(["$target_cpu:$ac_cv_sys_large_files"],
	[ppc64:*|powerpc64:*], [],
	[*:no|*:unknown], [],
	[
	    # AIX currently does not support a 32-bit call to posix_fadvise()
	    # if _LARGE_FILES is defined.
	    ac_cv_func_posix_fadvise=no
	])
    ])

AC_C_BIGENDIAN
AC_C_CONST
AC_C_CHAR_UNSIGNED
AC_C_INLINE
AC_C_VOLATILE
AC_C_TYPEOF
AC_C_RESTRICT

AS_CASE(":$ac_cv_c_const:$ac_cv_c_volatile:",
    [*:no:*], [AC_MSG_ERROR(ANSI C-conforming const and volatile are mandatory)])

AC_CHECK_TYPES([long long, off_t])

AC_CACHE_CHECK([char bit], [rb_cv_char_bit],
    [test "$universal_binary" = yes && cross_compiling=yes
    AC_COMPUTE_INT([rb_cv_char_bit], [CHAR_BIT],
	[AC_INCLUDES_DEFAULT([@%:@include <limits.h>])], [rb_cv_char_bit=8])
    test "$universal_binary" = yes && cross_compiling=$real_cross_compiling])

RUBY_CHECK_SIZEOF(int, [], [ILP])
RUBY_CHECK_SIZEOF(short)
RUBY_CHECK_SIZEOF(long, [int], [ILP LP])
RUBY_CHECK_SIZEOF(long long)
RUBY_CHECK_SIZEOF(__int64, [8], [ILP LP])
RUBY_CHECK_SIZEOF(__int128, [16], [ILP LP])
RUBY_CHECK_SIZEOF(off_t)
RUBY_CHECK_SIZEOF(void*, [int long "long long"], [ILP LP LLP])
RUBY_CHECK_SIZEOF(float)
RUBY_CHECK_SIZEOF(double)
RUBY_CHECK_SIZEOF(time_t, [long "long long"], [], [@%:@include <time.h>])
RUBY_CHECK_SIZEOF(clock_t, [], [], [@%:@include <time.h>])

AC_CACHE_CHECK(packed struct attribute, rb_cv_packed_struct,
    [rb_cv_packed_struct=no
    for mac in \
	"__pragma(pack(push, 1)) x __pragma(pack(pop))" \
	"x __attribute__((packed))" \
	; do
	AC_TRY_COMPILE([@%:@define PACKED_STRUCT(x) $mac
			PACKED_STRUCT(struct { int a; });], [],
		[rb_cv_packed_struct=$mac; break])
    done])
AS_IF([test "$rb_cv_packed_struct" != no], [
    AC_DEFINE_UNQUOTED([PACKED_STRUCT(x)], [$rb_cv_packed_struct])
    RUBY_TRY_CFLAGS(-Wno-address-of-packed-member, [AC_DEFINE(USE_UNALIGNED_MEMBER_ACCESS)])
], [
    AC_DEFINE_UNQUOTED([PACKED_STRUCT(x)], x)
])

AS_IF([test "x$ac_cv_type_long_long" = xyes], [
    RUBY_CHECK_PRINTF_PREFIX(long long, ll I64, LL)
], [test "x$ac_cv_type___int64" = xyes], [
    RUBY_CHECK_PRINTF_PREFIX(__int64, ll I64, LL)
])

RUBY_REPLACE_TYPE(pid_t, int, PIDT)
RUBY_REPLACE_TYPE(uid_t, int, UIDT)
RUBY_REPLACE_TYPE(gid_t, int, GIDT)
RUBY_REPLACE_TYPE(time_t, [], TIMET, [@%:@include <time.h>])
RUBY_REPLACE_TYPE(dev_t, [int long "long long"], DEVT)
RUBY_REPLACE_TYPE(mode_t, ["unsigned short" "unsigned int" long], MODET, [@%:@include <sys/stat.h>])
RUBY_REPLACE_TYPE(rlim_t, [int long "long long"], RLIM, [
@%:@ifdef HAVE_SYS_TYPES_H
@%:@include <sys/types.h>
@%:@endif
@%:@ifdef HAVE_SYS_TYPES_H
@%:@include <sys/time.h>
@%:@endif
@%:@include <sys/resource.h>
])
RUBY_REPLACE_TYPE(off_t, [], OFFT)
RUBY_REPLACE_TYPE(clockid_t, [], CLOCKID, [@%:@ifdef HAVE_TIME_H
@%:@ include <time.h>
@%:@endif
@%:@ifdef HAVE_SYS_TIME_H
@%:@ include <sys/time.h>
@%:@endif])

AC_CACHE_CHECK(for prototypes, rb_cv_have_prototypes,
  [AC_TRY_COMPILE([int foo(int x) { return 0; }], [return foo(10);],
	rb_cv_have_prototypes=yes,
	rb_cv_have_prototypes=no)])
AS_IF([test "$rb_cv_have_prototypes" = yes], [
  AC_DEFINE(HAVE_PROTOTYPES)
])

AC_CACHE_CHECK(token paste string, rb_cv_tokenpaste,
  [AC_TRY_COMPILE([@%:@define paste(a,b) a@%:@@%:@b],
		  [int xy = 1; return paste(x,y);],
		  rb_cv_tokenpaste=ansi,
		  rb_cv_tokenpaste=knr)])
AS_IF([test "$rb_cv_tokenpaste" = ansi], [
  AC_DEFINE(TOKEN_PASTE(x,y),[x@%:@@%:@y])
], [
  AC_DEFINE(TOKEN_PASTE(x,y),[x/**/y])
])

AC_CACHE_CHECK(stringization, rb_cv_stringization, [
  rb_cv_stringization=no
  for string in "#expr" '"expr"'; do
    AC_COMPILE_IFELSE([
      AC_LANG_BOOL_COMPILE_TRY([
#define STRINGIZE0(expr) $string
#define STRINGIZE(expr) STRINGIZE0(expr)
#undef real_test_for_stringization
#define test_for_stringization -.real_test_for_stringization.-
const char stringized[[]] = STRINGIZE(test_for_stringization);
], [sizeof(stringized) == 32])],
      [rb_cv_stringization="$string"; break],
      [rb_cv_stringization=no])
  done]
)
AC_DEFINE(STRINGIZE(expr),STRINGIZE0(expr))
AS_IF([test x"$rb_cv_stringization" != xno -a "$rb_cv_stringization" != "#expr"], [
  AC_DEFINE_UNQUOTED(STRINGIZE0(expr),$rb_cv_stringization)
  AC_DEFINE(OLD_FASHIONED_STRINGIZATION,1)
])

AC_CACHE_CHECK([string literal concatenation],
  rb_cv_string_literal_concatenation, [
  AC_COMPILE_IFELSE([
    AC_LANG_BOOL_COMPILE_TRY([
const char concatenated_literal[[]] = "literals" "to"
  "be" "concatenated.";
], [sizeof(concatenated_literal) == 26])],
    [rb_cv_string_literal_concatenation=yes],
    [rb_cv_string_literal_concatenation=no])]
)
AS_IF([test "$rb_cv_string_literal_concatenation" = no], [
  AC_MSG_ERROR([No string literal concatenation])
])

AC_CACHE_CHECK(for variable length prototypes and stdarg.h, rb_cv_stdarg,
  [AC_TRY_COMPILE([
#include <stdarg.h>
int foo(int x, ...) {
	va_list va;
	va_start(va, x);
	va_arg(va, int);
	va_arg(va, char *);
	va_arg(va, double);
	return 0;
}
], [return foo(10, "", 3.14);],
	rb_cv_stdarg=yes,
	rb_cv_stdarg=no)])
AS_IF([test "$rb_cv_stdarg" = yes], [
  AC_DEFINE(HAVE_STDARG_PROTOTYPES)
])

# __VA_ARGS__ is also tested in AC_PROG_CC_C99 since autoconf 2.60a (around
# 2006). The check below is redundant and should always success.  Remain not
# deleted for backward compat.
AC_CACHE_CHECK(for variable length macro, rb_cv_va_args_macro,
  [AC_TRY_COMPILE([
int foo(const char*);
@%:@define FOO(...) foo(@%:@__VA_ARGS__)
], [FOO(1);FOO(1,2);FOO(1,2,3);],
  rb_cv_va_args_macro=yes,
  rb_cv_va_args_macro=no)])
AS_IF([test "$rb_cv_va_args_macro" = yes], [
  AC_DEFINE(HAVE_VA_ARGS_MACRO)
])

# We want C11's  `_Alignof`.  GCC (and alike) have  `__alignof__`, which behave
# slightly differently  than the  C11's.  We cannot  use `__alignof__`  for our
# purpose.   The problem  is, however,  that  old gcc  and old  clang had  both
# implemented `_Alignof` as  a synonym of `__alignof__`.  They are  not what we
# want.  We have to check sanity.
#
# See also: https://gcc.gnu.org/bugzilla/show_bug.cgi?id=52023
# See also: https://bugs.llvm.org/show_bug.cgi?id=26547
AC_CACHE_CHECK([if _Alignof() works], rb_cv_have__alignof,[
    rb_cv_have__alignof=no
    RUBY_WERROR_FLAG([
        AC_TRY_COMPILE([
            @%:@ifdef HAVE_STDALIGN_H
            @%:@include <stdalign.h>
            @%:@endif
            @%:@ifdef STDC_HEADERS
            @%:@include <stddef.h>
            @%:@endif
            @%:@ifndef __GNUC__
            @%:@define __extension__
            @%:@endif
        ], [
            typedef struct conftest_tag {
                char _;
                double d;
            } T;
            static int conftest_ary@<:@
                offsetof(T, d) == __extension__ _Alignof(double)
                ? 1 : -1
            @:>@;
            return conftest_ary@<:@0@:>@;
        ], [
            rb_cv_have__alignof=yes
        ])
    ])
])
AS_IF([test "$rb_cv_have__alignof" != no], [
    AC_DEFINE(HAVE__ALIGNOF)
])

RUBY_FUNC_ATTRIBUTE(__const__, CONSTFUNC)
RUBY_FUNC_ATTRIBUTE(__pure__, PUREFUNC)
RUBY_FUNC_ATTRIBUTE(__noreturn__, NORETURN)
RUBY_FUNC_ATTRIBUTE(__deprecated__, DEPRECATED)
RUBY_FUNC_ATTRIBUTE(__deprecated__("by "@%:@n), DEPRECATED_BY(n,x), rb_cv_func_deprecated_by)
RUBY_FUNC_ATTRIBUTE(__noinline__, NOINLINE)
RUBY_FUNC_ATTRIBUTE(__always_inline__, ALWAYS_INLINE)
RUBY_FUNC_ATTRIBUTE(__no_sanitize__(san), NO_SANITIZE(san, x), rb_cv_func_no_sanitize)
RUBY_FUNC_ATTRIBUTE(__no_sanitize_address__, NO_SANITIZE_ADDRESS)
RUBY_FUNC_ATTRIBUTE(__no_address_safety_analysis__, NO_ADDRESS_SAFETY_ANALYSIS)
RUBY_FUNC_ATTRIBUTE(__warn_unused_result__, WARN_UNUSED_RESULT)
RUBY_FUNC_ATTRIBUTE(__unused__, MAYBE_UNUSED)
RUBY_FUNC_ATTRIBUTE(__error__ mesg, ERRORFUNC(mesg,x), rb_cv_func___error__)
RUBY_FUNC_ATTRIBUTE(__warning__ mesg, WARNINGFUNC(mesg,x), rb_cv_func___warning__)
RUBY_FUNC_ATTRIBUTE(__weak__, WEAK, rb_cv_func_weak)
AS_IF([test "$rb_cv_func_weak" != x], [
   AC_DEFINE(HAVE_FUNC_WEAK)
])

AC_CACHE_CHECK([for __attribute__((__depreacted__(msg))) in C++],
  rb_cv_CentOS6_CXX_workaround,
  RUBY_WERROR_FLAG([
    AC_LANG_PUSH([C++])
    AC_COMPILE_IFELSE(
      [AC_LANG_PROGRAM(
        [],
        [__attribute__((__deprecated__("message"))) int conftest(...);])],
      [rb_cv_CentOS6_CXX_workaround=yes],
      [rb_cv_CentOS6_CXX_workaround=no])
    AC_LANG_POP()]))
AS_IF([test "$rb_cv_CentOS6_CXX_workaround" != no],[
  AC_DEFINE([RUBY_CXX_DEPRECATED(msg)],
    [__attribute__((__deprecated__(msg)))])])

AC_CACHE_CHECK([for std::nullptr_t], rb_cv_CXX_nullptr, [
  AC_LANG_PUSH([C++])
  AC_COMPILE_IFELSE(
    [AC_LANG_PROGRAM(
      [@%:@include <cstddef>],
      [static std::nullptr_t const *const conftest = nullptr;])],
    [rb_cv_CXX_nullptr=yes],
    [rb_cv_CXX_nullptr=no])
  AC_LANG_POP()])
AS_IF([test "$rb_cv_CXX_nullptr" != no],[AC_DEFINE(HAVE_NULLPTR)])

if_i386=${universal_binary+[defined __i386__]}
RUBY_FUNC_ATTRIBUTE(__stdcall__,  FUNC_STDCALL,  rb_cv_func_stdcall,  ${if_i386})
RUBY_FUNC_ATTRIBUTE(__cdecl__,    FUNC_CDECL,    rb_cv_func_cdecl,    ${if_i386})
RUBY_FUNC_ATTRIBUTE(__fastcall__, FUNC_FASTCALL, rb_cv_func_fastcall, ${if_i386})
RUBY_FUNC_ATTRIBUTE(__optimize__("O0"), FUNC_UNOPTIMIZED, rb_cv_func_unoptimized)
RUBY_FUNC_ATTRIBUTE(__optimize__("-Os","-fomit-frame-pointer"), FUNC_MINIMIZED, rb_cv_func_minimized)

AS_IF([test "$GCC" = yes], [
    AC_CACHE_CHECK([for function alias], [rb_cv_gcc_function_alias],
	[rb_cv_gcc_function_alias=no
	for a in alias weak,alias; do
	    AC_TRY_LINK([void foo(void) {}
		void bar(void) __attribute__(($a("foo")));], [bar()],
		[rb_cv_gcc_function_alias=$a; break])
	done])
    AS_IF([test "$rb_cv_gcc_function_alias" != no], [
	AC_DEFINE(HAVE_ATTRIBUTE_FUNCTION_ALIAS)
	AC_DEFINE_UNQUOTED([RUBY_ALIAS_FUNCTION_TYPE(type, prot, name, args)],
			   [type prot __attribute__(($rb_cv_gcc_function_alias(@%:@name)));])
	AC_DEFINE_UNQUOTED([RUBY_ALIAS_FUNCTION_VOID(prot, name, args)],
			   [RUBY_ALIAS_FUNCTION_TYPE(void, prot, name, args)])
    ])

    AC_CACHE_CHECK([for __atomic builtins], [rb_cv_gcc_atomic_builtins], [
	AC_TRY_LINK([unsigned int atomic_var;],
		    [
			__atomic_exchange_n(&atomic_var, 0, __ATOMIC_SEQ_CST);
			__atomic_exchange_n(&atomic_var, 1, __ATOMIC_SEQ_CST);
			__atomic_fetch_add(&atomic_var, 1, __ATOMIC_SEQ_CST);
			__atomic_fetch_sub(&atomic_var, 1, __ATOMIC_SEQ_CST);
			__atomic_or_fetch(&atomic_var, 1, __ATOMIC_SEQ_CST);
		    ],
		    [rb_cv_gcc_atomic_builtins=yes],
		    [rb_cv_gcc_atomic_builtins=no])])
    AS_IF([test "$rb_cv_gcc_atomic_builtins" = yes], [
	AC_DEFINE(HAVE_GCC_ATOMIC_BUILTINS)
    ])

    AC_CACHE_CHECK([for __sync builtins], [rb_cv_gcc_sync_builtins], [
	AC_TRY_LINK([unsigned int atomic_var;],
		    [
			__sync_lock_test_and_set(&atomic_var, 0);
			__sync_lock_test_and_set(&atomic_var, 1);
			__sync_fetch_and_add(&atomic_var, 1);
			__sync_fetch_and_sub(&atomic_var, 1);
			__sync_or_and_fetch(&atomic_var, 1);
			__sync_val_compare_and_swap(&atomic_var, 0, 1);
		    ],
		    [rb_cv_gcc_sync_builtins=yes],
		    [rb_cv_gcc_sync_builtins=no])])
    AS_IF([test "$rb_cv_gcc_sync_builtins" = yes], [
	AC_DEFINE(HAVE_GCC_SYNC_BUILTINS)
    ])
])

    AC_CACHE_CHECK(for __builtin_unreachable, rb_cv_func___builtin_unreachable,
    [RUBY_WERROR_FLAG(
    [AC_TRY_LINK([volatile int zero;],
	[if (zero) __builtin_unreachable();],
	[rb_cv_func___builtin_unreachable=yes],
	[rb_cv_func___builtin_unreachable=no])
    ])
    ])
    AS_IF([test "$rb_cv_func___builtin_unreachable" = yes], [
	AC_DEFINE_UNQUOTED(UNREACHABLE, [__builtin_unreachable()])
    ])

AC_CACHE_CHECK(for exported function attribute, rb_cv_func_exported, [
rb_cv_func_exported=no
RUBY_WERROR_FLAG([
for mac in '__attribute__ ((__visibility__("default")))' '__declspec(dllexport)'; do
  AC_TRY_COMPILE([@%:@define RUBY_FUNC_EXPORTED $mac extern
    RUBY_FUNC_EXPORTED void conftest_attribute_check(void);], [],
    [rb_cv_func_exported="$mac"; break])
done
])])
AS_IF([test "$rb_cv_func_exported" != no], [
    AC_DEFINE_UNQUOTED(RUBY_FUNC_EXPORTED, [$rb_cv_func_exported extern])
])
RUBY_DECL_ATTRIBUTE([__nonnull__(n)], [RUBY_FUNC_NONNULL(n,x)], [rb_cv_func_nonnull],
                    [], [function], [
@%:@define x int conftest_attribute_check(void *p)
@%:@define n 1
])

RUBY_APPEND_OPTION(XCFLAGS, -DRUBY_EXPORT)

AC_ARG_ENABLE(mathn,
    AS_HELP_STRING([--enable-mathn], [enable canonicalization for mathn]),
    [AC_MSG_ERROR([mathn support has been dropped])])

AC_CACHE_CHECK(for function name string predefined identifier,
    rb_cv_function_name_string,
    [AS_CASE(["$target_os"],[openbsd*],[
      rb_cv_function_name_string=__func__
     ],[
     rb_cv_function_name_string=no
      RUBY_WERROR_FLAG([
        for func in __func__ __FUNCTION__; do
            AC_TRY_LINK([@%:@include <stdio.h>],
            [puts($func);],
            [rb_cv_function_name_string=$func
            break])
        done
      ])])]
)
AS_IF([test "$rb_cv_function_name_string" != no], [
    AC_DEFINE_UNQUOTED(RUBY_FUNCTION_NAME_STRING, [$rb_cv_function_name_string])
])

AC_CACHE_CHECK(if enum over int is allowed, rb_cv_enum_over_int, [
    rb_cv_enum_over_int=no
    AS_IF([test "x$ac_cv_type_long_long" = xyes], [
	type="unsigned long long" max="ULLONG_MAX"
    ], [
	type="unsigned long" max="ULONG_MAX"
    ])
    RUBY_WERROR_FLAG([
        AC_COMPILE_IFELSE([
            AC_LANG_BOOL_COMPILE_TRY([
                    @%:@include <limits.h>
                    enum {conftest_max = $max};
                ], [
                    (conftest_max == $max) &&
                    (sizeof(conftest_max) == sizeof($type))
                ]
	    )],
	    [rb_cv_enum_over_int=yes],
	    [rb_cv_enum_over_int=no]
	)
    ])
])
AS_IF([test $rb_cv_enum_over_int = yes], [
    AC_DEFINE(ENUM_OVER_INT, 1)
])

dnl Check whether we need to define sys_nerr locally
AC_CHECK_DECLS([sys_nerr], [], [], [$ac_includes_default
@%:@include <errno.h>])

AC_CHECK_DECLS([getenv])

AS_CASE(["$target_cpu"],
[alpha*|sh4|sh4el|sh4eb], [AS_CASE(["$target_os"::"$GCC"],
		[*::yes],  # gcc
			[CFLAGS="-mieee $CFLAGS"],
		[osf*],    # ccc
			[CFLAGS="-ieee $CFLAGS"],
		)],
[sparc*], [AC_LIBOBJ([sparc])])

ac_cv_header_net_socket_h=${ac_cv_header_net_socket_h=no}
AS_IF([test "$ac_cv_header_net_socket_h" = yes], [
    ac_cv_header_sys_socket_h=${ac_cv_header_sys_socket_h=no}
], [
    ac_cv_header_sys_socket_h=${ac_cv_header_sys_socket_h=yes}
])


AC_TYPE_SIZE_T
RUBY_CHECK_SIGNEDNESS(size_t, [AC_MSG_ERROR(size_t is signed)], [],
		      [@%:@include <sys/types.h>])
RUBY_CHECK_SIZEOF(size_t, [int long void*], [], [@%:@include <sys/types.h>])
RUBY_CHECK_SIZEOF(ptrdiff_t, size_t, [], [@%:@include <stddef.h>])
RUBY_CHECK_PRINTF_PREFIX(size_t, z)
RUBY_CHECK_PRINTF_PREFIX(ptrdiff_t, t)
AC_STRUCT_ST_BLKSIZE
AC_STRUCT_ST_BLOCKS
AC_STRUCT_ST_RDEV
RUBY_CHECK_SIZEOF([struct stat.st_size], [off_t int long "long long"], [], [@%:@include <sys/stat.h>])
AS_IF([test "$ac_cv_member_struct_stat_st_blocks" = yes], [
    RUBY_CHECK_SIZEOF([struct stat.st_blocks], [off_t int long "long long"], [], [@%:@include <sys/stat.h>])
])
RUBY_CHECK_SIZEOF([struct stat.st_ino], [long "long long"], [], [@%:@include <sys/stat.h>])
AC_CHECK_MEMBERS([struct stat.st_atim])
AC_CHECK_MEMBERS([struct stat.st_atimespec])
AC_CHECK_MEMBERS([struct stat.st_atimensec])
AC_CHECK_MEMBERS([struct stat.st_mtim])
AC_CHECK_MEMBERS([struct stat.st_mtimespec])
AC_CHECK_MEMBERS([struct stat.st_mtimensec])
AC_CHECK_MEMBERS([struct stat.st_ctim])
AC_CHECK_MEMBERS([struct stat.st_ctimespec])
AC_CHECK_MEMBERS([struct stat.st_ctimensec])
AC_CHECK_MEMBERS([struct stat.st_birthtimespec])
AS_IF([test "x$ac_cv_member_struct_stat_st_birthtimespec" != xyes],
    [AC_CHECK_MEMBERS([struct statx.stx_btime])])

AC_CHECK_TYPES([struct timeval], [], [], [@%:@ifdef HAVE_TIME_H
@%:@include <time.h>
@%:@endif
@%:@ifdef HAVE_SYS_TIME_H
@%:@include <sys/time.h>
@%:@endif])

AS_IF([test "${ac_cv_type_struct_timeval}" = yes], [
    RUBY_CHECK_SIZEOF([struct timeval.tv_sec], [time_t long "long long"], [],
		      [@%:@ifdef HAVE_TIME_H
@%:@include <time.h>
@%:@endif
@%:@ifdef HAVE_SYS_TIME_H
@%:@include <sys/time.h>
@%:@endif])
    AS_CASE(${ac_cv_sizeof_struct_timeval_tv_sec},
	    [SIZEOF_INT], [t=int],
	    [SIZEOF_LONG], [t=long],
	    [SIZEOF_LONG_LONG], [t=LONG_LONG],
	    [t=])
    AS_IF([test "${t}" != ""], [
	AC_DEFINE_UNQUOTED(TYPEOF_TIMEVAL_TV_SEC, [$t])
    ])
])

AC_CHECK_TYPES([struct timespec], [], [], [@%:@ifdef HAVE_TIME_H
@%:@include <time.h>
@%:@endif
@%:@ifdef HAVE_SYS_TIME_H
@%:@include <sys/time.h>
@%:@endif])

AC_CHECK_TYPES([struct timezone], [], [], [@%:@ifdef HAVE_TIME_H
@%:@ include <time.h>
@%:@endif
@%:@ifdef HAVE_SYS_TIME_H
@%:@ include <sys/time.h>
@%:@endif])

AC_CACHE_VAL([rb_cv_large_fd_select],
    [AC_CHECK_TYPE(fd_mask, [rb_cv_large_fd_select=yes], [rb_cv_large_fd_select=no], [AC_INCLUDES_DEFAULT([])
@%:@ifdef HAVE_SYS_SELECT_H
@%:@ include <sys/select.h>
@%:@endif])])
AS_IF([test "$rb_cv_large_fd_select" = yes], [
    AC_DEFINE(HAVE_RB_FD_INIT, 1)
])

RUBY_DEFINT(int8_t, 1)
RUBY_DEFINT(uint8_t, 1, unsigned)
RUBY_DEFINT(int16_t, 2)
RUBY_DEFINT(uint16_t, 2, unsigned)
RUBY_DEFINT(int32_t, 4)
RUBY_DEFINT(uint32_t, 4, unsigned)
RUBY_DEFINT(int64_t, 8)
RUBY_DEFINT(uint64_t, 8, unsigned)
RUBY_DEFINT(int128_t, 16)
RUBY_DEFINT(uint128_t, 16, unsigned)
RUBY_DEFINT(intptr_t, void*)
RUBY_DEFINT(uintptr_t, void*, unsigned)
AS_IF([test "x$rb_cv_type_intptr_t" != xno], [
    RUBY_CHECK_PRINTF_PREFIX(intptr_t, '' ll I64 l, PTR)
])
RUBY_DEFINT(ssize_t, size_t, [], [@%:@include <sys/types.h>])	dnl may differ from int, so not use AC_TYPE_SSIZE_T.
AS_IF([test "x$rb_cv_type_int64_t" != xno], [
    RUBY_CHECK_PRINTF_PREFIX(int64_t, ll I64 l, 64)
])

AC_CACHE_CHECK(for stack end address, rb_cv_stack_end_address,
[rb_cv_stack_end_address=no
  AC_TRY_LINK(
    [extern void *__libc_stack_end;],
    [if (!__libc_stack_end) return 1;],
    [rb_cv_stack_end_address="__libc_stack_end"])
])
AS_IF([test $rb_cv_stack_end_address != no], [
  AC_DEFINE_UNQUOTED(STACK_END_ADDRESS, $rb_cv_stack_end_address)
])

dnl Checks for library functions.
AC_TYPE_GETGROUPS
AC_TYPE_SIGNAL
AS_CASE(["${target_cpu}-${target_os}:${target_archs}"],
[powerpc-darwin*], [
  AC_LIBSOURCES(alloca.c)
  AC_SUBST([ALLOCA], [\${LIBOBJDIR}alloca.${ac_objext}])
  AC_DEFINE(C_ALLOCA)
  AC_DEFINE_UNQUOTED(alloca, alloca)
  ],
[universal-darwin*:*ppc*], [
  AC_LIBSOURCES(alloca.c)
  AC_SUBST([ALLOCA], [\${LIBOBJDIR}alloca.${ac_objext}])
  RUBY_DEFINE_IF([defined __powerpc__], C_ALLOCA, 1)
  RUBY_DEFINE_IF([defined __powerpc__], alloca, alloca)
  ],
[
  AC_FUNC_ALLOCA
  ])
AS_IF([test "x$ALLOCA" = "x"], [
    AC_CACHE_CHECK([for dynamic size alloca], rb_cv_dynamic_alloca, [
    for chk in ok __chkstk; do
	AC_TRY_LINK([
	    @%:@ifdef HAVE_ALLOCA_H
	    @%:@include <alloca.h>
	    @%:@endif
	    void $chk() {}
	    int dynamic_alloca_test;
	    int dynamic_alloca_result;],
	    [dynamic_alloca_result = alloca(dynamic_alloca_test) != 0;],
	    [rb_cv_dynamic_alloca=$chk; break])
    done])
    AS_IF([test "x$rb_cv_dynamic_alloca" = "x__chkstk"], [
	AC_DEFINE_UNQUOTED(RUBY_ALLOCA_CHKSTK, _$rb_cv_dynamic_alloca)
	AS_CASE("$target_cpu",
	[x64|x86_64], [
	    AC_SUBST([ALLOCA], [\${LIBOBJDIR}x86_64-chkstk.${ac_objext}])
	],)
    ])
])
AC_FUNC_MEMCMP

AS_CASE(["$target_os"],[freebsd*],[
	 AC_DEFINE(BROKEN_CLOSE)
	 AC_REPLACE_FUNCS(close)
	 ])

AC_REPLACE_FUNCS(acosh)
AC_REPLACE_FUNCS(cbrt)
AC_REPLACE_FUNCS(crypt)
AC_REPLACE_FUNCS(dup2)
AC_REPLACE_FUNCS(erf)
AC_REPLACE_FUNCS(explicit_bzero)
AC_REPLACE_FUNCS(ffs)
AC_REPLACE_FUNCS(flock)
AC_REPLACE_FUNCS(hypot)
AC_REPLACE_FUNCS(lgamma_r)
AC_REPLACE_FUNCS(memmove)
AC_REPLACE_FUNCS(nan)
AC_REPLACE_FUNCS(nextafter)
AC_REPLACE_FUNCS(setproctitle)
AC_REPLACE_FUNCS(strchr)
AC_REPLACE_FUNCS(strerror)
AC_REPLACE_FUNCS(strlcat)
AC_REPLACE_FUNCS(strlcpy)
AC_REPLACE_FUNCS(strstr)
AC_REPLACE_FUNCS(tgamma)

RUBY_REPLACE_FUNC([finite], [@%:@include <math.h>])
RUBY_REPLACE_FUNC([isinf], [@%:@include <math.h>])
RUBY_REPLACE_FUNC([isnan], [@%:@include <math.h>])

# for missing/setproctitle.c
AS_CASE(["$target_os"],
[aix* | k*bsd*-gnu | kopensolaris*-gnu | linux* | darwin*], [AC_DEFINE(SPT_TYPE,SPT_REUSEARGV)],
[hpux*], [AC_DEFINE(SPT_TYPE,SPT_PSTAT) ],
[])
AC_CHECK_HEADERS(sys/pstat.h)


AC_CACHE_CHECK(for signbit, rb_cv_have_signbit,
  [AC_TRY_LINK([
#include <math.h>
], [int v = signbit(-0.0);],
	rb_cv_have_signbit=yes,
	rb_cv_have_signbit=no)])
AS_IF([test "$rb_cv_have_signbit" = yes], [
  AC_DEFINE(HAVE_SIGNBIT)
], [
  AC_LIBOBJ([signbit])
])

AC_FUNC_FORK

AC_CHECK_FUNCS(__syscall)
AC_CHECK_FUNCS(_longjmp)		# used for AC_ARG_WITH(setjmp-type)
# we don't use _setjmp if _longjmp doesn't exist.
test x$ac_cv_func__longjmp = xno && ac_cv_func__setjmp=no
AC_CHECK_FUNCS(arc4random_buf)
AC_CHECK_FUNCS(atan2l atan2f)
AC_CHECK_FUNCS(chroot)
AC_CHECK_FUNCS(chsize)
AC_CHECK_FUNCS(clock_gettime)
AC_CHECK_FUNCS(copy_file_range)
AC_CHECK_FUNCS(cosh)
AC_CHECK_FUNCS(crypt_r)
AC_CHECK_FUNCS(daemon)
AC_CHECK_FUNCS(dirfd)
AC_CHECK_FUNCS(dl_iterate_phdr)
AC_CHECK_FUNCS(dlopen)
AC_CHECK_FUNCS(dladdr)
AC_CHECK_FUNCS(dup)
AC_CHECK_FUNCS(dup3)
AC_CHECK_FUNCS(eaccess)
AC_CHECK_FUNCS(endgrent)
AC_CHECK_FUNCS(eventfd)
AC_CHECK_FUNCS(explicit_memset)
AC_CHECK_FUNCS(fcopyfile)
AC_CHECK_FUNCS(fchmod)
AC_CHECK_FUNCS(fchown)
AC_CHECK_FUNCS(fcntl)
AC_CHECK_FUNCS(fdatasync)
AC_CHECK_FUNCS(fdopendir)
AC_CHECK_FUNCS(fgetattrlist)
AC_CHECK_FUNCS(fmod)
AC_CHECK_FUNCS(fstatat)
AC_CHECK_FUNCS(fsync)
AC_CHECK_FUNCS(ftruncate)
AC_CHECK_FUNCS(ftruncate64)		# used for Win32 platform
AC_CHECK_FUNCS(getattrlist)
AC_CHECK_FUNCS(getcwd)
AC_CHECK_FUNCS(getgidx)
AC_CHECK_FUNCS(getgrnam)
AC_CHECK_FUNCS(getgrnam_r)
AC_CHECK_FUNCS(getgroups)
AC_CHECK_FUNCS(getlogin)
AC_CHECK_FUNCS(getlogin_r)
AC_CHECK_FUNCS(getpgid)
AC_CHECK_FUNCS(getpgrp)
AC_CHECK_FUNCS(getpriority)
AC_CHECK_FUNCS(getpwnam)
AC_CHECK_FUNCS(getpwnam_r)
AC_CHECK_FUNCS(getpwuid)
AC_CHECK_FUNCS(getpwuid_r)
AC_CHECK_FUNCS(getrandom)
AC_CHECK_FUNCS(getresgid)
AC_CHECK_FUNCS(getresuid)
AC_CHECK_FUNCS(getrlimit)
AC_CHECK_FUNCS(getsid)
AC_CHECK_FUNCS(gettimeofday)		# for making ac_cv_func_gettimeofday
AC_CHECK_FUNCS(getuidx)
AC_CHECK_FUNCS(gmtime_r)
AC_CHECK_FUNCS(grantpt)
AC_CHECK_FUNCS(initgroups)
AC_CHECK_FUNCS(ioctl)
AC_CHECK_FUNCS(isfinite)
AC_CHECK_FUNCS(issetugid)
AC_CHECK_FUNCS(killpg)
AC_CHECK_FUNCS(lchmod)
AC_CHECK_FUNCS(lchown)
AC_CHECK_FUNCS(link)
AC_CHECK_FUNCS(llabs)
AC_CHECK_FUNCS(lockf)
AC_CHECK_FUNCS(log2)
AC_CHECK_FUNCS(lstat)
AC_CHECK_FUNCS(lutimes)
AC_CHECK_FUNCS(malloc_usable_size)
AC_CHECK_FUNCS(malloc_size)
AC_CHECK_FUNCS(mblen)
AC_CHECK_FUNCS(memalign)
AC_CHECK_FUNCS(memset_s)
AC_CHECK_FUNCS(writev)
AC_CHECK_FUNCS(memrchr)
AC_CHECK_FUNCS(memmem)
AC_CHECK_FUNCS(mkfifo)
AC_CHECK_FUNCS(mknod)
AC_CHECK_FUNCS(mktime)
AC_CHECK_FUNCS(openat)
AC_CHECK_FUNCS(pipe2)
AC_CHECK_FUNCS(poll)
AC_CHECK_FUNCS(posix_fadvise)
AC_CHECK_FUNCS(posix_memalign)
AC_CHECK_FUNCS(ppoll)
AC_CHECK_FUNCS(pread)
AC_CHECK_FUNCS(pwrite)
AC_CHECK_FUNCS(qsort_r)
AC_CHECK_FUNCS(qsort_s)
AC_CHECK_FUNCS(readlink)
AC_CHECK_FUNCS(realpath)
AC_CHECK_FUNCS(round)
AC_CHECK_FUNCS(sched_getaffinity)
AC_CHECK_FUNCS(seekdir)
AC_CHECK_FUNCS(select_large_fdset)
AC_CHECK_FUNCS(sendfile)
AC_CHECK_FUNCS(setegid)
AC_CHECK_FUNCS(setenv)
AC_CHECK_FUNCS(seteuid)
AC_CHECK_FUNCS(setgid)
AC_CHECK_FUNCS(setgroups)
AC_CHECK_FUNCS(setpgid)
AC_CHECK_FUNCS(setpgrp)
AC_CHECK_FUNCS(setregid)
AC_CHECK_FUNCS(setresgid)
AC_CHECK_FUNCS(setresuid)
AC_CHECK_FUNCS(setreuid)
AC_CHECK_FUNCS(setrgid)
AC_CHECK_FUNCS(setrlimit)
AC_CHECK_FUNCS(setruid)
AC_CHECK_FUNCS(setsid)
AC_CHECK_FUNCS(setuid)
AC_CHECK_FUNCS(shutdown)
AC_CHECK_FUNCS(sigaction)
AC_CHECK_FUNCS(sigaltstack)
AC_CHECK_FUNCS(sigprocmask)
AC_CHECK_FUNCS(sinh)
AC_CHECK_FUNCS(spawnv)
AC_CHECK_FUNCS(symlink)
AC_CHECK_FUNCS(syscall)
AC_CHECK_FUNCS(sysconf)
AC_CHECK_FUNCS(tanh)
AC_CHECK_FUNCS(telldir)
AC_CHECK_FUNCS(timegm)
AC_CHECK_FUNCS(times)
AC_CHECK_FUNCS(truncate)
AC_CHECK_FUNCS(truncate64)		# used for Win32
AC_CHECK_FUNCS(unsetenv)
AC_CHECK_FUNCS(utimensat)
AC_CHECK_FUNCS(utimes)
AC_CHECK_FUNCS(wait4)
AC_CHECK_FUNCS(waitpid)
AC_CHECK_FUNCS(__cospi)
AC_CHECK_FUNCS(__sinpi)

AS_IF([test "x$ac_cv_member_struct_statx_stx_btime" = xyes],
    [AC_CHECK_FUNCS(statx)])

AS_CASE(["$ac_cv_func_memset_s:$ac_cv_func_qsort_s"], [*yes*],
    [RUBY_DEFINE_IF([!defined __STDC_WANT_LIB_EXT1__], [__STDC_WANT_LIB_EXT1__], 1)])

AS_IF([test "$ac_cv_func_getcwd" = yes], [
    AC_CACHE_CHECK(if getcwd allocates buffer if NULL is given, [rb_cv_getcwd_malloc],
	[AC_TRY_RUN([
@%:@include <stddef.h>
@%:@include <stdio.h>
@%:@ifdef HAVE_UNISTD_H
@%:@include <unistd.h>
@%:@endif
@%:@ifndef EXIT_SUCCESS
@%:@define EXIT_SUCCESS 0
@%:@endif
@%:@ifndef EXIT_FAILURE
@%:@define EXIT_FAILURE 1
@%:@endif

int
main(int argc, char **argv)
{
    if (!getcwd(NULL, 0)) return EXIT_FAILURE;
    return EXIT_SUCCESS;
}
],
	    rb_cv_getcwd_malloc=yes,
	    rb_cv_getcwd_malloc=no,
	    AS_CASE($target_os,
		[linux*|darwin*|*bsd|cygwin*|mingw*|mswin*],
		[rb_cv_getcwd_malloc=yes],
		[rb_cv_getcwd_malloc=no]))])
    AS_IF([test "$rb_cv_getcwd_malloc" = no], [AC_DEFINE(NO_GETCWD_MALLOC, 1)])
])

AS_IF([test "$ac_cv_func_crypt_r" = yes],
    [AC_CHECK_HEADERS(crypt.h)])
AS_IF([test "$ac_cv_func_crypt_r:$ac_cv_header_crypt_h" = yes:yes],
    [AC_CHECK_MEMBERS([struct crypt_data.initialized], [], [],
		      [AC_INCLUDES_DEFAULT([@%:@include <crypt.h>])])])

RUBY_CHECK_BUILTIN_FUNC(__builtin_alloca_with_align, [__builtin_alloca_with_align(1, 4096)])
RUBY_CHECK_BUILTIN_FUNC(__builtin_assume_aligned, [__builtin_assume_aligned((void*)32, 32)])
RUBY_CHECK_BUILTIN_FUNC(__builtin_bswap16, [__builtin_bswap16(0)])
RUBY_CHECK_BUILTIN_FUNC(__builtin_bswap32, [__builtin_bswap32(0)])
RUBY_CHECK_BUILTIN_FUNC(__builtin_bswap64, [__builtin_bswap64(0)])
RUBY_CHECK_BUILTIN_FUNC(__builtin_popcount, [__builtin_popcount(0)])
RUBY_CHECK_BUILTIN_FUNC(__builtin_popcountll, [__builtin_popcountll(0)])
RUBY_CHECK_BUILTIN_FUNC(__builtin_clz, [__builtin_clz(0)])
RUBY_CHECK_BUILTIN_FUNC(__builtin_clzl, [__builtin_clzl(0)])
RUBY_CHECK_BUILTIN_FUNC(__builtin_clzll, [__builtin_clzll(0)])
RUBY_CHECK_BUILTIN_FUNC(__builtin_ctz, [__builtin_ctz(0)])
RUBY_CHECK_BUILTIN_FUNC(__builtin_ctzll, [__builtin_ctzll(0)])
RUBY_CHECK_BUILTIN_FUNC(__builtin_add_overflow, [int x;__builtin_add_overflow(0,0,&x)])
RUBY_CHECK_BUILTIN_FUNC(__builtin_sub_overflow, [int x;__builtin_sub_overflow(0,0,&x)])
RUBY_CHECK_BUILTIN_FUNC(__builtin_mul_overflow, [int x;__builtin_mul_overflow(0,0,&x)])
RUBY_CHECK_BUILTIN_FUNC(__builtin_mul_overflow_p, [__builtin_mul_overflow_p(0,0,(int)0)])
RUBY_CHECK_BUILTIN_FUNC(__builtin_constant_p, [__builtin_constant_p(0)])
RUBY_CHECK_BUILTIN_FUNC(__builtin_choose_expr, [
    [int x[__extension__(__builtin_choose_expr(1, 1, -1))]];
    [int y[__extension__(__builtin_choose_expr(0, -1, 1))]];
    ])
AS_IF([test x$rb_cv_builtin___builtin_choose_expr = xyes], [
    RUBY_CHECK_BUILTIN_FUNC(__builtin_choose_expr_constant_p, [
    [int x[__extension__(__builtin_choose_expr(__builtin_constant_p(1), 1, -1))]];
    [int y[__extension__(__builtin_choose_expr(__builtin_constant_p(foo), -1, 1))]];
    ])
])
RUBY_CHECK_BUILTIN_FUNC(__builtin_types_compatible_p, [__builtin_types_compatible_p(int, int)])
RUBY_CHECK_BUILTIN_FUNC(__builtin_trap, [__builtin_trap()])

AS_IF([test "$ac_cv_func_qsort_r" != no], [
  AC_CACHE_CHECK(whether qsort_r is GNU version, rb_cv_gnu_qsort_r,
    [AC_TRY_COMPILE([
@%:@include <stdlib.h>
void (qsort_r)(void *base, size_t nmemb, size_t size,
	    int (*compar)(const void *, const void *, void *),
	    void *arg);
],[ ],
      [rb_cv_gnu_qsort_r=yes],
      [rb_cv_gnu_qsort_r=no])
  ])
  AC_CACHE_CHECK(whether qsort_r is BSD version, rb_cv_bsd_qsort_r,
    [AC_TRY_COMPILE([
@%:@include <stdlib.h>
void (qsort_r)(void *base, size_t nmemb, size_t size,
	     void *arg, int (*compar)(void *, const void *, const void *));
],[ ],
      [rb_cv_bsd_qsort_r=yes],
      [rb_cv_bsd_qsort_r=no])
  ])
  AS_CASE("$rb_cv_gnu_qsort_r:$rb_cv_bsd_qsort_r",
  [yes:no], [
    AC_DEFINE(HAVE_GNU_QSORT_R, 1)
  ],
  [no:yes], [
    AC_DEFINE(HAVE_BSD_QSORT_R, 1)
  ])
])

AC_CACHE_CHECK(whether atan2 handles Inf as C99, rb_cv_atan2_inf_c99, [
    AS_IF([test $ac_cv_func_atan2f:$ac_cv_func_atan2l = yes:yes], [
	AC_TRY_RUN([
@%:@include <math.h>
@%:@ifdef HAVE_UNISTD_H
@%:@include <unistd.h>
@%:@endif
@%:@ifndef EXIT_SUCCESS
@%:@define EXIT_SUCCESS 0
@%:@endif
@%:@ifndef EXIT_FAILURE
@%:@define EXIT_FAILURE 1
@%:@endif

int
main(int argc, char **argv)
{
    if (fabs(atan2(INFINITY, INFINITY) - M_PI_4) <= 0.01) return EXIT_SUCCESS;
    return EXIT_FAILURE;
}
],
	[rb_cv_atan2_inf_c99=yes],
	[rb_cv_atan2_inf_c99=no],
	[AS_CASE($target_os, [mingw*|mswin*], [rb_cv_atan2_inf_c99=no], [rb_cv_atan2_inf_c99=yes])]
	)
    ], [rb_cv_atan2_inf_c99=no])
])
AS_IF([test "x$rb_cv_atan2_inf_c99" = xyes], [AC_DEFINE(ATAN2_INF_C99)])

# Some platform need -lrt for clock_gettime, but the other don't.
AS_IF([test x"$ac_cv_func_clock_gettime" != xyes], [
    # glibc 2.17 moves clock_* functions from librt to the main C library.
    # http://sourceware.org/ml/libc-announce/2012/msg00001.html
    AC_CHECK_LIB(rt, clock_gettime)
    AS_IF([test x"$ac_cv_lib_rt_clock_gettime" = xyes], [
	AC_DEFINE(HAVE_CLOCK_GETTIME, 1)
    ])
])
AC_CHECK_FUNCS(clock_getres) # clock_getres should be tested after clock_gettime test including librt test.
AC_CHECK_LIB([rt], [timer_create])
AC_CHECK_LIB([rt], [timer_settime])
AS_IF([test x"$ac_cv_lib_rt_timer_create" = xyes], [
    AC_DEFINE(HAVE_TIMER_CREATE, 1)
])
AS_IF([test x"$ac_cv_lib_rt_timer_settime" = xyes], [
    AC_DEFINE(HAVE_TIMER_SETTIME, 1)
])

AC_CACHE_CHECK(for unsetenv returns a value, rb_cv_unsetenv_return_value,
  [AC_TRY_COMPILE([
#include <stdlib.h>
], [int v = unsetenv("foo");],
	rb_cv_unsetenv_return_value=yes,
	rb_cv_unsetenv_return_value=no)])
AS_IF([test "$rb_cv_unsetenv_return_value" = no], [
  AC_DEFINE(VOID_UNSETENV)
])

# End of setjmp check.

AC_ARG_ENABLE(setreuid,
       AS_HELP_STRING([--enable-setreuid], [use setreuid()/setregid() according to need even if obsolete]),
       [use_setreuid=$enableval])
AS_IF([test "$use_setreuid" = yes], [
    AC_DEFINE(USE_SETREUID)
    AC_DEFINE(USE_SETREGID)
])
AC_STRUCT_TIMEZONE
AC_CACHE_CHECK(for struct tm.tm_gmtoff, rb_cv_member_struct_tm_tm_gmtoff,
  [AC_TRY_COMPILE([
@%:@define _BSD_SOURCE
@%:@define _DEFAULT_SOURCE
@%:@include <time.h>
   ],
    [struct tm t; t.tm_gmtoff = 3600;],
  [rb_cv_member_struct_tm_tm_gmtoff=yes],
  [rb_cv_member_struct_tm_tm_gmtoff=no])])
AS_IF([test "$rb_cv_member_struct_tm_tm_gmtoff" = yes], [
  AC_DEFINE(HAVE_STRUCT_TM_TM_GMTOFF)
])
AC_CACHE_CHECK(for external int daylight, rb_cv_have_daylight,
  [AC_TRY_LINK([#include <time.h>
  int i;],
	[i = daylight;],
	rb_cv_have_daylight=yes,
	rb_cv_have_daylight=no)])
AS_IF([test "$rb_cv_have_daylight" = yes], [
  AC_DEFINE(HAVE_DAYLIGHT)
])

AC_CACHE_CHECK(for negative time_t for gmtime(3), rb_cv_negative_time_t,
  [AC_TRY_RUN([
#include <stdlib.h>
#include <time.h>

void
check(tm, y, m, d, h, s)
    struct tm *tm;
    int y, m, d, h, s;
{
    if (!tm ||
	tm->tm_year != y ||
	tm->tm_mon  != m-1 ||
	tm->tm_mday != d ||
	tm->tm_hour != h ||
	tm->tm_sec  != s) {
	exit(1);
    }
}

int
main()
{
   time_t t = -1;
   struct tm *tm;

   check(gmtime(&t), 69, 12, 31, 23, 59);
   t = ~(time_t)0 << 31;
   check(gmtime(&t), 1, 12, 13, 20, 52);
   return 0;
}
],
	rb_cv_negative_time_t=yes,
	rb_cv_negative_time_t=no,
	rb_cv_negative_time_t=yes)])
AS_IF([test "$rb_cv_negative_time_t" = yes], [
  AC_DEFINE(NEGATIVE_TIME_T)
])

# [ruby-dev:40910] overflow of time on FreeBSD
# http://www.freebsd.org/cgi/query-pr.cgi?pr=145341
AC_CACHE_CHECK(for localtime(3) overflow correctly, rb_cv_localtime_overflow,
  [AC_TRY_RUN([
#include <stdlib.h>
#include <time.h>

void
check(time_t t1)
{
    struct tm *tm;
    time_t t2;
    tm = localtime(&t1);
    if (!tm)
	return; /* overflow detected.  ok. */
    t2 = mktime(tm);
    if (t1 == t2)
        return; /* round-trip.  ok. */
    exit(1);
}

int
main()
{
    time_t t;
    if (~(time_t)0 <= 0) {
        t = (((time_t)1) << (sizeof(time_t) * 8 - 2));
        t |= t - 1;
    }
    else {
        t = ~(time_t)0;
    }
    check(t);
    return 0;
}
],
	rb_cv_localtime_overflow=yes,
	rb_cv_localtime_overflow=no,
	rb_cv_localtime_overflow=no)])
AS_IF([test "$rb_cv_localtime_overflow" = no], [
  AC_DEFINE(LOCALTIME_OVERFLOW_PROBLEM)
])

AS_IF([test "$ac_cv_func_sigprocmask" = yes && test "$ac_cv_func_sigaction" = yes], [
   AC_DEFINE(POSIX_SIGNAL)
], [
  AC_CHECK_FUNCS(sigsetmask)
  AC_CACHE_CHECK(for BSD signal semantics, rb_cv_bsd_signal,
    [AC_TRY_RUN([
#include <stdio.h>
#include <signal.h>

void
sig_handler(dummy)
     int dummy;
{
}

int
main()
{
  signal(SIGINT, sig_handler);
  kill(getpid(), SIGINT);
  kill(getpid(), SIGINT);
  return 0;
}
],
	rb_cv_bsd_signal=yes,
	rb_cv_bsd_signal=no,
	rb_cv_bsd_signal=$ac_cv_func_sigsetmask)])
  AS_IF([test "$rb_cv_bsd_signal" = yes], [
    AC_DEFINE(BSD_SIGNAL)
  ])
])

AC_CHECK_TYPES([sig_t],[],[],[@%:@include <signal.h>])

AS_IF([test "$ac_cv_func_getpgid" = no], [
  # AC_FUNC_GETPGRP fails when cross-compiling with old autoconf.
  # autoconf is changed between 2.52d and 2.52f?
  # http://lists.gnu.org/archive/html/bug-gnu-utils/2001-09/msg00181.html
  # "autoconf cleanup for AC_FUNC_GETPGRP and GETPGRP_VOID"
AC_FUNC_GETPGRP
])
AS_IF([test "$ac_cv_func_setpgid:$ac_cv_func_setpgrp" = no:yes], [
  # AC_FUNC_SETPGRP fails when cross-compiling.  (until autoconf 2.69?)
  # https://lists.gnu.org/archive/html/bug-autoconf/2013-02/msg00002.html
  # "AC_FUNC_SETPGRP fails to work properly when cross-compiling"
AC_FUNC_SETPGRP
])

AS_IF([test x"$ac_cv_func_dirfd" = xno], [
  AS_CASE(["$target_os"],[solaris*],
          [AC_CHECK_MEMBERS([DIR.d_fd, DIR.dd_fd],,,[
#include <sys/types.h>
#include <dirent.h>
])])
])

AC_CACHE_CHECK(whether right shift preserve sign bit, rb_cv_rshift_sign,
    [AC_COMPILE_IFELSE([AC_LANG_BOOL_COMPILE_TRY([], [(-1==(-1>>1))])],
	rb_cv_rshift_sign=yes,
	rb_cv_rshift_sign=no)])
AS_IF([test "$rb_cv_rshift_sign" = yes], [
  AC_DEFINE(RSHIFT(x,y), ((x)>>(int)(y)))
], [
  AC_DEFINE(RSHIFT(x,y), (((x)<0) ? ~((~(x))>>(int)(y)) : (x)>>(int)(y)))
])

AS_IF([test "$ac_cv_func_copy_file_range" = no], [
  AC_CACHE_CHECK([for copy_file_range],
    rb_cv_use_copy_file_range,
    [AC_TRY_RUN([
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <fcntl.h>
#include <unistd.h>

#ifndef O_TMPFILE
  #define O_TMPFILE __O_TMPFILE
#endif

int
main()
{
#ifdef __NR_copy_file_range
   int ret, fd_in, fd_out;
   fd_in = open("/tmp", O_TMPFILE|O_RDWR, S_IRUSR);
   fd_out = open("/tmp", O_TMPFILE|O_WRONLY, S_IWUSR);
   ret = syscall(__NR_copy_file_range, fd_in, NULL, fd_out, NULL, 0, 0);
   close(fd_in);
   close(fd_out);
   if (ret == -1) { return 1; }
   return 0;
#else
   return 1;
#endif
}
  ],
    [rb_cv_use_copy_file_range=yes],
    [rb_cv_use_copy_file_range=no],
    [rb_cv_use_copy_file_range=no])])
])
AS_CASE(["$ac_cv_func_copy_file_range:$rb_cv_use_copy_file_range"], [*yes*], [
  AC_DEFINE(USE_COPY_FILE_RANGE)
])

AS_CASE(["$ac_cv_func_gettimeofday:$ac_cv_func_clock_gettime"],
[*yes*], [],
[
    AC_MSG_ERROR(clock_gettime() or gettimeofday() must exist)
])

AS_IF([test "$ac_cv_func_sysconf" = yes], [
  RUBY_CHECK_SYSCONF(CLK_TCK)
])

AS_IF([test "${universal_binary-no}" = yes ], [
    archflagpat=`eval echo '"'"${ARCH_FLAG}"'"' | sed 's/[[][|.*]]/\\&/g'`
    save_CFLAGS="$CFLAGS" new_cflags=`echo "$CFLAGS" | sed "s|$archflagpat"'||'`
    save_LDFLAGS="$LDFLAGS" new_ldflags=`echo "$LDFLAGS" | sed "s|$archflagpat"'||'`
    stack_dir=
    for archs in ${universal_archnames}; do
	archs=`echo $archs | sed 's/=.*//'`
	CFLAGS="$new_cflags -arch $archs"
	LDFLAGS="$new_ldflags -arch $archs"
	RUBY_STACK_GROW_DIRECTION($archs, dir)
	AS_IF([test x$stack_dir = x], [
	    stack_dir=$dir
	], [test x$stack_dir != x$dir], [
	    stack_dir=no
	])
    done
    CFLAGS="$save_CFLAGS" LDFLAGS="$save_LDFLAGS"
    AS_IF([test x$stack_dir = xno], [
	for archs in ${universal_archnames}; do
	    archs=`echo $archs | sed 's/=.*//'`
	    eval dir=\$[rb_cv_stack_grow_dir_]AS_TR_SH([$archs])
	    RUBY_DEFINE_IF([defined __${archs}__], STACK_GROW_DIRECTION, $dir)
	done
    ], [
	AC_DEFINE_UNQUOTED(STACK_GROW_DIRECTION, $stack_dir)
    ])
], [
    RUBY_STACK_GROW_DIRECTION($target_cpu, dir)
    AC_DEFINE_UNQUOTED(STACK_GROW_DIRECTION, $dir)
])

AC_ARG_WITH(coroutine,
    AS_HELP_STRING([--with-coroutine=IMPLEMENTATION], [specify the coroutine implementation to use]),
    [rb_cv_coroutine=$withval])
AS_CASE([$rb_cv_coroutine], [yes|''], [
    AC_MSG_CHECKING(native coroutine implementation for ${target_cpu}-${target_os})
    rb_cv_coroutine=
    AS_CASE(["$target_cpu-$target_os"],
        [x*64-darwin*], [
            rb_cv_coroutine=amd64
        ],
        [arm64-darwin*], [
            rb_cv_coroutine=arm64
        ],
        [x*64-linux*], [
            AS_CASE(["$ac_cv_sizeof_voidp"],
                [8], [ rb_cv_coroutine=amd64 ],
                [4], [ rb_cv_coroutine=x86 ],
                dnl unknown pointer size, bail out as no Context.h soon.
            )
        ],
        [*86-linux*], [
            rb_cv_coroutine=x86
        ],
        [x64-mingw32], [
            rb_cv_coroutine=win64
        ],
        [*86-mingw32], [
            rb_cv_coroutine=win32
        ],
        [arm*-linux*], [
            rb_cv_coroutine=arm32
        ],
        [aarch64-linux*], [
            rb_cv_coroutine=arm64
        ],
        [powerpc64le-linux*], [
            rb_cv_coroutine=ppc64le
        ],
        [x86_64-openbsd*], [
            rb_cv_coroutine=amd64
        ],
        [i386-openbsd*], [
            rb_cv_coroutine=x86
        ],
        [*-openbsd*], [
            rb_cv_coroutine=copy
        ],
        [
            rb_cv_coroutine=ucontext
        ]
    )
    AC_MSG_RESULT(${rb_cv_coroutine})
])
COROUTINE_H=coroutine/$rb_cv_coroutine/Context.h
AS_IF([test ! -f "$srcdir/$COROUTINE_H"],
      [AC_MSG_ERROR('$rb_cv_coroutine' is not supported as coroutine)])
AS_CASE([$rb_cv_coroutine],
    [copy|ucontext], [
        COROUTINE_SRC=coroutine/$rb_cv_coroutine/Context.c
    ],
    [
        COROUTINE_SRC=coroutine/$rb_cv_coroutine/Context.'$(ASMEXT)'
    ]
)
AC_DEFINE_UNQUOTED(COROUTINE_H, ["$COROUTINE_H"])
AC_SUBST(X_COROUTINE_H, [$COROUTINE_H])
AC_SUBST(X_COROUTINE_SRC, [$COROUTINE_SRC])

AS_IF([test x"$enable_pthread" = xyes], [
    for pthread_lib in thr pthread pthreads c c_r root; do
	AC_CHECK_LIB($pthread_lib, pthread_create,
		     rb_with_pthread=yes, rb_with_pthread=no)
	AS_IF([test "$rb_with_pthread" = "yes"], [break])
    done
    AS_IF([test x"$rb_with_pthread" = xyes], [
	AC_DEFINE(_REENTRANT)
	AC_DEFINE(_THREAD_SAFE)
	AC_DEFINE(HAVE_LIBPTHREAD)
	AC_CHECK_HEADERS(pthread_np.h, [], [], [@%:@include <pthread.h>])
	AS_CASE(["$pthread_lib:$target_os"],
		[c:*], [],
		[root:*], [],
		[c_r:*|*:openbsd*|*:mirbsd*],  [LIBS="-pthread $LIBS"],
		[LIBS="-l$pthread_lib $LIBS"])
    ], [
	AC_MSG_WARN("Don't know how to find pthread library on your system -- thread support disabled")
    ])
    AC_CACHE_CHECK([whether pthread_t is scalar type], [rb_cv_scalar_pthread_t], [
	AC_TRY_COMPILE([
	    @%:@include <pthread.h>
	    ], [
	    pthread_t thread_id;
	    thread_id = 0;
	    if (!thread_id) return 0;
	    ], [rb_cv_scalar_pthread_t=yes], [rb_cv_scalar_pthread_t=no])
    ])
    AS_IF([test x"$rb_cv_scalar_pthread_t" = xyes], [
	: # RUBY_CHECK_SIZEOF(pthread_t, [void* int long], [], [@%:@include <pthread.h>])
    ], [
	AC_DEFINE(NON_SCALAR_THREAD_ID)
    ])
    AC_CHECK_FUNCS(sched_yield pthread_attr_setinheritsched \
	pthread_attr_get_np pthread_attr_getstack pthread_attr_getguardsize \
	pthread_get_stackaddr_np pthread_get_stacksize_np \
	thr_stksegment pthread_stackseg_np pthread_getthrds_np \
	pthread_condattr_setclock \
	pthread_sigmask pthread_setname_np pthread_set_name_np)
    AS_CASE(["$target_os"],[aix*],[ac_cv_func_pthread_getattr_np=no],[AC_CHECK_FUNCS(pthread_getattr_np)])
    set_current_thread_name=
    AS_IF([test "$ac_cv_func_pthread_setname_np" = yes], [
	AC_CACHE_CHECK([arguments of pthread_setname_np], [rb_cv_func_pthread_setname_np_arguments],
	    [rb_cv_func_pthread_setname_np_arguments=
	    # Linux,AIX,  (pthread_self(), name)
	    # NetBSD (pthread_self(), \"%s\", name)
	    # Darwin (name)
	    for mac in \
		"(pthread_self(), name)" \
		"(pthread_self(), \"%s\", name)" \
		"(name)" \
		; do
		AC_TRY_COMPILE([
		    @%:@include <pthread.h>
		    @%:@ifdef HAVE_PTHREAD_NP_H
		    @%:@include <pthread_np.h>
		    @%:@endif
		    @%:@define SET_THREAD_NAME(name) pthread_setname_np${mac}
		    ],
		    [if (SET_THREAD_NAME("conftest")) return 1;],
		    [rb_cv_func_pthread_setname_np_arguments="${mac}"
		    break])
	    done
	    ]
	)
	AS_IF([test -n "${rb_cv_func_pthread_setname_np_arguments}"], [
	    set_current_thread_name="pthread_setname_np${rb_cv_func_pthread_setname_np_arguments}"
	])
    ], [test "$ac_cv_func_pthread_set_name_np" = yes], [
	set_current_thread_name="pthread_set_name_np(pthread_self(), name)"
    ])
    AS_IF([test -n "$set_current_thread_name"], [
	AC_DEFINE_UNQUOTED(SET_CURRENT_THREAD_NAME(name), $set_current_thread_name)
	AS_CASE([$set_current_thread_name],
	    [*'pthread_self()'*], [
		set_another_thread_name=`echo "$set_current_thread_name" | sed 's/pthread_self()/thid/'`
		AC_DEFINE_UNQUOTED(SET_ANOTHER_THREAD_NAME(thid,name), $set_another_thread_name)
	    ])
    ])
])

AS_IF([test x"$ac_cv_header_ucontext_h" = xno], [
    AC_CACHE_CHECK([if signal.h defines ucontext_t], [rb_cv_ucontext_in_signal_h],
	[AC_TRY_COMPILE([@%:@include <signal.h>],
	[size_t size = sizeof(ucontext_t);],
	[rb_cv_ucontext_in_signal_h=yes], [rb_cv_ucontext_in_signal_h=no])])
    AS_IF([test x"$rb_cv_ucontext_in_signal_h" = xyes], [
	    AC_DEFINE_UNQUOTED(UCONTEXT_IN_SIGNAL_H, 1)
    ])
])
AS_IF([test x"$ac_cv_header_ucontext_h" = xyes -o x"$rb_cv_ucontext_in_signal_h" = xyes], [
    AC_CACHE_CHECK([if mcontext_t is a pointer], [rb_cv_mcontext_t_ptr],
	[AC_TRY_COMPILE([
	    @%:@include <signal.h>
	    @%:@ifdef HAVE_UCONTEXT_H
	    @%:@include <ucontext.h>
	    @%:@endif
        mcontext_t test(mcontext_t mc) {return mc+1;}
	],
	[test(0);],
	[rb_cv_mcontext_t_ptr=yes], [rb_cv_mcontext_t_ptr=no])])
    AS_IF([test x"$rb_cv_mcontext_t_ptr" = xyes], [
	AC_DEFINE_UNQUOTED(DEFINE_MCONTEXT_PTR(mc, uc), mcontext_t mc = (uc)->uc_mcontext)
    ], [
	AC_DEFINE_UNQUOTED(DEFINE_MCONTEXT_PTR(mc, uc), mcontext_t *mc = &(uc)->uc_mcontext)
    ])
    AS_IF([test x"$rb_with_pthread" = xyes], [
	AC_CHECK_FUNCS(getcontext setcontext)
    ])
])

AS_IF([test "$ac_cv_func_fork_works" = "yes" -a "$rb_with_pthread" = "yes"], [
    AC_CACHE_CHECK([if fork works with pthread], rb_cv_fork_with_pthread,
	[AC_TRY_RUN([
#include <stdlib.h>
#include <unistd.h>
#include <pthread.h>
#include <stdio.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <signal.h>
#ifndef EXIT_SUCCESS
#define EXIT_SUCCESS 0
#endif
#ifndef EXIT_FAILURE
#define EXIT_FAILURE 1
#endif

void *
thread_func(void *dmy)
{
    return dmy;
}

int
use_threads(void)
{
    pthread_t tid;
    if (pthread_create(&tid, 0, thread_func, 0) != 0) {
	return -1;
    }
    if (pthread_join(tid, 0) != 0) {
	return -1;
    }
    return 0;
}

int
main(int argc, char *argv[])
{
    pid_t pid;
    if (use_threads()) return EXIT_FAILURE;
    pid = fork();

    if (pid) {
	int loc;
	sleep(1);
	if (waitpid(pid, &loc, WNOHANG) == 0) {
	    kill(pid, SIGKILL);
	    return EXIT_FAILURE;
	}
        if (!WIFEXITED(loc) || WEXITSTATUS(loc) != EXIT_SUCCESS)
           return EXIT_FAILURE;
    }
    else {
	if (use_threads()) return EXIT_FAILURE;
    }

    return EXIT_SUCCESS;
}],
	rb_cv_fork_with_pthread=yes,
	rb_cv_fork_with_pthread=no,
	rb_cv_fork_with_pthread=yes)])
    test x$rb_cv_fork_with_pthread = xyes || AC_DEFINE(CANNOT_FORK_WITH_PTHREAD)
])
}

: "runtime section" && {
dnl wheather use dln_a_out or not
AC_ARG_WITH(dln-a-out,
	AS_HELP_STRING([--with-dln-a-out], [use dln_a_out if possible]),
	[
	AS_CASE([$withval],
	[yes], [
	    AS_IF([test "$enable_shared" = yes], [
		AC_MSG_ERROR(dln_a_out can not make shared library)
	    ])
	    with_dln_a_out=yes],
	[
	    with_dln_a_out=no])], [with_dln_a_out=no])

AC_CACHE_CHECK(whether ELF binaries are produced, rb_cv_binary_elf,
[AC_TRY_LINK([],[], [
AS_CASE(["`head -1 conftest$EXEEXT | tr -dc '\177ELF' | tr '\177' .`"],
[.ELF*], [rb_cv_binary_elf=yes], [rb_cv_binary_elf=no])],
rb_cv_binary_elf=no)])

AS_IF([test "$rb_cv_binary_elf" = yes], [
  AC_DEFINE(USE_ELF)
  AS_IF([test "$with_dln_a_out" = yes], [
    AC_MSG_ERROR(dln_a_out does not work with ELF)
  ])
  AC_CHECK_HEADERS([elf.h elf_abi.h])
  AS_IF([test $ac_cv_header_elf_h = yes -o $ac_cv_header_elf_abi_h = yes], [
    AC_LIBOBJ([addr2line])
    AS_IF([test "x$compress_debug_sections" = xzlib], [
      AC_CHECK_LIB([z], [uncompress])
    ])
  ])
])

AC_CHECK_HEADERS([mach-o/loader.h])
AS_IF([test "$ac_cv_header_mach_o_loader_h" = yes], [
  AC_LIBOBJ([addr2line])
])

AS_CASE(["$target_os"],
[linux* | gnu* | k*bsd*-gnu | bsdi* | kopensolaris*-gnu], [
    AS_IF([test "$rb_cv_binary_elf" = no], [
	with_dln_a_out=yes
    ], [
	LDFLAGS="$LDFLAGS -rdynamic"
    ])])
LIBEXT=a

AC_ARG_WITH(mjit-tabs,
    AS_HELP_STRING([--without-mjit-tabs], [expand tabs in mjit header]),
    [AS_IF([test $withval = no], [MJIT_TABS=false])])
AC_SUBST(MJIT_TABS)dnl
AC_SUBST(DLDFLAGS)dnl
AC_SUBST(ARCH_FLAG)dnl
AC_SUBST(MJIT_HEADER_FLAGS)dnl
AC_SUBST(MJIT_HEADER_INSTALL_DIR)dnl
AC_SUBST(MJIT_CC)dnl
AS_IF([test "$GCC" = "yes"], [
    AS_CASE(["$target_os"],[aix*],[mjit_std_cflag="-std=gnu99"])
])
AC_SUBST(MJIT_CFLAGS, [${MJIT_CFLAGS-"-w ${mjit_std_cflag} ${orig_cflags}"}])dnl
AC_SUBST(MJIT_OPTFLAGS, [${MJIT_OPTFLAGS-'$(optflags)'}])dnl
AC_SUBST(MJIT_DEBUGFLAGS, [${MJIT_DEBUGFLAGS-'$(debugflags)'}])dnl
AC_SUBST(MJIT_LDSHARED)dnl

AC_SUBST(STATIC)dnl
AC_SUBST(CCDLFLAGS)dnl
AC_SUBST(LDSHARED)dnl
AC_SUBST(LDSHAREDXX)dnl
AC_SUBST(DLEXT)dnl
AC_SUBST(DLEXT2)dnl
AC_SUBST(LIBEXT)dnl
AC_SUBST(ASMEXT, S)dnl

STATIC=

AS_IF([test "$with_dln_a_out" != yes], [
  rb_cv_dlopen=unknown
  AC_MSG_CHECKING(whether OS depend dynamic link works)
  AS_IF([test "$GCC" = yes], [
    AS_CASE(["$target_os"],
    [darwin*], [
      # The -fno-common is needed if we wish to embed the Ruby interpreter
      # into a plugin module of some project (as opposed to embedding it
      # within the project's application).  The -I/usr/local/include is
      # needed because CPP as discovered by configure (cc -E -traditional)
      # fails to consult /usr/local/include by default.  This causes
      # mkmf.rb's have_header() to fail if the desired resource happens to be
      # installed in the /usr/local tree.
      RUBY_APPEND_OPTION(CCDLFLAGS, -fno-common)],
    [bsdi*|cygwin*|mingw*|aix*|interix*], [ ],
    [
      RUBY_APPEND_OPTION(CCDLFLAGS, -fPIC)])
  ], [
    AS_CASE(["$target_os"],
	[hpux*],          [CCDLFLAGS="$CCDLFLAGS +Z"],
	[solaris*|irix*], [CCDLFLAGS="$CCDLFLAGS -KPIC"],
	[sunos*],         [CCDLFLAGS="$CCDLFLAGS -PIC"],
	[esix*|uxpds*],   [CCDLFLAGS="$CCDLFLAGS -KPIC"],
	                  [: ${CCDLFLAGS=""}])
  ])


  AC_ARG_ENABLE(rpath,
       AS_HELP_STRING([--enable-rpath], [embed run path into extension libraries.
       enabled by default on ELF platforms]),
       [enable_rpath=$enableval], [enable_rpath="$rb_cv_binary_elf"])

  AS_CASE(["$target_os"],
	[hpux*], [	DLDFLAGS="$DLDFLAGS -E"
			: ${LDSHARED='$(LD) -b'}
			XLDFLAGS="$XLDFLAGS -Wl,-E"
			: ${LIBPATHENV=SHLIB_PATH}
			rb_cv_dlopen=yes],
	[solaris*], [	AS_IF([test "$GCC" = yes], [
			    : ${LDSHARED='$(CC) -shared'}
			    AS_IF([test "$rb_cv_prog_gnu_ld" = yes], [
				LDFLAGS="$LDFLAGS -Wl,-E"
			    ])
			], [
			    : ${LDSHARED='$(CC) -G'}
			])
			AS_IF([test "$ac_cv_sizeof_voidp" = 8], [
			    : ${LIBPATHENV=LD_LIBRARY_PATH_64}
			    : ${PRELOADENV=LD_PRELOAD_64}
			], [
			    : ${LIBPATHENV=LD_LIBRARY_PATH_32}
			    : ${PRELOADENV=LD_PRELOAD_32}
			])
			rb_cv_dlopen=yes],
	[sunos*], [	: ${LDSHARED='$(LD) -assert nodefinitions'}
			rb_cv_dlopen=yes],
	[irix*], [	: ${LDSHARED='$(LD) -shared'}
			rb_cv_dlopen=yes],
	[sysv4*], [	: ${LDSHARED='$(LD) -G'}
			rb_cv_dlopen=yes],
	[nto-qnx*], [	: ${LDSHARED='$(CC) -shared'}
			rb_cv_dlopen=yes],
	[esix*|uxpds*], [ : ${LDSHARED='$(LD) -G'}
			rb_cv_dlopen=yes],
	[osf*], [	: ${LDSHARED='$(LD) -shared -expect_unresolved "*"'}
			rb_cv_dlopen=yes],
	[bsdi3*], [	AS_CASE(["$CC"],
			[*shlicc*], [	: ${LDSHARED='$(CC) -r'}
					rb_cv_dlopen=yes])],
	[linux* | gnu* | k*bsd*-gnu | netbsd* | bsdi* | kopensolaris*-gnu | haiku*], [
			: ${LDSHARED='$(CC) -shared'}
			AS_IF([test "$rb_cv_binary_elf" = yes], [
			    LDFLAGS="$LDFLAGS -Wl,-export-dynamic"
			])
			rb_cv_dlopen=yes],
	[interix*], [	: ${LDSHARED='$(CC) -shared'}
			XLDFLAGS="$XLDFLAGS -Wl,-E"
			LIBPATHFLAG=" -L%1\$-s"
			rb_cv_dlopen=yes],
	[freebsd*|dragonfly*], [
			: ${LDSHARED='$(CC) -shared'}
			AS_IF([test "$rb_cv_binary_elf" = yes], [
			    LDFLAGS="$LDFLAGS -rdynamic"
			    DLDFLAGS="$DLDFLAGS "'-Wl,-soname,$@'
			], [
			  test "$GCC" = yes && test "$rb_cv_prog_gnu_ld" = yes || LDSHARED='$(LD) -Bshareable'
			])
			rb_cv_dlopen=yes],
	[openbsd*|mirbsd*], [	: ${LDSHARED='$(CC) -shared ${CCDLFLAGS}'}
			AS_IF([test "$rb_cv_binary_elf" = yes], [
			    LDFLAGS="$LDFLAGS -Wl,-E"
			])
			rb_cv_dlopen=yes],
	[darwin*], [	: ${LDSHARED='$(CC) -dynamic -bundle'}
			: ${DLDSHARED='$(CC) -dynamiclib'}
			: ${LDFLAGS=""}
			: ${LIBPATHENV=DYLD_FALLBACK_LIBRARY_PATH}
			: ${PRELOADENV=DYLD_INSERT_LIBRARIES}
			rb_cv_dlopen=yes],
        [aix*], [	: ${LDSHARED='$(CC)'}
			AS_IF([test "$GCC" = yes], [
			    LDSHARED="$LDSHARED ${linker_flag}-G -shared"
			], [
			    LDSHARED="$LDSHARED ${linker_flag}-G"
			])
			EXTDLDFLAGS='-e$(TARGET_ENTRY)'
			XLDFLAGS="${linker_flag}"'-bE:$(ARCHFILE)'" ${linker_flag}-brtl"
			XLDFLAGS="$XLDFLAGS ${linker_flag}-blibpath:${prefix}/lib:${LIBPATH:-/usr/lib:/lib}"
			: ${ARCHFILE="ruby.imp"}
                        TRY_LINK='$(CC) -oconftest $(INCFLAGS) -I$(hdrdir) $(CPPFLAGS)'
                        TRY_LINK="$TRY_LINK"' $(CFLAGS) $(src) $(LIBPATH) $(LDFLAGS) $(LOCAL_LIBS) $(LIBS)'
			: ${LIBPATHENV=LIBPATH}
			: ${PRELOADENV=LDR_PRELOAD}
			rb_cv_dlopen=yes],
	[nto-qnx*], [	DLDFLAGS="$DLDFLAGS -L/lib -L/usr/lib -L/usr/local/lib"
			: ${LDSHARED='$(LD) -Bshareable -x'}
			LDFLAGS="$LDFLAGS -L/lib -L/usr/lib -L/usr/local/lib"
			rb_cv_dlopen=yes],
	[cygwin*|mingw*], [
			: ${LDSHARED='$(CC) -shared'}
			XLDFLAGS="$XLDFLAGS -Wl,--stack,0x00200000,--enable-auto-import"
			DLDFLAGS="${DLDFLAGS} -Wl,--enable-auto-image-base,--enable-auto-import"
			: ${LIBPATHENV=PATH}
			: ${PRELOADENV=""}
			rb_cv_dlopen=yes],
	[hiuxmpp], [	: ${LDSHARED='$(LD) -r'}],
	[atheos*], [	: ${LDSHARED='$(CC) -shared'}
			rb_cv_dlopen=yes],
	[	: ${LDSHARED='$(LD)'}])
  AC_MSG_RESULT($rb_cv_dlopen)

  AS_IF([test "$rb_cv_dlopen" = yes], [
    AS_CASE(["$target_os"],
      [darwin*], [
	for flag in \
	  "-undefined dynamic_lookup" \
	  "-multiply_defined suppress" \
	  ; do
	  test "x${linker_flag}" = x || flag="${linker_flag}`echo ${flag} | tr ' ' ,`"
	  RUBY_TRY_LDFLAGS([$flag], [], [flag=])
	  AS_IF([test "x$flag" != x], [
	    RUBY_APPEND_OPTIONS(DLDFLAGS, [$flag])
	  ])
	done
      ])
  ])

  AS_IF([test "$enable_rpath:${RPATHFLAG}" = yes:], [
      AS_IF([test "x$rpathflag" != x], [
	  RPATHFLAG=" ${rpathflag}%1\$-s"
      ])
  ])
])
AS_IF([test "${LDSHAREDXX}" = ""], [
    AS_CASE(["${LDSHARED}"],
	[*'$(CC)'*], [
	    LDSHAREDXX=`echo "${LDSHARED}" | sed 's/\$(CC)/$(CXX)/'`
	    ],
	[*'${CC}'*], [
	    LDSHAREDXX=`echo "${LDSHARED}" | sed 's/\${CC}/${CXX}/'`
	    ],
	[*$CC*], [
	    LDSHAREDXX=`echo "${LDSHARED}" | sed "s|$CC|$CXX|"`
	    ],
	[ld" "*], [
	    ])
])
AS_CASE([${RPATHFLAG}],[*'%1$'*],[: ${LIBPATHFLAG=' -L%1$-s'}],[: ${LIBPATHFLAG=' -L%s'}])

AC_SUBST(LINK_SO)
AC_SUBST(LIBPATHFLAG)
AC_SUBST(RPATHFLAG)
AC_SUBST(LIBPATHENV, "${LIBPATHENV-LD_LIBRARY_PATH}")
AC_SUBST(PRELOADENV, "${PRELOADENV-LD_PRELOAD}")
AC_SUBST(TRY_LINK)

AS_IF([test "x$OPT_DIR" != x], [
    pat=`echo "${LDFLAGS_OPTDIR}" | sed ['s/[][\\.*|]/\\\\&/']`
    LDFLAGS=`echo "${LDFLAGS}" | sed "s| ${pat}||"`
    val=`IFS="$PATH_SEPARATOR"
        for dir in $OPT_DIR; do
            echo x ${LIBPATHFLAG} ${RPATHFLAG} |
            sed "s/^x *//;s${IFS}"'%1\\$-s'"${IFS}${dir}/lib${IFS}g;s${IFS}%s${IFS}${dir}/lib${IFS}g"
        done | tr '\012' ' ' | sed 's/ *$//'`
    AS_IF([test x"$val" != x], [
	test x"${LDFLAGS}" = x || LDFLAGS="$LDFLAGS "
	LDFLAGS="$LDFLAGS$val"
	test x"${DLDFLAGS}" = x || DLDFLAGS="$DLDFLAGS "
	DLDFLAGS="$DLDFLAGS$val"
    ])
    LDFLAGS_OPTDIR="$val"
])

AS_CASE(["$target_os"],
[freebsd*], [
    AC_CHECK_LIB([procstat], [procstat_open_sysctl])
    AS_IF([test "x$ac_cv_lib_procstat_procstat_open_sysctl" = xyes], [
	AC_CHECK_FUNCS(procstat_getvmmap)
    ])
    ])
AS_CASE(["$target_cpu-$target_os"],
[*-darwin*], [
    AC_CHECK_HEADERS([libproc.h])
    AC_CHECK_HEADERS([execinfo.h])
    AS_IF([test "x$ac_cv_header_execinfo_h" = xyes], [
	AC_CHECK_LIB([execinfo], [backtrace])
	AC_CHECK_HEADERS([libunwind.h])
    ])],
[*-freebsd*|x86_64-netbsd*], [
    AC_CHECK_HEADERS([execinfo.h])
    AS_IF([test "x$ac_cv_header_execinfo_h" = xyes], [
	AC_CHECK_LIB([execinfo], [backtrace])
	AC_CHECK_LIB([unwind], [unw_backtrace])
    ])])
AC_CHECK_FUNCS(backtrace)

AS_IF([test "x$ac_cv_func_backtrace" = xyes], [
  AC_CACHE_CHECK(for broken backtrace, rb_cv_broken_backtrace,
    [AC_TRY_RUN([
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <signal.h>
#include <execinfo.h>

]`grep '^@%:@ *define  *RUBY_SIGALTSTACK_SIZE' ${srcdir}/signal.c`[
#define TRACE_SIZE 256

void sigsegv(int signum, siginfo_t *info, void *ctx){
    void *trace[TRACE_SIZE];
    int n = backtrace(trace, TRACE_SIZE);
    if (n > 0) {
	/*fprintf(stdout, "backtrace:%d\n",n);*/
    } else {
	_exit(EXIT_FAILURE);
    }
    _exit(EXIT_SUCCESS);
}
int
main(void)
{
    volatile int *a = NULL;
    stack_t ss;
    struct sigaction sa;

    ss.ss_sp = malloc(RUBY_SIGALTSTACK_SIZE);
    if (ss.ss_sp == NULL) {
	fprintf(stderr, "cannot allocate memory for sigaltstack\n");
	return EXIT_FAILURE;
    }
    ss.ss_size = RUBY_SIGALTSTACK_SIZE;
    ss.ss_flags = 0;
    if (sigaltstack(&ss, NULL) == -1) {
	fprintf(stderr, "sigaltstack failed\n");
	return EXIT_FAILURE;
    }
    memset(&sa, 0, sizeof(struct sigaction));
    sigemptyset(&sa.sa_mask);
    sa.sa_sigaction = sigsegv;
    sa.sa_flags |= SA_SIGINFO;
    sa.sa_flags |= SA_ONSTACK;
    sigaction(SIGSEGV, &sa, NULL);
    a[0] = 1;
    return EXIT_SUCCESS;
}
],
	rb_cv_broken_backtrace=no,
	rb_cv_broken_backtrace=yes,
	rb_cv_broken_backtrace=no)])
  AS_IF([test "$rb_cv_broken_backtrace" = yes], [
    AC_DEFINE(BROKEN_BACKTRACE, 1)
  ])
])

AC_ARG_WITH(valgrind,
        AS_HELP_STRING([--without-valgrind],[disable valgrind memcheck support]),
        [], with_valgrind=yes)
AS_IF([test x$with_valgrind != xno],
        [AC_CHECK_HEADERS(valgrind/memcheck.h)])

dln_a_out_works=no
AS_IF([test "$ac_cv_header_a_out_h" = yes], [
  AS_IF([test "$with_dln_a_out" = yes || test "$rb_cv_dlopen" = unknown], [
    cat confdefs.h > config.h
    AC_CACHE_CHECK(whether matz's dln works, rb_cv_dln_a_out,
    [AC_TRY_COMPILE([
#define USE_DLN_A_OUT
#include "dln.c"
],
	[],
	rb_cv_dln_a_out=yes,
	rb_cv_dln_a_out=no)])
    AS_IF([test "$rb_cv_dln_a_out" = yes], [
      dln_a_out_works=yes
      AC_DEFINE(USE_DLN_A_OUT)
    ])
  ])
])

AS_IF([test "$dln_a_out_works" = yes], [
  AS_IF([test "$GCC" = yes], [
    STATIC=-static
  ], [
    STATIC=-Bstatic
  ])
  DLEXT=so
  CCDLFLAGS=
], [
  AS_CASE(["$target_os"],
    [hpux*], [
	DLEXT=sl],
    [darwin*], [
	SOEXT=dylib
	DLEXT=bundle],
    [cygwin*|mingw*|*djgpp*], [
	LOAD_RELATIVE=1
	SOEXT=dll
	DLEXT=so],
    [
	DLEXT=so])
])
: ${SOEXT="${DLEXT}"}
AC_SUBST(SOEXT)
AS_IF([test "$rb_cv_dlopen:$load_relative" = yes:yes], [
    AS_IF([test "$ac_cv_func_dladdr" = yes], [
	LOAD_RELATIVE=1
    ])
])
AS_IF([test x"$LOAD_RELATIVE" = x1], [
    load_relative=yes
], [
    unset load_relative
])

len=2 # .rb
n=`expr "$DLEXT"  : '.*'`; test "$n" -gt "$len" && len=$n
n=`expr "$DLEXT2" : '.*'`; test "$n" -gt "$len" && len=$n
AC_DEFINE_UNQUOTED(DLEXT_MAXLEN, `expr $len + 1`)
test ".$DLEXT"  = "." || AC_DEFINE_UNQUOTED(DLEXT,  ".$DLEXT")
test ".$DLEXT2" = "." || AC_DEFINE_UNQUOTED(DLEXT2, ".$DLEXT2")
AC_SUBST(DLEXT)

AS_IF([test "$with_dln_a_out" = yes], [
  STRIP=true
], [
    AC_MSG_CHECKING([for $STRIP flags])
    AC_LINK_IFELSE([AC_LANG_PROGRAM], [AS_IF(
        ["${STRIP}" -A -n conftest$ac_exeext 2>/dev/null], [
            AC_MSG_RESULT([-A -n])
            STRIP="${STRIP} -A -n"
        ],
        ["${STRIP}" -S -x conftest$ac_exeext 2>/dev/null], [
            AC_MSG_RESULT([-S -x])
            STRIP="${STRIP} -S -x"
        ], [
            AC_MSG_RESULT([none needed])
        ])
    ])
])


AC_ARG_WITH(ext,
            AC_HELP_STRING([--with-ext=EXTS],
                           [pass to --with-ext option of extmk.rb]))
AC_ARG_WITH(out-ext,
            AC_HELP_STRING([--with-out-ext=EXTS],
                           [pass to --without-ext option of extmk.rb]))
EXTSTATIC=
AC_SUBST(EXTSTATIC)dnl
AC_ARG_WITH(static-linked-ext,
	    AS_HELP_STRING([--with-static-linked-ext], [link external modules statically]),
            [AS_CASE([$withval],[yes],[STATIC=;EXTSTATIC=static],[no],[],[EXTSTATIC="$withval"])])
AS_CASE([",$EXTSTATIC,"], [,static,|*,enc,*], [
  ENCOBJS='enc/encinit.$(OBJEXT) enc/libenc.$(LIBEXT) enc/libtrans.$(LIBEXT)'
  EXTOBJS='ext/extinit.$(OBJEXT)'
  AC_DEFINE_UNQUOTED(EXTSTATIC, 1)
  AC_SUBST(ENCSTATIC, static)
], [
  ENCOBJS='dmyenc.$(OBJEXT)'
  EXTOBJS='dmyext.$(OBJEXT)'
])
AC_SUBST(ENCOBJS)
AC_SUBST(EXTOBJS)

AC_ARG_WITH(setup,
	    AS_HELP_STRING([--with-setup=SETUP], [use extension libraries setup]),
	    [setup=$withval])
AS_IF([test -n "$setup"], [
    AS_IF([! test -f "ext/$setup" -o -f "$srcdir/ext/$setup"], [
	AC_MSG_ERROR(Setup file $setup not found under ext or $srcdir/ext)
    ])
], [test -f "$srcdir/ext/Setup.$target_os"], [
    setup="Setup.$target_os"
], [
    setup=
    for file in "$srcdir"/ext/Setup.*; do
	AS_CASE(["$file"], [*~|*.bak|*.orig|*.rej|*.tmp], [continue])
	setup=`basename "$file"`
	AS_CASE(["$target_os"], [`expr "$setup" : 'Setup.\(.*\)'`*], [break])
	platform=`sed '/^option  *platform  */!d;s///;s/|/*|/g;q' "$file"`
	AS_IF([test "x$platform" != x], [
	    eval "AS_CASE([\"\$target_os\"], [$platform*], [break])"
	])
	setup=
    done
    : ${setup:=Setup}
])
AC_SUBST(setup)

rubylibprefix='${libdir}/${RUBY_BASE_NAME}'
AC_ARG_WITH(rubylibprefix,
	    AS_HELP_STRING([--with-rubylibprefix=DIR], [prefix for ruby libraries [[LIBDIR/RUBY_BASE_NAME]]]),
	    [AS_IF([test "x$withval" = xno], [
		AC_MSG_ERROR([No ruby, No libprefix])
	    ])
	    rubylibprefix="$withval"])
AC_SUBST(rubylibprefix)

AS_IF([test x"${exec_prefix}" != xNONE], [
    RUBY_EXEC_PREFIX="$exec_prefix"
], [test x"$prefix" != xNONE], [
    RUBY_EXEC_PREFIX="$prefix"
], [
    RUBY_EXEC_PREFIX=$ac_default_prefix
])
pat=`echo "${RUBY_EXEC_PREFIX}" | tr -c '\012' .`'\(.*\)'
for var in bindir libdir rubylibprefix; do
    eval val='"$'$var'"'
    AS_CASE(["$val"], ["${RUBY_EXEC_PREFIX}"*], [val='${exec_prefix}'"`expr \"$val\" : \"$pat\"`"])
    eval $var='"$val"'
done

BTESTRUBY='$(MINIRUBY)'
BOOTSTRAPRUBY='$(BASERUBY)'
AS_IF([test x"$cross_compiling" = xyes], [
  test x"$MINIRUBY" = x && MINIRUBY="${RUBY-$BASERUBY} -I`$CHDIR .; pwd` "-r'$(arch)-fake'
  XRUBY_LIBDIR=`${RUBY-$BASERUBY} -rrbconfig -e ['puts RbConfig::CONFIG["libdir"]']`
  XRUBY_RUBYLIBDIR=`${RUBY-$BASERUBY} -rrbconfig -e ['puts RbConfig::CONFIG["rubylibdir"]']`
  XRUBY_RUBYHDRDIR=`${RUBY-$BASERUBY} -rrbconfig -e ['puts RbConfig::CONFIG["rubyhdrdir"]']`
  AC_SUBST(XRUBY_LIBDIR)
  AC_SUBST(XRUBY_RUBYLIBDIR)
  AC_SUBST(XRUBY_RUBYHDRDIR)
  PREP='$(arch)-fake.rb'
  RUNRUBY_COMMAND='$(MINIRUBY) -I`cd $(srcdir)/lib; pwd`'
  RUNRUBY='$(RUNRUBY_COMMAND)'
  XRUBY='$(MINIRUBY)'
  TEST_RUNNABLE=no
  CROSS_COMPILING=yes
  AC_DEFINE(CROSS_COMPILING, 1)
], [
  MINIRUBY='./miniruby$(EXEEXT) -I$(srcdir)/lib -I.'
  MINIRUBY="$MINIRUBY"' -I$(EXTOUT)/common'
  PREP='miniruby$(EXEEXT)'
  RUNRUBY_COMMAND='$(MINIRUBY) $(tooldir)/runruby.rb --extout=$(EXTOUT) $(RUNRUBYOPT)'
  RUNRUBY='$(RUNRUBY_COMMAND) --'
  XRUBY='$(RUNRUBY)'
  AS_CASE(["$HAVE_BASERUBY:$build_os"], [no:*|*:mingw*], [BOOTSTRAPRUBY='$(MINIRUBY)'])
  TEST_RUNNABLE=yes
  CROSS_COMPILING=no
])
AC_SUBST(TEST_RUNNABLE)
AC_SUBST(CROSS_COMPILING)
AC_SUBST(MINIRUBY)
AC_SUBST(BTESTRUBY)
AC_SUBST(PREP)
AC_SUBST(RUNRUBY_COMMAND)
AC_SUBST(RUNRUBY)
AC_SUBST(XRUBY)
AC_SUBST(BOOTSTRAPRUBY)
AC_SUBST(EXTOUT, [${EXTOUT=.ext}])

FIRSTMAKEFILE=""
LIBRUBY_A='lib$(RUBY_SO_NAME)-static.a'
LIBRUBY='$(LIBRUBY_A)'
LIBRUBYARG_STATIC='-l$(RUBY_SO_NAME)-static'
LIBRUBYARG='$(LIBRUBYARG_STATIC)'
SOLIBS='$(MAINLIBS)'

AS_CASE(["$target_os"],
  [cygwin*|mingw*|haiku*|darwin*], [
    : ${DLDLIBS=""}
    ],
  [
    DLDLIBS="$DLDLIBS -lc"
    ])

AC_ARG_ENABLE(multiarch,
	      AS_HELP_STRING([--enable-multiarch], [enable multiarch compatible directories]),
	      [multiarch=], [unset multiarch])
AS_IF([test ${multiarch+set}], [
   AC_DEFINE(ENABLE_MULTIARCH)
   MJIT_HEADER_INSTALL_DIR=include/'${arch}/${RUBY_VERSION_NAME}'
], [
   MJIT_HEADER_INSTALL_DIR=include/'${RUBY_VERSION_NAME}/${arch}'
])

archlibdir='${libdir}/${arch}'
sitearchlibdir='${libdir}/${sitearch}'
archincludedir='${includedir}/${arch}'
sitearchincludedir='${includedir}/${sitearch}'

AC_ARG_WITH(soname,
	AS_HELP_STRING([--with-soname=SONAME], [base name of shared library]),
	[RUBY_SO_NAME=$withval],
	[
	    AS_CASE(["$target_os"],
	    [darwin*], [
	        RUBY_SO_NAME='$(RUBY_BASE_NAME).$(RUBY_API_VERSION)'
	    ],
	    [cygwin*], [
	        RUBY_SO_NAME='$(RUBY_BASE_NAME)$(MAJOR)$(MINOR)0'
	    ],
	    [mingw*], [
		RUBY_SO_NAME="${rb_cv_msvcrt}"'-$(RUBY_BASE_NAME)$(MAJOR)$(MINOR)0'
		AS_IF([test x"${target_cpu}" != xi386], [
		    RUBY_SO_NAME="${target_cpu}-${RUBY_SO_NAME}"
		])
	    ],
	    [RUBY_SO_NAME='$(RUBY_BASE_NAME)'])
	])

LIBRUBY_LDSHARED=${DLDSHARED=${LDSHARED}}
LIBRUBY_DLDFLAGS=$DLDFLAGS
LIBRUBY_SO='lib$(RUBY_SO_NAME).$(SOEXT).$(RUBY_PROGRAM_VERSION)'
LIBRUBY_SONAME='lib$(RUBY_SO_NAME).$(SOEXT).$(RUBY_API_VERSION)'
LIBRUBY_ALIASES='lib$(RUBY_SO_NAME).$(SOEXT)'
ENABLE_SHARED=no

AC_ARG_ENABLE(shared,
       AS_HELP_STRING([--enable-shared], [build a shared library for Ruby]),
       [enable_shared=$enableval])
libprefix=${multiarch+'$(archlibdir)'}${multiarch-'$(libdir)'}
LIBRUBY_RELATIVE=${load_relative-no}
AS_CASE("$enable_shared", [yes], [
  LIBRUBY='$(LIBRUBY_SO)'
  LIBRUBYARG_SHARED='-l$(RUBY_SO_NAME)'
  LIBRUBYARG='$(LIBRUBYARG_SHARED)'
  LIBRUBY_RELATIVE=no
  test -z "$CCDLFLAGS" || CFLAGS="$CFLAGS $CCDLFLAGS"
  ENABLE_SHARED=yes

  # libdir can be overridden in config.site file (on OpenSUSE at least).
  libdir_basename=lib
  AS_IF([test "$bindir" = '${exec_prefix}/bin'], [
    AS_CASE(["$libdir"], ['${exec_prefix}/'*], [libdir_basename=`basename "$libdir"`])
  ])
  AC_DEFINE_UNQUOTED(LIBDIR_BASENAME, ["${libdir_basename}"])
  libdir_basename="${libdir_basename}"${multiarch+'/${arch}'}

  AS_CASE(["$target_os"],
    [freebsd*|dragonfly*], [],
    [
     AS_IF([test "$GCC" = yes], [
       RUBY_TRY_LDFLAGS([${linker_flag}--no-undefined], [no_undefined=yes], [no_undefined=no])
       AS_IF([test "no_undefined" = yes], [
	  RUBY_APPEND_OPTION(EXTLDFLAGS, [${linker_flag}--no-undefined])
       ])
     ])
    ])

  AS_CASE(["$target_os"],
    [sunos4*], [
	LIBRUBY_ALIASES='$(LIBRUBY_SONAME) lib$(RUBY_SO_NAME).$(SOEXT)'
	],
    [linux* | gnu* | k*bsd*-gnu | atheos* | kopensolaris*-gnu | haiku*], [
	RUBY_APPEND_OPTIONS(LIBRUBY_DLDFLAGS, ['-Wl,-soname,$(LIBRUBY_SONAME)' "$LDFLAGS_OPTDIR"])
	LIBRUBY_ALIASES='$(LIBRUBY_SONAME) lib$(RUBY_SO_NAME).$(SOEXT)'
	AS_IF([test "$load_relative" = yes], [
	    libprefix="'\$\${ORIGIN}/../${libdir_basename}'"
	    LIBRUBY_RPATHFLAGS="-Wl,-rpath,${libprefix}"
	    LIBRUBY_RELATIVE=yes
	])
	],
    [freebsd*|dragonfly*], [
	LIBRUBY_SO='lib$(RUBY_SO_NAME).$(SOEXT).$(MAJOR)$(MINOR)'
	LIBRUBY_SONAME='$(LIBRUBY_SO)'
	AS_IF([test "$rb_cv_binary_elf" != "yes" ], [
	    LIBRUBY_SO="$LIBRUBY_SO.\$(TEENY)"
	    LIBRUBY_ALIASES=''
	])
	],
    [netbsd*], [
	LIBRUBY_SONAME='lib$(RUBY_SO_NAME).$(SOEXT).$(MAJOR)$(MINOR)'
	LIBRUBY_SO="${LIBRUBY_SONAME}"'.$(TEENY)'
	RUBY_APPEND_OPTIONS(LIBRUBY_DLDFLAGS, ['-Wl,-soname,$(LIBRUBY_SONAME)' "$LDFLAGS_OPTDIR"])
	AS_IF([test "$rb_cv_binary_elf" = yes], [ # ELF platforms
	   LIBRUBY_ALIASES='$(LIBRUBY_SONAME) lib$(RUBY_SO_NAME).$(SOEXT)'
	], [	# a.out platforms
	   LIBRUBY_ALIASES=""
	])
	],
    [openbsd*|mirbsd*], [
	LIBRUBY_SO='lib$(RUBY_SO_NAME).$(SOEXT).$(MAJOR).'`expr ${MINOR} \* 10 + ${TEENY}`
	],
    [solaris*], [
	LIBRUBY_SO='lib$(RUBY_SO_NAME).$(SOEXT).$(MAJOR)'
	LIBRUBY_SONAME='lib$(RUBY_SO_NAME).$(SOEXT).$(RUBY_PROGRAM_VERSION)'
	LIBRUBY_ALIASES='$(LIBRUBY_SONAME) lib$(RUBY_SO_NAME).$(SOEXT)'
	RUBY_APPEND_OPTIONS(LIBRUBY_DLDFLAGS, ["${linker_flag}-h${linker_flag:+,}"'$(@F)'])
	XLDFLAGS="$XLDFLAGS "'-R${libdir}'
	],
    [hpux*], [
	XLDFLAGS="$XLDFLAGS "'-Wl,+s,+b,$(libdir)'
	LIBRUBY_ALIASES='$(LIBRUBY_SONAME) lib$(RUBY_SO_NAME).$(SOEXT)'
	],
    [aix*], [
	RUBY_APPEND_OPTIONS(LIBRUBY_DLDFLAGS, ["${linker_flag}-bnoentry" "$XLDFLAGS" "$LDFLAGS_OPTDIR"])
	LIBRUBYARG_SHARED='-L${libdir} -l${RUBY_SO_NAME}'
	LIBS="$LIBS -lm -lc"
	],
    [darwin*], [
	LIBRUBY_SO='lib$(RUBY_SO_NAME).$(SOEXT)'
	LIBRUBY_SONAME='$(LIBRUBY_SO)'
	LIBRUBY_ALIASES='lib$(RUBY_INSTALL_NAME).$(SOEXT)'
	AS_IF([test "$load_relative" = yes], [
	    libprefix="@executable_path/../${libdir_basename}"
	    LIBRUBY_RELATIVE=yes
	])
	LIBRUBY_DLDFLAGS="$LIBRUBY_DLDFLAGS -install_name ${libprefix}"'/$(LIBRUBY_SONAME)'
	LIBRUBY_DLDFLAGS="$LIBRUBY_DLDFLAGS "'-compatibility_version $(RUBY_API_VERSION)'
	LIBRUBY_DLDFLAGS="$LIBRUBY_DLDFLAGS "'-current_version $(RUBY_PROGRAM_VERSION)'
	AS_IF([test "$visibility_option" = ld], [
	    LIBRUBY_DLDFLAGS="$LIBRUBY_DLDFLAGS "'-Wl,-unexported_symbol,_Init_*'
	    LIBRUBY_DLDFLAGS="$LIBRUBY_DLDFLAGS "'-Wl,-unexported_symbol,_ruby_static_id_*'
	    LIBRUBY_DLDFLAGS="$LIBRUBY_DLDFLAGS "'-Wl,-unexported_symbol,*_threadptr_*'
	])
	LIBRUBY_DLDFLAGS="$LIBRUBY_DLDFLAGS "' $(XLDFLAGS)'
	],
    [interix*], [
	LIBRUBYARG_SHARED='-L. -L${libdir} -l$(RUBY_SO_NAME)'
	],
    [mingw*|cygwin*|mswin*], [
	LIBRUBY_RELATIVE=yes
	])
], [
  LIBRUBYARG_SHARED=

  # enable PIE if possible
  AC_ARG_ENABLE(pie,
          AS_HELP_STRING([--disable-pie], [disable PIE feature]),
          [pie=$enableval], [pie=])
  AS_IF([test "$GCC" = yes -a -z "$EXTSTATIC" -a "x$pie" != xno], [
    RUBY_TRY_CFLAGS(-fPIE, [pie=yes], [pie=no])
    AS_IF([test "$pie" = yes], [
      # Use -fPIE when testing -pie.  RUBY_TRY_LDFLAGS sets
      # $save_CFLAGS internally, so set other name here.
      save_CFLAGS_before_pie="$CFLAGS"
      CFLAGS="$CFLAGS -fPIE"

      # gcc need -pie but clang need -Wl,-pie.
      for pie in -pie -Wl,-pie; do
	RUBY_TRY_LDFLAGS([$pie], [], [pie=])
	AS_IF([test "x$pie" != x], [
	  RUBY_APPEND_OPTION(XCFLAGS, -fPIE)
	  RUBY_APPEND_OPTION(XLDFLAGS, $pie)
	  break
	])
      done
      CFLAGS="$save_CFLAGS_before_pie"
    ])
  ])
])
AS_IF([test "$enable_rpath" = yes], [
    test -z "$LIBRUBY_RPATHFLAGS" || LIBRUBY_RPATHFLAGS="$LIBRUBY_RPATHFLAGS "
    rpathflag="${RPATHFLAG}"
    AS_CASE(["${cross_compiling}${load_relative}"], [*yes*], [], [rpathflag="$RPATHFLAG$LIBPATHFLAG"])
    rpathflag=`IFS="$PATH_SEPARATOR"
        echo x "$rpathflag" |
        sed "s/^x *//;s${IFS}"'%1\\$-s'"${IFS}${libprefix}${IFS}g;s${IFS}%s${IFS}${libprefix}${IFS}g"
    `
    LIBRUBY_RPATHFLAGS="$LIBRUBY_RPATHFLAGS${rpathflag}"
    LIBRUBYARG_SHARED="$LIBRUBY_RPATHFLAGS $LIBRUBYARG_SHARED"
    LIBRUBYARG_STATIC="$LIBRUBY_RPATHFLAGS $LIBRUBYARG_STATIC"
])
AC_SUBST(LIBRUBY_RELATIVE)

LDFLAGS="-L. $LDFLAGS"
AC_SUBST(ARCHFILE)

AS_IF([test "$EXEEXT" = .exe], [
    EXECUTABLE_EXTS='".exe",".com",".cmd",".bat"'
    AC_DEFINE_UNQUOTED(EXECUTABLE_EXTS, $EXECUTABLE_EXTS)
    EXECUTABLE_EXTS=`echo $EXECUTABLE_EXTS | tr -d '"' | tr , ' '`
    AC_SUBST(EXECUTABLE_EXTS)
])

AS_CASE("$cross_compiling:${LIBPATHENV}", [yes:* | no:], [], [
    AC_MSG_CHECKING(whether wrapper for $LIBPATHENV is needed)
    AS_IF([env ${LIBPATHENV}=/lib /bin/sh -c ': ${'${LIBPATHENV}'?}' 2>/dev/null],
	[AC_MSG_RESULT(no)],
	[PREP="$PREP"' exe/$(PROGRAM)'
	AC_MSG_RESULT(yes)]
    )
])

AC_ARG_ENABLE(dtrace,
        AS_HELP_STRING([--enable-dtrace],
        [enable DTrace for tracing inside ruby. enabled by default on systems having dtrace]),
        [enable_dtrace=$enableval], [enable_dtrace=auto])

LIBRUBY_A_OBJS='$(OBJS)'
DTRACE_REBUILD=
AS_CASE(["${enable_dtrace}"],
[yes|auto], [
    RUBY_DTRACE_AVAILABLE()
], [
    rb_cv_dtrace_available=no
])
AS_IF([test "${enable_dtrace}" = yes], [dnl
    AS_IF([test -z "$DTRACE"], [dnl
	AC_MSG_ERROR([dtrace(1) is missing])
    ], [test "$cross_compiling" = yes], [dnl
	AC_MSG_ERROR([--enable-dtrace, however, cross compiling])
    ], [test "${rb_cv_dtrace_available}" = "no"], [dnl
       AC_MSG_ERROR([--enable-dtrace, however, USDT is not available])
    ])
])
AS_CASE([$rb_cv_dtrace_available],
[yes*], [dnl
    RUBY_DTRACE_POSTPROCESS()
    AS_IF([test "$rb_cv_prog_dtrace_g" != no], [dnl
	DTRACE_OBJ='probes.$(OBJEXT)'
    ])
    AS_IF([test "$rb_cv_prog_dtrace_g" = rebuild], [dnl
	DTRACE_REBUILD=yes
	LIBRUBY_A_OBJS='$(DTRACE_GLOMMED_OBJ)'
    ])
    AS_CASE("${target_os}", [freebsd*], [dnl
        # FreeBSD's dtrace requires libelf
        LIBS="-lelf $LIBS"
    ])
    DTRACE_EXT=d
], [dnl
    enable_dtrace=no
    DTRACE_EXT=dmyh
])
AC_SUBST(DTRACE_EXT)
AC_SUBST(DTRACE_OBJ)
AC_SUBST(DTRACE_REBUILD)
AC_SUBST(DTRACE_OPT)
AC_SUBST(LIBRUBY_A_OBJS)

AC_ARG_ENABLE(gcov,
       AS_HELP_STRING([--enable-gcov], [enable coverage measurement by gcov]),
       [gcov=yes])
AS_IF([test x"$gcov" = xyes], [
    CFLAGS="$CFLAGS -coverage"
    LDFLAGS="$LDFLAGS -coverage"
])

RUBY_SETJMP_TYPE
}

: "build section" && {
dnl build rdoc index if requested
RDOCTARGET=""
CAPITARGET=""
AC_ARG_ENABLE(install-doc,
       AS_HELP_STRING([--disable-install-doc], [do not install either rdoc indexes or C API documents during install]),
       [install_doc=$enableval], [install_doc=yes])
AC_ARG_WITH(rdoc,
      AS_HELP_STRING([--with-rdoc=ri,html], [comma/space separated list of RDoc formats to install]),
      [install_rdoc=`echo ,$withval, | sed 'y/,/ /;s/ ri / rdoc /;s/^ *//;s/ *$//'`], [
AC_ARG_ENABLE(install-rdoc,
      AS_HELP_STRING([--disable-install-rdoc], [do not install rdoc indexes during install]),
      [install_rdoc=$enableval], [install_rdoc=yes])
])
AC_ARG_ENABLE(install-capi,
      AS_HELP_STRING([--disable-install-capi], [do not install C API documents during install]),
      [install_capi=$enableval], [install_capi=no])

AS_IF([test "$install_doc" != no], [
    AS_CASE(["$install_rdoc"],
    [yes], [
	RDOCTARGET="rdoc"
    ],
    [all], [
	RDOCTARGET="rdoc html"
    ],
    [no|''], [
	RDOCTARGET="nodoc"
    ],
    [
	RDOCTARGET="$install_rdoc"
    ])
    AS_IF([test "$install_capi" != no -a -n "$DOXYGEN"], [
	CAPITARGET="capi"
    ], [
	CAPITARGET="nodoc"
    ])
], [
    RDOCTARGET="nodoc"
    CAPITARGET="nodoc"
])

AC_SUBST(RDOCTARGET)
AC_SUBST(CAPITARGET)

AS_CASE(["$RDOCTARGET:$CAPITARGET"],[nodoc:nodoc],[INSTALLDOC=nodoc],[INSTALLDOC=all])
AC_SUBST(INSTALLDOC)

AC_ARG_ENABLE(jit-support,
        AS_HELP_STRING([--disable-jit-support], [disable JIT features]),
        [MJIT_SUPPORT=$enableval
         AS_IF([test x"$enable_jit_support" = "xyes"],
                 [AC_DEFINE(USE_MJIT, 1)],
                 [AC_DEFINE(USE_MJIT, 0)])],
        [MJIT_SUPPORT=yes
         AC_DEFINE(USE_MJIT, 1)])

AC_SUBST(MJIT_SUPPORT)

AC_ARG_ENABLE(install-static-library,
	AS_HELP_STRING([--disable-install-static-library], [do not install static ruby library]),
	[INSTALL_STATIC_LIBRARY=$enableval],
	AS_IF([test x"$enable_shared" = xyes],
	    [INSTALL_STATIC_LIBRARY=no],
	    [INSTALL_STATIC_LIBRARY=yes]))
AC_SUBST(INSTALL_STATIC_LIBRARY)

AS_IF([test "$rb_with_pthread" = "yes"], [
    THREAD_MODEL=pthread
])
AC_CACHE_CHECK([for prefix of external symbols], rb_cv_symbol_prefix, [
    AC_TRY_COMPILE([extern void conftest_external(void) {}], [], [
	rb_cv_symbol_prefix=`$NM conftest.$ac_objext |
			     sed -n ['/.*T[ 	]\([^ 	]*\)conftest_external.*/!d;s//\1/p;q']`
	],
	[rb_cv_symbol_prefix=''])
    test -n "$rb_cv_symbol_prefix" || rb_cv_symbol_prefix=NONE
])
SYMBOL_PREFIX="$rb_cv_symbol_prefix"
test "x$SYMBOL_PREFIX" = xNONE && SYMBOL_PREFIX=''
DLNOBJ=dln.o
AC_ARG_ENABLE(dln,
	      AC_HELP_STRING([--disable-dln], [disable dynamic link feature]),
	      [test "$enableval" = yes || DLNOBJ=dmydln.o])
AC_SUBST(DLNOBJ)
MINIDLNOBJ=dmydln.o

AS_CASE(["$target_os"],
    [linux*], [
	],
    [netbsd*], [
	RUBY_APPEND_OPTION(CFLAGS, -pipe)
	],
    [darwin*], [
	RUBY_APPEND_OPTION(CFLAGS, -pipe)
	AC_COMPILE_IFELSE([
	    AC_LANG_BOOL_COMPILE_TRY([@%:@include <AvailabilityMacros.h>],
		[MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_7])],
	    [dnl
		RUBY_APPEND_OPTION(XLDFLAGS, [-framework Security])
		RUBY_APPEND_OPTION(LIBRUBYARG_STATIC, [-framework Security])
	    ]dnl
	)
	RUBY_APPEND_OPTION(XLDFLAGS, [-framework Foundation])
	RUBY_APPEND_OPTION(LIBRUBYARG_STATIC, [-framework Foundation])
	],
    [osf*], [
	AS_IF([test "$GCC" != "yes" ], [
	  # compile something small: taint.c is fine for this.
	  # the main point is the '-v' flag of 'cc'.
	  AS_CASE(["`cc -v -I. -c main.c -o /tmp/main.o 2>&1`"],
	  [*/gemc_cc*], [   # we have the new DEC GEM CC
                        CFLAGS="$CFLAGS -oldc"
                        ],
          [            # we have the old MIPS CC
                        ])
	  # cleanup
	  rm -f /tmp/main.o
	  CFLAGS="$CFLAGS -std"
	])
	],
    [cygwin*|mingw*], [
	LIBRUBY_DLDFLAGS="${LIBRUBY_DLDFLAGS}"' -Wl,--out-implib=$(LIBRUBY)'
	AS_CASE(["$target_os"],
	[cygwin*], [
	    AS_IF([test x"$enable_shared" = xyes], [
		LIBRUBY_SO='cyg$(RUBY_SO_NAME)'.dll
		LIBRUBY_DLDFLAGS="${LIBRUBY_DLDFLAGS}"' $(RUBYDEF)'
	    ])
	    ],
	[mingw*], [
	    AS_IF([test x"$enable_shared" = xyes], [
		LIBRUBY_SO='$(RUBY_SO_NAME)'.dll
		LIBRUBY_DLDFLAGS="${LIBRUBY_DLDFLAGS}"' $(RUBYDEF)'
	    ])
	    EXPORT_PREFIX=' '
	    DLDFLAGS="${DLDFLAGS}"' $(DEFFILE)'
	    AC_LIBOBJ([win32/win32])
	    AC_LIBOBJ([win32/file])
	    COMMON_LIBS=m
#	    COMMON_MACROS="WIN32_LEAN_AND_MEAN="
	    COMMON_HEADERS="winsock2.h windows.h"
	    THREAD_MODEL=win32
	    PLATFORM_DIR=win32
	    ])
	LIBRUBY_ALIASES=''
	FIRSTMAKEFILE=GNUmakefile:cygwin/GNUmakefile.in
	AS_IF([test x"$enable_shared" = xyes], [
	    LIBRUBY='lib$(RUBY_SO_NAME).dll.a'
	], [
	    LIBRUBY_SO=dummy
	    LIBRUBY='lib$(RUBY_SO_NAME).a'
	    LIBRUBYARG='-l$(RUBY_SO_NAME)'
	])
	],
    [hpux*], [
	AS_CASE(["$YACC"],[*yacc*], [
	    XCFLAGS="$XCFLAGS -DYYMAXDEPTH=300"
	    YACC="$YACC -Nl40000 -Nm40000"
	])
])

MINIOBJS="$MINIDLNOBJ"

AS_CASE(["$THREAD_MODEL"],
[pthread], [AC_CHECK_HEADERS(pthread.h)],
[win32],   [],
[""],      [AC_MSG_ERROR(thread model is missing)],
           [AC_MSG_ERROR(unknown thread model $THREAD_MODEL)])

AC_ARG_ENABLE(debug-env,
       AS_HELP_STRING([--enable-debug-env], [enable RUBY_DEBUG environment variable]),
       [AC_SUBST(ENABLE_DEBUG_ENV, yes)])

AS_CASE(["$FIRSTMAKEFILE"], [*GNUmakefile:*], [gnumake=yes], [
    AC_MSG_CHECKING([if ${MAKE-make} is GNU make])
    mkdir conftest.dir
    echo "all:; @echo yes" > conftest.dir/GNUmakefile
    echo "all:; @echo no" > conftest.dir/Makefile
    gnumake=`(cd conftest.dir; ${MAKE-make})`
    rm -fr conftest.dir
    AS_CASE(["$gnumake"],
    [*yes*], [
	FIRSTMAKEFILE=GNUmakefile:template/GNUmakefile.in
	gnumake=yes],
    [
	gnumake=no])
    AC_MSG_RESULT($gnumake)
])
AS_IF([test "$gnumake" = yes], [ NULLCMD=: ], [
    AC_MSG_CHECKING([for safe null command for ${MAKE-make}])
    mkdir conftest.dir
    NULLCMD=
    for cmd in : true; do
	echo 'A=1' > conftest.dir/Makefile
	echo 'B=$(A:1=@'$cmd')' >> conftest.dir/Makefile
	echo 'all:; $B 1 2 3 4 5 6 7 8 9' >> conftest.dir/Makefile
	AS_IF([(cd conftest.dir; ${MAKE-make} >/dev/null 2>/dev/null)], [
	    NULLCMD=$cmd
	    break
	])
    done
    rm -fr conftest.dir
    AS_IF([test -z "$NULLCMD"], [
	AC_MSG_ERROR(no candidate for safe null command)
    ])
    AC_MSG_RESULT($NULLCMD)
])
AC_SUBST(NULLCMD)

AS_IF([test "${universal_binary-no}" = yes ], [
    AC_CACHE_CHECK([for architecture macros], rb_cv_architecture_macros, [
    mv confdefs.h confdefs1.h
    : > confdefs.h
    AC_TRY_COMPILE([@%:@if defined __`echo ${universal_archnames} |
    sed 's/=[^ ]*//g;s/ /__ || defined __/g'`__
@%:@else
@%:@error
>>>>>><<<<<<
@%:@endif], [],
[
    rb_cv_architecture_macros=yes
    mv -f confdefs1.h confdefs.h
], [
    rb_cv_architecture_macros=no
    archflagpat=`eval echo '"'"${ARCH_FLAG}"'"' | sed 's/[[][|.*]]/\\&/g'`
    new_cflags=`echo "$CFLAGS" | sed "s|$archflagpat"'||'`
    for archs in ${universal_archnames}; do
	cpu=${archs@%:@*=}
	archs=${archs%=*}
	CFLAGS="$new_cflags -arch $archs"
	archs="__${archs}__"
	AC_MSG_CHECKING([for macro ${archs} on ${cpu}])
	AC_TRY_COMPILE([@%:@ifndef ${archs}
@%:@error
@%:@endif], [], [AC_MSG_RESULT([yes])], [AC_MSG_RESULT([no])])
    done
    mv -f confdefs1.h confdefs.h
    AC_MSG_ERROR([failed])
    ])])
    AC_CACHE_CHECK(whether __ARCHITECTURE__ is available, rb_cv_architecture_available,
	AC_TRY_COMPILE([@%:@include <stdio.h>
		const char arch[[]] = __ARCHITECTURE__;], [puts(arch);],
		[rb_cv_architecture_available=yes], [rb_cv_architecture_available=no]))
])

: ${MJIT_LDSHARED=`echo "$LDSHARED" | sed ['s|\$(LD)|'"${LD}"'|g;s|\$(CC)|$(MJIT_CC)|g']`}

MAINLIBS="$LIBS"
LIBS=$ORIG_LIBS
AS_IF([test -n "${LIBS}"], [
    libspat=`echo "${LIBS}" | sed 's/[[][|.*$^]]/\\&/g;s/^  */ /;s/^  *$/ /'`
    MAINFLAGS=`echo " $MAINLIBS " | sed "s|$libspat"'||;s/^ *//;s/ *$//'`
])
LIBRUBYARG_STATIC="${LIBRUBYARG_STATIC} \$(MAINLIBS)"
CPPFLAGS="$CPPFLAGS "'$(DEFS)'
test -z "$CPPFLAGS" || CPPFLAGS="$CPPFLAGS "; CPPFLAGS="$CPPFLAGS"'${cppflags}'
AS_IF([test -n "${cflags+set}"], [
    cflagspat=`eval echo '"'"${cflags}"'"' | sed 's/[[][|.*]]/\\&/g;s/^  */ /;s/^  *$/ /'`
    CFLAGS=`echo " $CFLAGS " | sed "s|$cflagspat"'|${cflags}|;s/^ *//;s/ *$//'`
])
AS_IF([test -n "${cxxflags+set}"], [
    cxxflagspat=`eval echo '"'"${cxxflags}"'"' | sed 's/[[][|.*]]/\\&/g;s/^  */ /;s/^  *$/ /'`
    CXXFLAGS=`echo " $CXXFLAGS " | sed "s|$cxxflagspat"'|${cxxflags}|;s/^ *//;s/ *$//'`
])
AS_IF([test "${ARCH_FLAG}"], [
    archflagpat=`eval echo '"'"${ARCH_FLAG}"'"' | sed 's/[[][|.*]]/\\&/g'`
    CFLAGS=`echo "$CFLAGS" | sed "s| *$archflagpat"'||'`
    CXXFLAGS=`echo "$CXXFLAGS" | sed "s| *$archflagpat"'||'`
    LDFLAGS=`echo "$LDFLAGS" | sed "s| *$archflagpat"'||'`
])
rb_cv_warnflags=`echo "$rb_cv_warnflags" | sed 's/^ *//;s/ *$//'`
warnflags="$rb_cv_warnflags"
AC_SUBST(cppflags)dnl
AC_SUBST(cflags, ["${orig_cflags:+$orig_cflags }"'${optflags} ${debugflags} ${warnflags}'])dnl
AC_SUBST(cxxflags)dnl
AC_SUBST(optflags)dnl
AC_SUBST(debugflags)dnl
AC_SUBST(warnflags)dnl
AC_SUBST(strict_warnflags)dnl
AC_SUBST(XCFLAGS)dnl
AC_SUBST(XLDFLAGS)dnl
AC_SUBST(EXTLDFLAGS)dnl
AC_SUBST(EXTDLDFLAGS)dnl
AC_SUBST(LIBRUBY_LDSHARED)
AC_SUBST(LIBRUBY_DLDFLAGS)
AC_SUBST(RUBY_INSTALL_NAME)
AC_SUBST(rubyw_install_name)
AC_SUBST(RUBYW_INSTALL_NAME)
AC_SUBST(RUBY_SO_NAME)
AC_SUBST(LIBRUBY_A)
AC_SUBST(LIBRUBY_SO)
AC_SUBST(LIBRUBY_SONAME)
AC_SUBST(LIBRUBY_ALIASES)
AC_SUBST(LIBRUBY)
AC_SUBST(LIBRUBYARG)
AC_SUBST(LIBRUBYARG_STATIC)
AC_SUBST(LIBRUBYARG_SHARED)
AC_SUBST(SOLIBS)
AC_SUBST(DLDLIBS)
AC_SUBST(DLDSHARED)
AC_SUBST(ENABLE_SHARED)
AC_SUBST(MAINLIBS)
AC_SUBST(COMMON_LIBS)
AC_SUBST(COMMON_MACROS)
AC_SUBST(COMMON_HEADERS)
AC_SUBST(EXPORT_PREFIX)
AC_SUBST(SYMBOL_PREFIX)
AC_SUBST(MINIOBJS)
AC_SUBST(THREAD_MODEL)
AC_SUBST(PLATFORM_DIR)

firstmf=`echo $FIRSTMAKEFILE | sed 's/:.*//'`
firsttmpl=`echo $FIRSTMAKEFILE | sed 's/.*://'`
MAKEFILES="Makefile $firstmf"
MAKEFILES="`echo $MAKEFILES`"
AC_SUBST(MAKEFILES)

ri_prefix=
test "$program_prefix" != NONE &&
  ri_prefix=$program_prefix

ri_suffix=
test "$program_suffix" != NONE &&
  ri_suffix=$program_suffix

RUBY_INSTALL_NAME="${ri_prefix}"'$(RUBY_BASE_NAME)'"${ri_suffix}"
AS_CASE(["$target_os"],
  [cygwin*|mingw*], [
    RUBYW_INSTALL_NAME="${ri_prefix}"'$(RUBYW_BASE_NAME)'"${ri_suffix}"
    rubyw_install_name='$(RUBYW_INSTALL_NAME)'
    ])

rubylibdir='${rubylibprefix}/${ruby_version}'
rubyarchdir=${multiarch+'${rubyarchprefix}/${ruby_version}'}${multiarch-'${rubylibdir}/${arch}'}

rubyarchprefix=${multiarch+'${archlibdir}/${RUBY_BASE_NAME}'}${multiarch-'${rubylibprefix}/${arch}'}
AC_ARG_WITH(rubyarchprefix,
	    AS_HELP_STRING([--with-rubyarchprefix=DIR],
			   [prefix for architecture dependent ruby libraries [[RUBYLIBPREFIX/ARCH]]]),
	    [rubyarchprefix="$withval"])
AC_SUBST(rubyarchprefix)

rubysitearchprefix=${multiarch+'${sitearchlibdir}/${RUBY_BASE_NAME}'}${multiarch-'${rubylibprefix}/${sitearch}'}
AC_ARG_WITH(rubysitearchprefix,
	    AS_HELP_STRING([--with-rubysitearchprefix=DIR],
			   [prefix for architecture dependent site libraries [[RUBYLIBPREFIX/SITEARCH]]]),
	    [rubysitearchprefix="$withval"])
AC_SUBST(rubysitearchprefix)

RI_BASE_NAME=`echo ${RUBY_BASE_NAME} | sed 's/ruby/ri/'`
ridir='${datarootdir}/${RI_BASE_NAME}'
AC_ARG_WITH(ridir,
	    AS_HELP_STRING([--with-ridir=DIR], [ri documentation [[DATAROOTDIR/ri]]]),
	    [ridir=$withval])
AC_SUBST(ridir)
AC_SUBST(RI_BASE_NAME)

AC_ARG_WITH(ruby-version,
	    AS_HELP_STRING([--with-ruby-version=STR], [ruby version string for version specific directories [[full]] (full|minor|STR)]),
            [ruby_version=$withval],
            [ruby_version=full])
unset RUBY_LIB_VERSION
unset RUBY_LIB_VERSION_STYLE
AS_CASE(["$ruby_version"],
  [full],  [RUBY_LIB_VERSION_STYLE='3	/* full */'],
  [minor], [RUBY_LIB_VERSION_STYLE='2	/* minor */'])
AS_IF([test ${RUBY_LIB_VERSION_STYLE+set}], [
    {
    echo "#define RUBY_LIB_VERSION_STYLE $RUBY_LIB_VERSION_STYLE"
    echo '#define STRINGIZE(x) x'
    test -f revision.h -o -f "${srcdir}/revision.h" || echo '#define RUBY_REVISION 0'
    echo '#include "version.h"'
    echo 'ruby_version=RUBY_LIB_VERSION'
    } > conftest.c
    ruby_version="`$CPP -I. -I"${srcdir}" -I"${srcdir}/include" conftest.c | sed '/^ruby_version=/!d;s/ //g'`"
    eval $ruby_version
], [test -z "${ruby_version}"], [
    AC_MSG_ERROR([No ruby version, No place for bundled libraries])
], [
    RUBY_LIB_VERSION="${ruby_version}"
])
AC_SUBST(RUBY_LIB_VERSION_STYLE)
AC_SUBST(RUBY_LIB_VERSION)

AC_ARG_WITH(sitedir,
	    AS_HELP_STRING([--with-sitedir=DIR], [site libraries in DIR [[RUBY_LIB_PREFIX/site_ruby]], "no" to disable site directory]),
            [sitedir=$withval],
            [sitedir='${rubylibprefix}/site_ruby'])
sitelibdir='${sitedir}/${ruby_version}'

AC_ARG_WITH(sitearchdir,
	    AS_HELP_STRING([--with-sitearchdir=DIR],
			   [architecture dependent site libraries in DIR [[SITEDIR/SITEARCH]], "no" to disable site directory]),
            [sitearchdir=$withval],
            [sitearchdir=${multiarch+'${rubysitearchprefix}/site_ruby/${ruby_version}'}${multiarch-'${sitelibdir}/${sitearch}'}])

AC_ARG_WITH(vendordir,
	    AS_HELP_STRING([--with-vendordir=DIR], [vendor libraries in DIR [[RUBY_LIB_PREFIX/vendor_ruby]], "no" to disable vendor directory]),
            [vendordir=$withval],
            [vendordir='${rubylibprefix}/vendor_ruby'])
vendorlibdir='${vendordir}/${ruby_version}'

AC_ARG_WITH(vendorarchdir,
	    AS_HELP_STRING([--with-vendorarchdir=DIR],
			   [architecture dependent vendor libraries in DIR [[VENDORDIR/SITEARCH]], "no" to disable vendor directory]),
            [vendorarchdir=$withval],
            [vendorarchdir=${multiarch+'${rubysitearchprefix}/vendor_ruby/${ruby_version}'}${multiarch-'${vendorlibdir}/${sitearch}'}])

AS_IF([test "${LOAD_RELATIVE+set}"], [
    AC_DEFINE_UNQUOTED(LOAD_RELATIVE, $LOAD_RELATIVE)
    RUBY_EXEC_PREFIX=''
])

AC_SUBST(RUBY_EXEC_PREFIX)

AC_SUBST(libdirname, ${multiarch+arch}libdir)
AC_SUBST(archlibdir)dnl
AC_SUBST(sitearchlibdir)dnl
AC_SUBST(archincludedir)dnl
AC_SUBST(sitearchincludedir)dnl
AC_SUBST(arch)dnl
AC_SUBST(sitearch)dnl
AC_SUBST(ruby_version)dnl
AC_SUBST(rubylibdir)dnl
AC_SUBST(rubyarchdir)dnl
AC_SUBST(sitedir)dnl
AC_SUBST(sitelibdir)dnl
AC_SUBST(sitearchdir)dnl
AC_SUBST(vendordir)dnl
AC_SUBST(vendorlibdir)dnl
AC_SUBST(vendorarchdir)dnl

AC_SUBST(CONFIGURE, "`echo $0 | sed 's|.*/||'`")dnl
AC_SUBST(configure_args, "`echo "${ac_configure_args}" | sed 's/\\$/$$/g'`")dnl

AS_IF([test "${universal_binary-no}" = yes ], [
    arch="universal-${target_os}"
    AS_IF([test "${rb_cv_architecture_available}" = yes], [
	AC_DEFINE_UNQUOTED(RUBY_PLATFORM_CPU, __ARCHITECTURE__)
    ], [
	for archs in ${universal_archnames}; do
	    cpu=`echo $archs | sed 's/.*=//'`
	    archs=`echo $archs | sed 's/=.*//'`
	    RUBY_DEFINE_IF([defined __${archs}__ &&! defined RUBY_PLATFORM_CPU], RUBY_PLATFORM_CPU, ["${cpu}"])
	done
    ])
    ints='long int short'
    test "$ac_cv_type_long_long" = yes && ints="'long long' $ints"
    AC_SUBST(UNIVERSAL_ARCHNAMES, "${universal_archnames}")
    AC_SUBST(UNIVERSAL_INTS, "${ints}")
    AC_DEFINE_UNQUOTED(RUBY_PLATFORM_OS, "${target_os}")
    AC_DEFINE_UNQUOTED(RUBY_ARCH, "universal-" RUBY_PLATFORM_OS)
    AC_DEFINE_UNQUOTED(RUBY_PLATFORM, "universal." RUBY_PLATFORM_CPU "-" RUBY_PLATFORM_OS)
], [
    arch="${target_cpu}-${target_os}"
    AC_DEFINE_UNQUOTED(RUBY_PLATFORM, "$arch")
])

unset sitearch
AS_CASE(["$target_os"],[mingw*],[sitearch="$target_cpu-$rb_cv_msvcrt"])
: ${sitearch='${arch}'}

AC_ARG_WITH(search-path,
		AS_HELP_STRING([--with-search-path=DIR], [specify the additional search path]),
		[search_path=$withval])
AS_IF([test "$search_path" != ""], [
    AC_SUBST(RUBY_SEARCH_PATH, $search_path)
])

AC_ARG_WITH(rubyhdrdir,
	    AS_HELP_STRING([--with-rubyhdrdir=DIR], [core headers in DIR [[INCLUDEDIR/RUBY_BASE_NAME-RUBY_VERSION]]]),
	    [rubyhdrdir=$withval],
	    [rubyhdrdir='${includedir}/${RUBY_VERSION_NAME}'])

AC_ARG_WITH(rubyarchhdrdir,
	    AS_HELP_STRING([--with-rubyarchhdrdir=DIR],
			   [architecture dependent core headers in DIR [[$(rubyhdrdir)/$(arch)]]]),
	    [rubyarchhdrdir=$withval],
	    [rubyarchhdrdir=${multiarch+'${archincludedir}/${RUBY_VERSION_NAME}'}${multiarch-'${rubyhdrdir}/${arch}'}])

AC_ARG_WITH(sitehdrdir,
	    AS_HELP_STRING([--with-sitehdrdir=DIR], [core site headers in DIR [[RUBYHDRDIR/site_ruby]]]),
	    [sitehdrdir=$withval],
	    [sitehdrdir='${rubyhdrdir}/site_ruby'])

AC_ARG_WITH(sitearchhdrdir,
	    AS_HELP_STRING([--with-sitearchhdrdir=DIR],
			   [architecture dependent core site headers in DIR [[RUBYHDRDIR/site_ruby]]]),
	    [sitearchhdrdir=$withval],
	    [sitearchhdrdir=${multiarch+'${sitearchincludedir}/${RUBY_VERSION_NAME}/site_ruby'}${multiarch-'${sitehdrdir}/${sitearch}'}])

AC_ARG_WITH(vendorhdrdir,
	    AS_HELP_STRING([--with-vendorhdrdir=DIR], [core vendor headers in DIR [[RUBYHDRDIR/vendor_ruby]]]),
	    [vendorhdrdir=$withval],
	    [vendorhdrdir='${rubyhdrdir}/vendor_ruby'])

AC_ARG_WITH(vendorarchhdrdir,
	    AS_HELP_STRING([--with-vendorarchhdrdir=DIR],
			   [architecture dependent core vendor headers in DIR [[RUBYHDRDIR/vendor_ruby]]]),
	    [vendorarchhdrdir=$withval],
	    [vendorarchhdrdir=${multiarch+'${sitearchincludedir}/${RUBY_VERSION_NAME}/vendor_ruby'}${multiarch-'${vendorhdrdir}/${sitearch}'}])

AC_SUBST(rubyhdrdir)dnl
AC_SUBST(sitehdrdir)dnl
AC_SUBST(vendorhdrdir)dnl
AC_SUBST(rubyarchhdrdir)dnl
AC_SUBST(sitearchhdrdir)dnl
AC_SUBST(vendorarchhdrdir)dnl

AC_ARG_WITH(mantype,
	AS_HELP_STRING([--with-mantype=TYPE], [specify man page type; TYPE is one of man and doc]),
		[
			AS_CASE(["$withval"],
			[man|man.gz|man.bz2|doc|doc.gz|doc.bz2], [MANTYPE=$withval],
			[AC_MSG_ERROR(invalid man type: $withval)])
		])
AS_IF([test -z "$MANTYPE"], [
	dnl Looks for nroff with -mdoc support.
	AC_CACHE_VAL([ac_cv_path_NROFF], [
		AC_PATH_PROGS_FEATURE_CHECK([NROFF],
			[nroff awf mandoc],
			[$ac_path_NROFF -mdoc ${srcdir}/man/ruby.1 \
				>/dev/null 2>&1 &&
				ac_cv_path_NROFF=$ac_path_NROFF \
				ac_path_NROFF_found=:],
			[], ["/usr/bin:/usr/ucb"]
		)
	])
	AS_IF([test -n "$ac_cv_path_NROFF"], [
		MANTYPE=doc
	], [
		MANTYPE=man
	])
])
AC_SUBST(MANTYPE)

AC_ARG_ENABLE(rubygems,
	AS_HELP_STRING([--disable-rubygems], [disable rubygems by default]),
	[enable_rubygems="$enableval"], [enable_rubygems=yes])
AS_IF([test x"$enable_rubygems" = xno], [
    USE_RUBYGEMS=no
], [
    USE_RUBYGEMS=yes
])
AC_SUBST(USE_RUBYGEMS)

arch_hdrdir="${EXTOUT}/include/${arch}/ruby"
AS_MKDIR_P("${arch_hdrdir}")
config_h="${arch_hdrdir}/config.h"
guard=INCLUDE_RUBY_CONFIG_H
{
  echo "#ifndef $guard"
  echo "#define $guard 1"
  grep -v "^#define PACKAGE_" confdefs.h
  echo "#endif /* $guard */"
} | tr -d '\015' |
(
  AS_IF([test "x$CONFIGURE_TTY" = xyes], [color=--color], [color=])
  exec ${tooldir}/ifchange $color "${config_h}" -
) >&AS_MESSAGE_FD || AC_MSG_ERROR([failed to create ${config_h}])
tr -d '\015' < largefile.h > confdefs.h
rm largefile.h

BUILTIN_ENCS=["`sed -n -e '/^BUILTIN_ENCS[ 	]*=/{' \
	-e s/// -e :l -e '/\\\\$/N' -e 's/\\\\\\n/ /' -e 't l' -e p \
	-e '}' "${srcdir}/enc/Makefile.in"`"]
BUILTIN_ENCOBJS=
for e in $BUILTIN_ENCS; do BUILTIN_ENCOBJS="$BUILTIN_ENCOBJS "`echo $e | sed 's/\.c$/.$(OBJEXT)/'`; done
AC_SUBST(BUILTIN_ENCOBJS)

BUILTIN_TRANSES=["`sed -n -e '/^BUILTIN_TRANSES[ 	]*=/{' \
	-e s/// -e :l -e '/\\\\$/N' -e 's/\\\\\\n/ /' -e 't l' -e p \
	-e '}' "${srcdir}/enc/Makefile.in"`"]
BUILTIN_TRANSSRCS=
BUILTIN_TRANSOBJS=
for e in $BUILTIN_TRANSES; do
  BUILTIN_TRANSSRCS="$BUILTIN_TRANSSRCS "`echo $e | sed 's/\.trans$/.c/'`
  BUILTIN_TRANSOBJS="$BUILTIN_TRANSOBJS "`echo $e | sed 's/\.trans$/.$(OBJEXT)/'`
done
AC_SUBST(BUILTIN_TRANSSRCS)
AC_SUBST(BUILTIN_TRANSOBJS)

PACKAGE=$RUBY_BASE_NAME
AC_SUBST(PACKAGE)
AS_MESSAGE([$PACKAGE library version = $ruby_version])

AS_IF([test x"$CC_WRAPPER" != x], [
    CC='$(CC_WRAPPER) '"${CC@%:@$CC_WRAPPER }"
    CPP='$(CC_WRAPPER) '"${CPP@%:@$CC_WRAPPER }"
    CC_WRAPPER='$(rubyarchdir)/darwin-cc'
    XCC_WRAPPER='$(top_srcdir)/tool/darwin-cc'
])
AC_SUBST(CC_WRAPPER, '')
AC_SUBST(XCC_WRAPPER)

AS_CASE([" $CPP "], [*" $CC "*], [CPP=`echo " $CPP " | sed "s| $CC |"' $(CC) |;s/^ *//;s/  *$//'`])

AS_IF([test x"$firstmf" != x], [
    AC_CONFIG_FILES($firstmf:$firsttmpl, [], [firstmf="$firstmf" firsttmpl="$firsttmpl"])
])
AC_CONFIG_FILES(Makefile:template/Makefile.in, [
    tmpmk=confmk$$.tmp
    {
	AS_IF([test ${VCS+set}], [
	    :
	], [git_dir=`$GIT --work-tree="$srcdir" --git-dir="$srcdir/.git" rev-parse --git-dir 2>/dev/null`], [
	    VCS='$(GIT)'
	], [
	    VCS='echo cannot'
	])
	AS_CASE("$VCS",
		['$(GIT)'|git], [VCSUP='$(VCS) pull --rebase $(GITPULLOPTIONS)'],
		[VCSUP='$(VCS)'])
	sed -n \
	    -e '[/^@%:@define \(RUBY_RELEASE_[A-Z]*\) \([0-9][0-9]*\)/]{' \
	    -e   's//\1 = \2/' \
	    -e   '[s/ \([0-9]\)$/ 0\1/]' \
	    -e   p \
	    -e '}' "$srcdir/version.h"
	sed '/^MISSING/s/\$U\././g;/^VCS *=/s#@VCS@#'"$VCS"'#;/^VCSUP *=/s#@VCSUP@#'"$VCSUP"'#' Makefile
	echo; test x"$EXEEXT" = x || echo 'miniruby: miniruby$(EXEEXT)'
	AS_IF([test "$gnumake" != yes], [
	    echo ['$(MKFILES): $(srcdir)/common.mk']
	    sed ['s/{\$([^(){}]*)[^{}]*}//g'] ${srcdir}/common.mk
	], [
	    echo 'distclean-local::; @$(RM) GNUmakefile uncommon.mk'
	])
    } > $tmpmk && AS_IF([! grep '^ruby:' $tmpmk > /dev/null], [
	AS_IF([test "${gnumake}" = yes], [
	    tmpgmk=confgmk$$.tmp
	    {
		echo "include $tmpmk"
		echo "-include uncommon.mk"
	    } > $tmpgmk
	], [
	    tmpgmk=$tmpmk
	]) &&
	test -z "`${MAKE-make} -f $tmpgmk info-program | grep '^PROGRAM=ruby$'`" &&
	echo 'ruby: $(PROGRAM);' >> $tmpmk
	test "$tmpmk" = "$tmpgmk" || rm -f "$tmpgmk"
    ]) && mv -f $tmpmk Makefile],
[EXEEXT='$EXEEXT' MAKE='${MAKE-make}' gnumake='$gnumake' GIT='$GIT'])

AC_ARG_WITH([ruby-pc],
	    AC_HELP_STRING([--with-ruby-pc=FILENAME], [pc file basename]),
	    [ruby_pc="$withval"],
	    [ruby_pc="${RUBY_BASE_NAME}-${MAJOR}.${MINOR}.pc"])
AC_SUBST(ruby_pc)
AC_SUBST(exec, [exec])

AC_ARG_WITH(destdir,
	    AS_HELP_STRING([--with-destdir=DESTDIR], [specify default directory to install]),
	    [DESTDIR="$withval"])
AC_SUBST(DESTDIR)

AC_CONFIG_FILES($ruby_pc:template/ruby.pc.in,
    [
    AS_IF([sed ['s/\$(\([A-Za-z_][A-Za-z0-9_]*\))/${\1}/g;s/@[A-Za-z_][A-Za-z0-9_]*@//'] $ruby_pc > ruby.tmp.pc &&
	{
	    test -z "$PKG_CONFIG" ||
	    PKG_CONFIG_PATH=. $PKG_CONFIG --print-errors ruby.tmp
	}],
    [
	mv -f ruby.tmp.pc $ruby_pc
    ], [
	exit 1
    ])
    ],
    [ruby_pc='$ruby_pc' PKG_CONFIG='$PKG_CONFIG'])

AC_OUTPUT
}
}

AS_IF([test "$silent" = yes], [], [
AS_IF([${FOLD+:} false], [], [
AS_IF([test "`echo abcdefg hijklmno | fold -s -w10 | sed 1d`" = hijklmno], [FOLD="fold"], [FOLD=])
])
fold_width=`expr $COLUMNS - 30 2>/dev/null` || fold_width=50
AS_REQUIRE_SHELL_FN([config_summary],
    [AS_FUNCTION_DESCRIBE([config_summary], [NAME, VAL], [configuration summary])],
    [AS_IF([test -z "$2"], [], [
	AS_ECHO_N(["   * $1:                     "]) | dd bs=1 count=26 2>/dev/null
	AS_IF([test "$FOLD"], [
	    echo "$2" | fold -s -w$fold_width |
	    sed '1!s/^/                          /;$!s/$/\\/'
	], [echo "$2"])
    ])]
)

AS_IF([test $install_doc = yes],
    [DOCTARGETS=`echo " $RDOCTARGET $CAPITARGET " | sed 's/ nodoc //g;s/^ *//;s/ *$//'`],
    [DOCTARGETS=no])
echo "---"
echo "Configuration summary for $RUBY_BASE_NAME version $MAJOR.$MINOR.$TEENY"
echo ""
config_summary "Installation prefix" "$prefix"
config_summary "exec prefix"         "$exec_prefix"
config_summary "arch"                "$arch"
config_summary "site arch"           "$sitearch"
config_summary "RUBY_BASE_NAME"      "$RUBY_BASE_NAME"
config_summary "enable shared"       "$enable_shared"
config_summary "ruby lib prefix"     "$rubylibprefix"
config_summary "site libraries path" "$rubysitearchprefix"
config_summary "vendor path"         "$vendordir"
config_summary "target OS"           "$target_os"
config_summary "compiler"            "$CC"
config_summary "with pthread"        "$enable_pthread"
config_summary "with coroutine"      "$rb_cv_coroutine"
config_summary "enable shared libs"  "$ENABLE_SHARED"
config_summary "dynamic library ext" "$DLEXT"
config_summary "CFLAGS"              "$cflags"
config_summary "CPPFLAGS"            "$cppflags"
config_summary "LDFLAGS"             "$LDFLAGS"
config_summary "DLDFLAGS"            "$DLDFLAGS"
config_summary "optflags"            "$optflags"
config_summary "debugflags"          "$debugflags"
config_summary "warnflags"           "$warnflags"
config_summary "strip command"       "$STRIP"
config_summary "install doc"         "$DOCTARGETS"
config_summary "JIT support"         "$MJIT_SUPPORT"
config_summary "man page type"       "$MANTYPE"
config_summary "search path"         "$search_path"
config_summary "static-linked-ext"   ${EXTSTATIC:+"yes"}
config_summary "BASERUBY -v"         "$BASERUBY_VERSION"
echo ""
echo "---"
])
