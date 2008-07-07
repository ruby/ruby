/^SHELL/s,/bin/sh,$(COMSPEC),
;s%/bin/rm%rm%
;s%|| true%%
;/\/dev\/null/ {
;s,/dev/null 2>&1, nul,
;s,2> /dev/null,,
;}
;/^config.status/ {
;    N;N;N;N;N;d
;}
:t
  /@[a-zA-Z_][a-zA-Z_0-9]*@/!b
s,@srcdir@,.,g;t t
s,@top_srcdir@,..,;t t
s,@PATH_SEPARATOR@,:,;t t
s,@PACKAGE_NAME@,,;t t
s,@PACKAGE_TARNAME@,,;t t
s,@PACKAGE_VERSION@,,;t t
s,@PACKAGE_STRING@,,;t t
s,@PACKAGE_BUGREPORT@,,;t t
s,@exec_prefix@,${prefix},;t t
s,@prefix@,/dev/env/DJDIR,;t t
s%@program_transform_name@%s,^,,%;t t
s,@bindir@,${exec_prefix}/bin,;t t
s,@sbindir@,${exec_prefix}/sbin,;t t
s,@libexecdir@,${exec_prefix}/libexec,;t t
s,@datadir@,${prefix}/share,;t t
s,@sysconfdir@,${prefix}/etc,;t t
s,@sharedstatedir@,${prefix}/com,;t t
s,@localstatedir@,${prefix}/var,;t t
s,@libdir@,${exec_prefix}/lib,;t t
s,@includedir@,${prefix}/include,;t t
s,@oldincludedir@,/usr/include,;t t
s,@infodir@,${prefix}/info,;t t
s,@mandir@,${prefix}/man,;t t
s,@build_alias@,i586-pc-msdosdjgpp,;t t
s,@host_alias@,i586-pc-msdosdjgpp,;t t
s,@target_alias@,i386-msdosdjgpp,;t t
s,@DEFS@,,;t t
s,@ECHO_C@,,;t t
s,@ECHO_N@,-n,;t t
s,@ECHO_T@,,;t t
s,@LIBS@,-lm ,;t t
s,@MAJOR@,1,;t t
s,@MINOR@,7,;t t
s,@TEENY@,3,;t t
s,@build@,i586-pc-msdosdjgpp,;t t
s,@build_cpu@,i586,;t t
s,@build_vendor@,pc,;t t
s,@build_os@,msdosdjgpp,;t t
s,@host@,i586-pc-msdosdjgpp,;t t
s,@host_cpu@,i586,;t t
s,@host_vendor@,pc,;t t
s,@host_os@,msdosdjgpp,;t t
s,@target@,i386-pc-msdosdjgpp,;t t
s,@target_cpu@,i386,;t t
s,@target_vendor@,pc,;t t
s,@target_os@,msdosdjgpp,;t t
s,@CC@,gcc,;t t
s,@ac_ct_CC@,,;t t
s,@CFLAGS@,-Os,;t t
s,@LDFLAGS@,,;t t
s,@CPPFLAGS@,,;t t
s,@EXEEXT@,.exe,;t t
s,@OBJEXT@,o,;t t
s,@CPP@,gcc -E,;t t
s,@EGREP@,grep -E,;t t
s,@GNU_LD@,yes,;t t
s,@CPPOUTFILE@,-o conftest.i,;t t
s,@OUTFLAG@,-o ,;t t
s,@YACC@,bison -y,;t t
s,@RANLIB@,ranlib,;t t
s,@ac_ct_RANLIB@,,;t t
s,@AR@,ar,;t t
s,@ac_ct_AR@,,;t t
s,@NM@,,;t t
s,@ac_ct_NM@,,;t t
s,@WINDRES@,,;t t
s,@ac_ct_WINDRES@,,;t t
s,@DLLWRAP@,,;t t
s,@ac_ct_DLLWRAP@,,;t t
s,@LN_S@,ln -s,;t t
s,@SET_MAKE@,,;t t
s,@LIBOBJS@,crypt.o flock.o vsnprintf.o,;t t
s,@ALLOCA@,,;t t
s,@XCFLAGS@,,;t t
s,@XLDFLAGS@, -L.,;t t
s,@DLDFLAGS@,,;t t
s,@STATIC@,,;t t
s,@CCDLFLAGS@,,;t t
s,@LDSHARED@,ld,;t t
s,@DLEXT@,so,;t t
s,@DLEXT2@,,;t t
s,@LIBEXT@,a,;t t
s,@LINK_SO@,,;t t
s,@LIBPATHFLAG@, -L%s,;t t
s,@STRIP@,strip,;t t
s,@EXTSTATIC@,,;t t
s,@setup@,Setup.dj,;t t
s,@MINIRUBY@,./miniruby,;t t
s,@PREP@,,;t t
s,@ARCHFILE@,,;t t
s,@LIBRUBY_LDSHARED@,ld,;t t
s,@LIBRUBY_DLDFLAGS@,,;t t
s,@RUBY_INSTALL_NAME@,ruby,;t t
s,@rubyw_install_name@,,;t t
s,@RUBYW_INSTALL_NAME@,,;t t
s,@RUBY_SO_NAME@,$(RUBY_INSTALL_NAME),;t t
s,@LIBRUBY_A@,lib$(RUBY_INSTALL_NAME).a,;t t
s,@LIBRUBY_SO@,lib$(RUBY_SO_NAME).so.$(MAJOR).$(MINOR).$(TEENY),;t t
s,@LIBRUBY_ALIASES@,lib$(RUBY_SO_NAME).so,;t t
s,@LIBRUBY@,$(LIBRUBY_A),;t t
s,@LIBRUBYARG@,-l$(RUBY_INSTALL_NAME),;t t
s,@SOLIBS@,,;t t
s,@DLDLIBS@,-lc,;t t
s,@ENABLE_SHARED@,no,;t t
s,@MAINLIBS@,,;t t
s,@COMMON_LIBS@,,;t t
s,@COMMON_MACROS@,,;t t
s,@COMMON_HEADERS@,,;t t
s,@EXPORT_PREFIX@,,;t t
s,@MAKEFILES@,Makefile,;t t
s,@arch@,i386-msdosdjgpp,;t t
s,@sitearch@,i386-msdosdjgpp,;t t
s,@sitedir@,${prefix}/lib/ruby/site_ruby,;t t
s,@configure_args@,,;t t
/^,THIS_IS_DUMMY_PATTERN_/i\
ac_given_srcdir=.
