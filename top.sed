/^SHELL/s,/bin/sh,$(COMPSEC),
s/@srcdir@/./g
s/@top_srcdir@/../
s/@CC@/gcc/
s/@CPP@/gcc -E/
s/@CPPFLAGS@//
s/@AR@/ar/
s/@RANLIB@/ranlib/
s/@YACC@/bison -y/
s/@INSTALL@/ginstall -c/
s/@INSTALL_PROGRAM@/${INSTALL}/
s/@INSTALL_DATA@/${INSTALL} -m 644/
s/@SET_MAKE@//
s/@CFLAGS@/-g -O2 -I./
s/@STATIC@//
s/@LDFLAGS@//
s/@LIBS@//
s/@LIBOBJS@/crypt.o flock.o/
s/@ALLOCA@//
s!@prefix@!/usr/local!
s/@exec_prefix@/${prefix}/
s!@bindir@!${exec_prefix}/bin!
s!@libdir@!${exec_prefix}/lib!
s/@STRIP@/strip/
s!/bin/rm!rm!
s/@DLEXT@/o/
s/@CCDLFLAGS@/-fpic/
s/@DLDFLAGS@//
s/@LDSHARED@//
s/@binsuffix@/.exe/g
s/@setup@/Setup/g
s/|| true//
s!@archlib@!/usr/local/lib/ruby/i386-djgpp!
/\/dev\/null/ {
s,/dev/null 2>&1, nul,
s,2> /dev/null,,
}
s/y\.tab\.c/y_tab.c/
#/if older/s/"ruby"/"ruby.exe"/g
#/`rm -f ruby`/s//`rm -f ruby.exe`/
#/`cp miniruby ruby`/s//`cp miniruby.exe ruby.exe`/
/^all:.*miniruby/ {
    n;c\
		cd ext\
		../miniruby ./extmk.rb\
		cd ..
}
/^clean:;/ {
    n;n;s!cd.*!cd ext\
		../miniruby ./extmk.rb clean\
		cd ..!
}
