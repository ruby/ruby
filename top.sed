s/@srcdir@/./
s/@CC@/gcc/
s/@CPP@/gcc -E/
s/@CPPFLAGS@//
s/@YACC@/bison -y/
s/@INSTALL@/ginstall -c/
s/@INSTALL_PROGRAM@/${INSTALL}/
s/@INSTALL_DATA@/${INSTALL} -m 644/
s/@SET_MAKE@//
s/@CFLAGS@/-g -O -I./
s/@STATIC@//
s/@LDFLAGS@//
s/@LIBS@//
s/@LIBOBJS@/crypt.o/
s/@ALLOCA@//
s!@prefix@!/usr/local!
s/@exec_prefix@/${prefix}/
s/@STRIP@/strip/
s!/bin/rm!rm!
s/@LDEXT@/so/
s/@CCDLFLAGS@/-fpic/
s!@arclib@!/usr/local/lib/ruby/i386-msdos!
/\/dev\/null/s,/dev/null 2>&1, nul,
/if older/s/"ruby"/"ruby.exe"/g
/`rm -f ruby`/s//`rm -f ruby.exe`/
/`cp miniruby ruby`/s//`cp miniruby.exe ruby.exe`/
/^extruby:/ {
    n;N;N;N;c\
		cd ext\
		../miniruby ./extmk.rb\
		cd ..
}
/^clean:;/ {
    n;n;s!cd.*!cd ext\
		../miniruby ./extmk.rb clean\
		cd ..!
}
