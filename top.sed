/^SHELL/s,/bin/sh,$(COMPSEC),
s/@srcdir@/./g
s/@top_srcdir@/../
s%@CFLAGS@%-g -O2%g
s%@CPPFLAGS@%%g
s%@LDFLAGS@%%g
s%@LIBS@%-lm %g
s%@exec_prefix@%${prefix}%g
s%@prefix@%/usr/local%g
s%@program_transform_name@%s,x,x,%g
s%@bindir@%${exec_prefix}/bin%g
s%@sbindir@%${exec_prefix}/sbin%g
s%@libexecdir@%${exec_prefix}/libexec%g
s%@datadir@%${prefix}/share%g
s%@sysconfdir@%${prefix}/etc%g
s%@sharedstatedir@%${prefix}/com%g
s%@localstatedir@%${prefix}/var%g
s%@libdir@%${exec_prefix}/lib%g
s%@includedir@%${prefix}/include%g
s%@oldincludedir@%/usr/include%g
s%@infodir@%${prefix}/info%g
s%@mandir@%${prefix}/man%g
s%@host@%i386-pc-djgpp%g
s%@host_alias@%i386-djgpp%g
s%@host_cpu@%i386%g
s%@host_vendor@%pc%g
s%@host_os@%djgpp%g
s%@CC@%gcc%g
s%@CPP@%gcc -E%g
s%@YACC@%bison -y%g
s%@RANLIB@%ranlib%g
s%@AR@%ar%g
s%@INSTALL_PROGRAM@%${INSTALL}%g
s%@INSTALL_DATA@%${INSTALL} -m 644%g
s%@SET_MAKE@%%g
s%@LIBOBJS@% crypt.o flock.o vsnprintf.o%g
s%@ALLOCA@%%g
s%@DLDFLAGS@%%g
s%@STATIC@%%g
s%@CCDLFLAGS@%%g
s%@LDSHARED@%ld%g
s%@DLEXT@%o%g
s%@STRIP@%strip%g
s%@EXTSTATIC@%%g
s%@binsuffix@%.exe%g
s%@setup@%Setup.dj%g
s%@LIBRUBY@%libruby.a%g
s%@LIBRUBYARG@%libruby.a%g
s%@SOLIBS@%%g
s%@arch@%i386-djgpp%g
s%/bin/rm%rm%
s%|| true%%
s%@archlib@%/usr/local/lib/ruby/i386-djgpp%
/\/dev\/null/ {
s,/dev/null 2>&1, nul,
s,2> /dev/null,,
}
/^config.status/ {
    N;N;N;N;N;d
}
s%y\.tab\.c%y_tab.c%
