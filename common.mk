bin: $(PROGRAM) $(WPROGRAM)
lib: $(LIBRUBY)
dll: $(LIBRUBY_SO)

.SUFFIXES: .inc

RUBYLIB       = -
RUBYOPT       = -

SPEC_GIT_BASE = git://github.com/rubyspec
MSPEC_GIT_URL = $(SPEC_GIT_BASE)/mspec.git
RUBYSPEC_GIT_URL = $(SPEC_GIT_BASE)/rubyspec.git

STATIC_RUBY   = static-ruby

EXTCONF       = extconf.rb
RBCONFIG      = ./.rbconfig.time
LIBRUBY_EXTS  = ./.libruby-with-ext.time
RDOCOUT       = $(EXTOUT)/rdoc

DMYEXT	      = dmyext.$(OBJEXT)
NORMALMAINOBJ = main.$(OBJEXT)
MAINOBJ       = $(NORMALMAINOBJ)
EXTOBJS	      = 
DLDOBJS	      = $(DMYEXT)
MINIOBJS      = $(ARCHMINIOBJS) dmyencoding.$(OBJEXT) miniprelude.$(OBJEXT)

COMMONOBJS    = array.$(OBJEXT) \
		bignum.$(OBJEXT) \
		class.$(OBJEXT) \
		compar.$(OBJEXT) \
		complex.$(OBJEXT) \
		dir.$(OBJEXT) \
		enum.$(OBJEXT) \
		enumerator.$(OBJEXT) \
		error.$(OBJEXT) \
		eval.$(OBJEXT) \
		load.$(OBJEXT) \
		proc.$(OBJEXT) \
		file.$(OBJEXT) \
		gc.$(OBJEXT) \
		hash.$(OBJEXT) \
		inits.$(OBJEXT) \
		io.$(OBJEXT) \
		marshal.$(OBJEXT) \
		math.$(OBJEXT) \
		numeric.$(OBJEXT) \
		object.$(OBJEXT) \
		pack.$(OBJEXT) \
		parse.$(OBJEXT) \
		process.$(OBJEXT) \
		prec.$(OBJEXT) \
		random.$(OBJEXT) \
		range.$(OBJEXT) \
		rational.$(OBJEXT) \
		re.$(OBJEXT) \
		regcomp.$(OBJEXT) \
		regenc.$(OBJEXT) \
		regerror.$(OBJEXT) \
		regexec.$(OBJEXT) \
		regparse.$(OBJEXT) \
		regsyntax.$(OBJEXT) \
		ruby.$(OBJEXT) \
		signal.$(OBJEXT) \
		sprintf.$(OBJEXT) \
		st.$(OBJEXT) \
		string.$(OBJEXT) \
		struct.$(OBJEXT) \
		time.$(OBJEXT) \
		transcode.$(OBJEXT) \
		util.$(OBJEXT) \
		variable.$(OBJEXT) \
		version.$(OBJEXT) \
		blockinlining.$(OBJEXT) \
		compile.$(OBJEXT) \
		debug.$(OBJEXT) \
		iseq.$(OBJEXT) \
		vm.$(OBJEXT) \
		vm_dump.$(OBJEXT) \
		thread.$(OBJEXT) \
		cont.$(OBJEXT) \
		id.$(OBJEXT) \
		$(BUILTIN_ENCOBJS) \
		$(MISSING)

OBJS          = dln.$(OBJEXT) \
		encoding.$(OBJEXT) \
		prelude.$(OBJEXT) \
		$(COMMONOBJS)

GOLFOBJS      = goruby.$(OBJEXT) golf_prelude.$(OBJEXT)

PRELUDE_SCRIPTS = $(srcdir)/prelude.rb $(srcdir)/enc/prelude.rb $(srcdir)/gem_prelude.rb
PRELUDES      = prelude.c miniprelude.c golf_prelude.c

SCRIPT_ARGS   =	--dest-dir="$(DESTDIR)" \
		--extout="$(EXTOUT)" \
		--mflags="$(MFLAGS)" \
		--make-flags="$(MAKEFLAGS)"
EXTMK_ARGS    =	$(SCRIPT_ARGS) --extension $(EXTS) --extstatic $(EXTSTATIC) --
INSTRUBY_ARGS =	$(SCRIPT_ARGS) \
		--data-mode=$(INSTALL_DATA_MODE) \
		--prog-mode=$(INSTALL_PROG_MODE) \
		--installed-list $(INSTALLED_LIST)
INSTALL_PROG_MODE = 0755
INSTALL_DATA_MODE = 0644

PRE_LIBRUBY_UPDATE = $(MINIRUBY) -e 'ARGV[1] or File.unlink(ARGV[0]) rescue nil' -- \
			$(LIBRUBY_EXTS) $(LIBRUBY_SO_UPDATE)

TESTSDIR      = $(srcdir)/test
TESTWORKDIR   = testwork

BOOTSTRAPRUBY = $(BASERUBY)

COMPILE_PRELUDE = $(MINIRUBY) -I$(srcdir) -rrbconfig $(srcdir)/tool/compile_prelude.rb

VCS           = svn

all: $(MKFILES) incs $(PREP) $(RBCONFIG) $(LIBRUBY) encs
	@$(MINIRUBY) $(srcdir)/ext/extmk.rb --make="$(MAKE)" $(EXTMK_ARGS)
prog: $(PROGRAM) $(WPROGRAM)

loadpath: $(PREP)
	$(MINIRUBY) -e 'p $$:'

$(PREP): $(MKFILES)

miniruby$(EXEEXT): config.status $(NORMALMAINOBJ) $(MINIOBJS) $(COMMONOBJS) $(DMYEXT) $(ARCHFILE)

GORUBY = go$(RUBY_INSTALL_NAME)
golf: $(LIBRUBY) $(GOLFOBJS)
	$(MAKE) $(MFLAGS) MAINOBJ="$(GOLFOBJS)" PROGRAM=$(GORUBY)$(EXEEXT) program

program: $(PROGRAM)

$(PROGRAM): $(LIBRUBY) $(MAINOBJ) $(OBJS) $(EXTOBJS) $(SETUP) $(PREP)

$(LIBRUBY_A):	$(OBJS) $(DMYEXT) $(ARCHFILE)

$(LIBRUBY_SO):	$(OBJS) $(DLDOBJS) $(LIBRUBY_A) $(PREP) $(LIBRUBY_SO_UPDATE) $(BUILTIN_ENCOBJS)

$(LIBRUBY_EXTS):
	@exit > $@

$(STATIC_RUBY)$(EXEEXT): $(MAINOBJ) $(DLDOBJS) $(EXTOBJS) $(LIBRUBY_A)
	@$(RM) $@
	$(PURIFY) $(CC) $(MAINOBJ) $(DLDOBJS) $(EXTOBJS) $(LIBRUBY_A) $(MAINLIBS) $(EXTLIBS) $(LIBS) $(OUTFLAG)$@ $(LDFLAGS) $(XLDFLAGS)

ruby.imp: $(COMMONOBJS)
	@$(NM) -Pgp $(COMMONOBJS) | awk 'BEGIN{print "#!"}; $$2~/^[BD]$$/{print $$1}' | sort -u -o $@

install: install-nodoc $(RDOCTARGET)
install-all: install-nodoc install-doc

install-nodoc: pre-install-nodoc do-install-nodoc post-install-nodoc
pre-install-nodoc:: pre-install-local pre-install-ext
do-install-nodoc: $(PREP)
	$(MINIRUBY) $(srcdir)/instruby.rb --make="$(MAKE)" $(INSTRUBY_ARGS) --mantype="$(MANTYPE)"
post-install-nodoc:: post-install-local post-install-ext

install-local: pre-install-local do-install-local post-install-local
pre-install-local:: pre-install-bin pre-install-lib pre-install-man
do-install-local: $(PREP)
	$(MINIRUBY) $(srcdir)/instruby.rb --make="$(MAKE)" $(INSTRUBY_ARGS) --install=local --mantype="$(MANTYPE)"
post-install-local:: post-install-bin post-install-lib post-install-man

install-ext: pre-install-ext do-install-ext post-install-ext
pre-install-ext:: pre-install-ext-arch pre-install-ext-comm
do-install-ext: $(PREP)
	$(MINIRUBY) $(srcdir)/instruby.rb --make="$(MAKE)" $(INSTRUBY_ARGS) --install=ext
post-install-ext:: post-install-ext-arch post-install-ext-comm

install-arch: pre-install-arch do-install-arch post-install-arch
pre-install-arch:: pre-install-bin pre-install-ext-arch
do-install-arch: $(PREP)
	$(MINIRUBY) $(srcdir)/instruby.rb --make="$(MAKE)" $(INSTRUBY_ARGS) --install=bin --install=ext-arch
post-install-arch:: post-install-bin post-install-ext-arch

install-comm: pre-install-comm do-install-comm post-install-comm
pre-install-comm:: pre-install-lib pre-install-ext-comm pre-install-man
do-install-comm: $(PREP)
	$(MINIRUBY) $(srcdir)/instruby.rb --make="$(MAKE)" $(INSTRUBY_ARGS) --install=lib --install=ext-comm --install=man
post-install-comm:: post-install-lib post-install-ext-comm post-install-man

install-bin: pre-install-bin do-install-bin post-install-bin
pre-install-bin:: install-prereq
do-install-bin: $(PREP)
	$(MINIRUBY) $(srcdir)/instruby.rb --make="$(MAKE)" $(INSTRUBY_ARGS) --install=bin
post-install-bin::
	@$(NULLCMD)

install-lib: pre-install-lib do-install-lib post-install-lib
pre-install-lib:: install-prereq
do-install-lib: $(PREP)
	$(MINIRUBY) $(srcdir)/instruby.rb --make="$(MAKE)" $(INSTRUBY_ARGS) --install=lib
post-install-lib::
	@$(NULLCMD)

install-ext-comm: pre-install-ext-comm do-install-ext-comm post-install-ext-comm
pre-install-ext-comm:: install-prereq
do-install-ext-comm: $(PREP)
	$(MINIRUBY) $(srcdir)/instruby.rb --make="$(MAKE)" $(INSTRUBY_ARGS) --install=ext-comm
post-install-ext-comm::
	@$(NULLCMD)

install-ext-arch: pre-install-ext-arch do-install-ext-arch post-install-ext-arch
pre-install-ext-arch:: install-prereq
do-install-ext-arch: $(PREP)
	$(MINIRUBY) $(srcdir)/instruby.rb --make="$(MAKE)" $(INSTRUBY_ARGS) --install=ext-arch
post-install-ext-arch::
	@$(NULLCMD)

install-man: pre-install-man do-install-man post-install-man
pre-install-man:: install-prereq
do-install-man: $(PREP)
	$(MINIRUBY) $(srcdir)/instruby.rb --make="$(MAKE)" $(INSTRUBY_ARGS) --install=man --mantype="$(MANTYPE)"
post-install-man::
	@$(NULLCMD)

what-where: no-install
no-install: no-install-nodoc no-install-doc
what-where-all: no-install-all
no-install-all: no-install-nodoc

what-where-nodoc: no-install-nodoc
no-install-nodoc: pre-no-install-nodoc dont-install-nodoc post-no-install-nodoc
pre-no-install-nodoc:: pre-no-install-local pre-no-install-ext
dont-install-nodoc:  $(PREP)
	$(MINIRUBY) $(srcdir)/instruby.rb -n --make="$(MAKE)" $(INSTRUBY_ARGS) --mantype="$(MANTYPE)"
post-no-install-nodoc:: post-no-install-local post-no-install-ext

what-where-local: no-install-local
no-install-local: pre-no-install-local dont-install-local post-no-install-local
pre-no-install-local:: pre-no-install-bin pre-no-install-lib pre-no-install-man
dont-install-local: $(PREP)
	$(MINIRUBY) $(srcdir)/instruby.rb -n --make="$(MAKE)" $(INSTRUBY_ARGS) --install=local --mantype="$(MANTYPE)"
post-no-install-local:: post-no-install-bin post-no-install-lib post-no-install-man

what-where-ext: no-install-ext
no-install-ext: pre-no-install-ext dont-install-ext post-no-install-ext
pre-no-install-ext:: pre-no-install-ext-arch pre-no-install-ext-comm
dont-install-ext: $(PREP)
	$(MINIRUBY) $(srcdir)/instruby.rb -n --make="$(MAKE)" $(INSTRUBY_ARGS) --install=ext
post-no-install-ext:: post-no-install-ext-arch post-no-install-ext-comm

what-where-arch: no-install-arch
no-install-arch: pre-no-install-arch dont-install-arch post-no-install-arch
pre-no-install-arch:: pre-no-install-bin pre-no-install-ext-arch
dont-install-arch: $(PREP)
	$(MINIRUBY) $(srcdir)/instruby.rb -n --make="$(MAKE)" $(INSTRUBY_ARGS) --install=bin --install=ext-arch
post-no-install-arch:: post-no-install-lib post-no-install-man post-no-install-ext-arch

what-where-comm: no-install-comm
no-install-comm: pre-no-install-comm dont-install-comm post-no-install-comm
pre-no-install-comm:: pre-no-install-lib pre-no-install-ext-comm pre-no-install-man
dont-install-comm: $(PREP)
	$(MINIRUBY) $(srcdir)/instruby.rb -n --make="$(MAKE)" $(INSTRUBY_ARGS) --install=lib --install=ext-comm --install=man
post-no-install-comm:: post-no-install-lib post-no-install-ext-comm post-no-install-man

what-where-bin: no-install-bin
no-install-bin: pre-no-install-bin dont-install-bin post-no-install-bin
pre-no-install-bin:: install-prereq
dont-install-bin: $(PREP)
	$(MINIRUBY) $(srcdir)/instruby.rb -n --make="$(MAKE)" $(INSTRUBY_ARGS) --install=bin
post-no-install-bin::
	@$(NULLCMD)

what-where-lib: no-install-lib
no-install-lib: pre-no-install-lib dont-install-lib post-no-install-lib
pre-no-install-lib:: install-prereq
dont-install-lib: $(PREP)
	$(MINIRUBY) $(srcdir)/instruby.rb -n --make="$(MAKE)" $(INSTRUBY_ARGS) --install=lib
post-no-install-lib::
	@$(NULLCMD)

what-where-ext-comm: no-install-ext-comm
no-install-ext-comm: pre-no-install-ext-comm dont-install-ext-comm post-no-install-ext-comm
pre-no-install-ext-comm:: install-prereq
dont-install-ext-comm: $(PREP)
	$(MINIRUBY) $(srcdir)/instruby.rb -n --make="$(MAKE)" $(INSTRUBY_ARGS) --install=ext-comm
post-no-install-ext-comm::
	@$(NULLCMD)

what-where-ext-arch: no-install-ext-arch
no-install-ext-arch: pre-no-install-ext-arch dont-install-ext-arch post-no-install-ext-arch
pre-no-install-ext-arch:: install-prereq
dont-install-ext-arch: $(PREP)
	$(MINIRUBY) $(srcdir)/instruby.rb -n --make="$(MAKE)" $(INSTRUBY_ARGS) --install=ext-arch
post-no-install-ext-arch::
	@$(NULLCMD)

what-where-man: no-install-man
no-install-man: pre-no-install-man dont-install-man post-no-install-man
pre-no-install-man:: install-prereq
dont-install-man: $(PREP)
	$(MINIRUBY) $(srcdir)/instruby.rb -n --make="$(MAKE)" $(INSTRUBY_ARGS) --install=man --mantype="$(MANTYPE)"
post-no-install-man::
	@$(NULLCMD)

install-doc: rdoc pre-install-doc do-install-doc post-install-doc
pre-install-doc:: install-prereq
do-install-doc: $(PROGRAM)
	$(MINIRUBY) $(srcdir)/instruby.rb --make="$(MAKE)" $(INSTRUBY_ARGS) --install=rdoc --rdoc-output="$(RDOCOUT)"
post-install-doc::
	@$(NULLCMD)

rdoc: $(PROGRAM) PHONY
	@echo Generating RDoc documentation
	$(RUNRUBY) "$(srcdir)/bin/rdoc" --all --ri --op "$(RDOCOUT)" "$(srcdir)"

what-where-doc: no-install-doc
no-install-doc: pre-no-install-doc dont-install-doc post-no-install-doc
pre-no-install-doc:: install-prereq
dont-install-doc:: $(PREP)
	$(MINIRUBY) $(srcdir)/instruby.rb -n --make="$(MAKE)" $(INSTRUBY_ARGS) --install=rdoc --rdoc-output="$(RDOCOUT)"
post-no-install-doc::
	@$(NULLCMD)

CLEAR_INSTALLED_LIST = clear-installed-list

install-prereq: $(CLEAR_INSTALLED_LIST)

clear-installed-list:
	@exit > $(INSTALLED_LIST)

clean: clean-ext clean-local clean-enc
clean-local::
	@$(RM) $(OBJS) $(MINIOBJS) $(MAINOBJ) $(LIBRUBY_A) $(LIBRUBY_SO) $(LIBRUBY) $(LIBRUBY_ALIASES)
	@$(RM) $(PROGRAM) $(WPROGRAM) miniruby$(EXEEXT) dmyext.$(OBJEXT) $(ARCHFILE) .*.time
	@$(RM) *.inc $(GOLFOBJS) y.tab.c y.output encdb.h transdb.h
clean-ext::
clean-enc:
	@-$(MAKE) -f enc.mk $(MFLAGS) clean

distclean: distclean-ext distclean-local distclean-enc
distclean-local:: clean-local
	@$(RM) $(MKFILES) $(arch_hdrdir)/ruby/config.h rbconfig.rb yasmdata.rb encdb.h
	@$(RM) config.cache config.log config.status config.status.lineno $(PRELUDES)
	@$(RM) *~ *.bak *.stackdump core *.core gmon.out $(PREP)
distclean-ext::
distclean-enc: clean-enc
	@-$(MAKE) -f enc.mk $(MFLAGS) distclean

realclean:: realclean-ext realclean-local realclean-enc
realclean-local:: distclean-local
	@$(RM) parse.c parse.h lex.c revision.h
realclean-ext::
realclean-enc:: distclean-enc

check: test test-all

btest: miniruby$(EXEEXT) PHONY
	$(BOOTSTRAPRUBY) "$(srcdir)/bootstraptest/runner.rb" --ruby="$(MINIRUBY)" $(OPTS)

btest-miniruby: miniruby$(EXEEXT) $(RBCONFIG) $(PROGRAM) PHONY
	@$(MINIRUBY) "$(srcdir)/bootstraptest/runner.rb" --ruby="$(MINIRUBY)" -q

test-sample: miniruby$(EXEEXT) $(RBCONFIG) $(PROGRAM) PHONY
	@$(MINIRUBY) $(srcdir)/rubytest.rb

test-knownbug: miniruby$(EXEEXT) $(PROGRAM) PHONY
	$(BOOTSTRAPRUBY) "$(srcdir)/bootstraptest/runner.rb" --ruby="$(PROGRAM)" $(OPTS) $(srcdir)/KNOWNBUGS.rb

test: test-sample btest-miniruby test-knownbug

test-all:
	$(RUNRUBY) "$(srcdir)/test/runner.rb" --basedir="$(TESTSDIR)" --runner=$(TESTUI) $(TESTS)

extconf: $(PREP)
	$(MAKEDIRS) "$(EXTCONFDIR)"
	$(RUNRUBY) -C "$(EXTCONFDIR)" $(EXTCONF) $(EXTCONFARGS)

$(RBCONFIG): $(srcdir)/mkconfig.rb config.status $(PREP)
	@$(MINIRUBY) $(srcdir)/mkconfig.rb -timestamp=$@ \
		-install_name=$(RUBY_INSTALL_NAME) \
		-so_name=$(RUBY_SO_NAME) rbconfig.rb

encs: enc.mk $(LIBRUBY) $(PREP) transdb.h
	$(MAKE) -f enc.mk MINIRUBY="$(MINIRUBY)" $(MFLAGS)

enc.mk: $(srcdir)/enc/make_encmake.rb $(srcdir)/enc/Makefile.in $(srcdir)/enc/depend \
	$(srcdir)/lib/mkmf.rb $(RBCONFIG)
	$(MINIRUBY) $(srcdir)/enc/make_encmake.rb --builtin-encs="$(BUILTIN_ENCOBJS)" $@ $(ENCS)

.PRECIOUS: $(MKFILES)

.PHONY: test install install-nodoc install-doc dist

PHONY:

{$(VPATH)}parse.c: {$(VPATH)}parse.y $(srcdir)/tool/ytab.sed

{$(srcdir)}.y.c:
	$(YACC) -d $(YFLAGS) -o y.tab.c $<
	sed -f $(srcdir)/tool/ytab.sed -e "/^#/s!y\.tab\.c!$@!" y.tab.c > $@.new
	@$(MV) $@.new $@
	sed -e "/^#/s!y\.tab\.h!$(@:.c=.h)!" y.tab.h > $(@:.c=.h).new
	@$(MV) $(@:.c=.h).new $(@:.c=.h)
	@$(RM) y.tab.c y.tab.h

acosh.$(OBJEXT): {$(VPATH)}acosh.c
alloca.$(OBJEXT): {$(VPATH)}alloca.c {$(VPATH)}config.h
crypt.$(OBJEXT): {$(VPATH)}crypt.c
dup2.$(OBJEXT): {$(VPATH)}dup2.c
erf.$(OBJEXT): {$(VPATH)}erf.c
finite.$(OBJEXT): {$(VPATH)}finite.c
flock.$(OBJEXT): {$(VPATH)}flock.c
memcmp.$(OBJEXT): {$(VPATH)}memcmp.c
memmove.$(OBJEXT): {$(VPATH)}memmove.c
mkdir.$(OBJEXT): {$(VPATH)}mkdir.c
strchr.$(OBJEXT): {$(VPATH)}strchr.c
strdup.$(OBJEXT): {$(VPATH)}strdup.c
strerror.$(OBJEXT): {$(VPATH)}strerror.c
strftime.$(OBJEXT): {$(VPATH)}strftime.c
strstr.$(OBJEXT): {$(VPATH)}strstr.c
strtod.$(OBJEXT): {$(VPATH)}strtod.c
strtol.$(OBJEXT): {$(VPATH)}strtol.c
nt.$(OBJEXT): {$(VPATH)}nt.c
x68.$(OBJEXT): {$(VPATH)}x68.c
os2.$(OBJEXT): {$(VPATH)}os2.c
dl_os2.$(OBJEXT): {$(VPATH)}dl_os2.c
ia64.$(OBJEXT): {$(VPATH)}ia64.s
	$(CC) $(CFLAGS) -c $<

# when I use -I., there is confliction at "OpenFile" 
# so, set . into environment varible "include"
win32.$(OBJEXT): {$(VPATH)}win32.c

###

RUBY_H_INCLUDES = {$(VPATH)}ruby.h {$(VPATH)}config.h {$(VPATH)}defines.h \
		  {$(VPATH)}intern.h {$(VPATH)}missing.h

array.$(OBJEXT): {$(VPATH)}array.c $(RUBY_H_INCLUDES) \
  {$(VPATH)}st.h {$(VPATH)}util.h
bignum.$(OBJEXT): {$(VPATH)}bignum.c $(RUBY_H_INCLUDES) \
  {$(VPATH)}st.h
class.$(OBJEXT): {$(VPATH)}class.c $(RUBY_H_INCLUDES) \
  {$(VPATH)}st.h {$(VPATH)}signal.h {$(VPATH)}node.h \
  {$(VPATH)}vm_core.h {$(VPATH)}debug.h {$(VPATH)}vm_opts.h \
  {$(VPATH)}id.h {$(VPATH)}parse.c \
  {$(VPATH)}thread_$(THREAD_MODEL).h
compar.$(OBJEXT): {$(VPATH)}compar.c $(RUBY_H_INCLUDES) \
  {$(VPATH)}st.h
complex.$(OBJEXT): {$(VPATH)}complex.c $(RUBY_H_INCLUDES) \
  {$(VPATH)}st.h
dir.$(OBJEXT): {$(VPATH)}dir.c $(RUBY_H_INCLUDES) \
  {$(VPATH)}st.h {$(VPATH)}util.h
dln.$(OBJEXT): {$(VPATH)}dln.c $(RUBY_H_INCLUDES) \
  {$(VPATH)}st.h {$(VPATH)}dln.h
dmydln.$(OBJEXT): {$(VPATH)}dmydln.c dln.$(OBJEXT)
dmyext.$(OBJEXT): {$(VPATH)}dmyext.c
dmyencoding.$(OBJEXT): {$(VPATH)}dmyencoding.c \
  {$(VPATH)}encoding.c $(RUBY_H_INCLUDES) {$(VPATH)}st.h \
  {$(VPATH)}encoding.h {$(VPATH)}oniguruma.h {$(VPATH)}regenc.h
encoding.$(OBJEXT): dmyencoding.$(OBJEXT) {$(VPATH)}util.h
enum.$(OBJEXT): {$(VPATH)}enum.c $(RUBY_H_INCLUDES) \
  {$(VPATH)}st.h {$(VPATH)}node.h {$(VPATH)}util.h
enumerator.$(OBJEXT): {$(VPATH)}enumerator.c $(RUBY_H_INCLUDES) \
  {$(VPATH)}st.h {$(VPATH)}debug.h {$(VPATH)}node.h
error.$(OBJEXT): {$(VPATH)}error.c $(RUBY_H_INCLUDES) \
  {$(VPATH)}st.h {$(VPATH)}vm_core.h {$(VPATH)}signal.h {$(VPATH)}node.h \
  {$(VPATH)}debug.h {$(VPATH)}vm_opts.h {$(VPATH)}id.h {$(VPATH)}parse.c \
  {$(VPATH)}thread_$(THREAD_MODEL).h
eval.$(OBJEXT): {$(VPATH)}eval.c {$(VPATH)}eval_intern.h \
  $(RUBY_H_INCLUDES) {$(VPATH)}st.h {$(VPATH)}node.h \
  {$(VPATH)}util.h {$(VPATH)}signal.h {$(VPATH)}vm_core.h \
  {$(VPATH)}debug.h {$(VPATH)}vm_opts.h {$(VPATH)}id.h {$(VPATH)}parse.c \
  {$(VPATH)}thread_$(THREAD_MODEL).h {$(VPATH)}dln.h \
  {$(VPATH)}eval_error.c {$(VPATH)}eval_safe.c \
  {$(VPATH)}eval_jump.c
load.$(OBJEXT): {$(VPATH)}load.c {$(VPATH)}eval_intern.h \
  $(RUBY_H_INCLUDES) {$(VPATH)}st.h {$(VPATH)}node.h \
  {$(VPATH)}util.h {$(VPATH)}signal.h {$(VPATH)}vm_core.h \
  {$(VPATH)}debug.h {$(VPATH)}vm_opts.h {$(VPATH)}id.h {$(VPATH)}parse.c \
  {$(VPATH)}thread_$(THREAD_MODEL).h {$(VPATH)}dln.h
file.$(OBJEXT): {$(VPATH)}file.c $(RUBY_H_INCLUDES) \
  {$(VPATH)}st.h {$(VPATH)}io.h {$(VPATH)}encoding.h {$(VPATH)}oniguruma.h \
  {$(VPATH)}signal.h {$(VPATH)}util.h {$(VPATH)}dln.h
gc.$(OBJEXT): {$(VPATH)}gc.c $(RUBY_H_INCLUDES) \
  {$(VPATH)}st.h {$(VPATH)}signal.h {$(VPATH)}node.h {$(VPATH)}re.h \
  {$(VPATH)}regex.h {$(VPATH)}oniguruma.h {$(VPATH)}io.h \
  {$(VPATH)}encoding.h {$(VPATH)}vm_core.h {$(VPATH)}debug.h \
  {$(VPATH)}vm_opts.h {$(VPATH)}id.h {$(VPATH)}parse.c \
  {$(VPATH)}thread_$(THREAD_MODEL).h \
  {$(VPATH)}gc.h {$(VPATH)}eval_intern.h
hash.$(OBJEXT): {$(VPATH)}hash.c $(RUBY_H_INCLUDES) \
  {$(VPATH)}st.h {$(VPATH)}util.h {$(VPATH)}signal.h
inits.$(OBJEXT): {$(VPATH)}inits.c $(RUBY_H_INCLUDES) \
  {$(VPATH)}st.h
io.$(OBJEXT): {$(VPATH)}io.c $(RUBY_H_INCLUDES) \
  {$(VPATH)}st.h {$(VPATH)}io.h {$(VPATH)}encoding.h {$(VPATH)}oniguruma.h \
  {$(VPATH)}signal.h {$(VPATH)}util.h \
  {$(VPATH)}vm_core.h {$(VPATH)}debug.h \
  {$(VPATH)}vm_opts.h {$(VPATH)}id.h {$(VPATH)}parse.c \
  {$(VPATH)}thread_$(THREAD_MODEL).h
main.$(OBJEXT): {$(VPATH)}main.c $(RUBY_H_INCLUDES) \
  {$(VPATH)}st.h
marshal.$(OBJEXT): {$(VPATH)}marshal.c $(RUBY_H_INCLUDES) \
  {$(VPATH)}st.h {$(VPATH)}io.h {$(VPATH)}encoding.h \
  {$(VPATH)}oniguruma.h {$(VPATH)}util.h
math.$(OBJEXT): {$(VPATH)}math.c $(RUBY_H_INCLUDES) {$(VPATH)}st.h
numeric.$(OBJEXT): {$(VPATH)}numeric.c $(RUBY_H_INCLUDES) \
  {$(VPATH)}st.h {$(VPATH)}encoding.h {$(VPATH)}oniguruma.h
object.$(OBJEXT): {$(VPATH)}object.c $(RUBY_H_INCLUDES) \
  {$(VPATH)}st.h {$(VPATH)}util.h {$(VPATH)}debug.h {$(VPATH)}node.h
pack.$(OBJEXT): {$(VPATH)}pack.c $(RUBY_H_INCLUDES) {$(VPATH)}st.h
parse.$(OBJEXT): {$(VPATH)}parse.c {$(VPATH)}parse.y $(RUBY_H_INCLUDES) \
  {$(VPATH)}st.h {$(VPATH)}node.h {$(VPATH)}encoding.h \
  {$(VPATH)}oniguruma.h {$(VPATH)}id.h {$(VPATH)}parse.c \
  {$(VPATH)}regenc.h {$(VPATH)}regex.h {$(VPATH)}util.h \
  {$(VPATH)}lex.c {$(VPATH)}keywords {$(VPATH)}debug.h
prec.$(OBJEXT): {$(VPATH)}prec.c $(RUBY_H_INCLUDES) {$(VPATH)}st.h
proc.$(OBJEXT): {$(VPATH)}proc.c {$(VPATH)}eval_intern.h \
  $(RUBY_H_INCLUDES) {$(VPATH)}st.h {$(VPATH)}node.h \
  {$(VPATH)}util.h {$(VPATH)}signal.h {$(VPATH)}vm_core.h \
  {$(VPATH)}debug.h {$(VPATH)}vm_opts.h {$(VPATH)}id.h {$(VPATH)}parse.c \
  {$(VPATH)}thread_$(THREAD_MODEL).h {$(VPATH)}dln.h {$(VPATH)}gc.h
process.$(OBJEXT): {$(VPATH)}process.c $(RUBY_H_INCLUDES) {$(VPATH)}st.h \
  {$(VPATH)}signal.h {$(VPATH)}vm_core.h {$(VPATH)}util.h \
  {$(VPATH)}node.h {$(VPATH)}debug.h {$(VPATH)}vm_opts.h \
  {$(VPATH)}id.h {$(VPATH)}parse.c \
  {$(VPATH)}thread_$(THREAD_MODEL).h
random.$(OBJEXT): {$(VPATH)}random.c $(RUBY_H_INCLUDES) \
  {$(VPATH)}st.h
range.$(OBJEXT): {$(VPATH)}range.c $(RUBY_H_INCLUDES) \
  {$(VPATH)}st.h
rational.$(OBJEXT): {$(VPATH)}rational.c $(RUBY_H_INCLUDES) \
  {$(VPATH)}st.h
re.$(OBJEXT): {$(VPATH)}re.c $(RUBY_H_INCLUDES) \
  {$(VPATH)}st.h {$(VPATH)}re.h {$(VPATH)}regex.h {$(VPATH)}oniguruma.h \
  {$(VPATH)}encoding.h {$(VPATH)}util.h \
  {$(VPATH)}regint.h {$(VPATH)}vm_core.h {$(VPATH)}debug.h \
  {$(VPATH)}vm_opts.h {$(VPATH)}id.h {$(VPATH)}parse.c \
  {$(VPATH)}thread_$(THREAD_MODEL).h \
  {$(VPATH)}regenc.h
regcomp.$(OBJEXT): {$(VPATH)}regcomp.c {$(VPATH)}regparse.h \
  {$(VPATH)}regint.h {$(VPATH)}vm_core.h {$(VPATH)}debug.h \
  {$(VPATH)}vm_opts.h {$(VPATH)}id.h {$(VPATH)}parse.c \
  {$(VPATH)}thread_$(THREAD_MODEL).h \
  {$(VPATH)}config.h {$(VPATH)}defines.h \
  {$(VPATH)}regenc.h {$(VPATH)}oniguruma.h {$(VPATH)}st.h
regenc.$(OBJEXT): {$(VPATH)}regenc.c \
  {$(VPATH)}regint.h {$(VPATH)}vm_core.h {$(VPATH)}debug.h \
  {$(VPATH)}vm_opts.h {$(VPATH)}id.h {$(VPATH)}parse.c \
  {$(VPATH)}thread_$(THREAD_MODEL).h \
  {$(VPATH)}config.h {$(VPATH)}defines.h {$(VPATH)}regenc.h \
  {$(VPATH)}oniguruma.h {$(VPATH)}st.h
regerror.$(OBJEXT): {$(VPATH)}regerror.c \
  {$(VPATH)}regint.h {$(VPATH)}vm_core.h {$(VPATH)}debug.h \
  {$(VPATH)}vm_opts.h {$(VPATH)}id.h {$(VPATH)}parse.c \
  {$(VPATH)}thread_$(THREAD_MODEL).h \
  {$(VPATH)}config.h {$(VPATH)}defines.h {$(VPATH)}regenc.h \
  {$(VPATH)}oniguruma.h {$(VPATH)}st.h
regexec.$(OBJEXT): {$(VPATH)}regexec.c \
  {$(VPATH)}regint.h {$(VPATH)}vm_core.h {$(VPATH)}debug.h \
  {$(VPATH)}vm_opts.h {$(VPATH)}id.h {$(VPATH)}parse.c \
  {$(VPATH)}thread_$(THREAD_MODEL).h \
  {$(VPATH)}config.h {$(VPATH)}defines.h {$(VPATH)}regenc.h \
  {$(VPATH)}oniguruma.h {$(VPATH)}st.h
regparse.$(OBJEXT): {$(VPATH)}regparse.c {$(VPATH)}regparse.h \
  {$(VPATH)}regint.h {$(VPATH)}vm_core.h {$(VPATH)}debug.h \
  {$(VPATH)}vm_opts.h {$(VPATH)}id.h {$(VPATH)}parse.c \
  {$(VPATH)}thread_$(THREAD_MODEL).h \
  {$(VPATH)}config.h {$(VPATH)}defines.h \
  {$(VPATH)}regenc.h {$(VPATH)}oniguruma.h {$(VPATH)}st.h
regsyntax.$(OBJEXT): {$(VPATH)}regsyntax.c \
  {$(VPATH)}regint.h {$(VPATH)}vm_core.h {$(VPATH)}debug.h \
  {$(VPATH)}vm_opts.h {$(VPATH)}id.h {$(VPATH)}parse.c \
  {$(VPATH)}thread_$(THREAD_MODEL).h \
  {$(VPATH)}config.h {$(VPATH)}defines.h {$(VPATH)}regenc.h \
  {$(VPATH)}oniguruma.h {$(VPATH)}st.h
ruby.$(OBJEXT): {$(VPATH)}ruby.c $(RUBY_H_INCLUDES) \
  {$(VPATH)}st.h {$(VPATH)}node.h {$(VPATH)}encoding.h \
  {$(VPATH)}oniguruma.h {$(VPATH)}eval_intern.h {$(VPATH)}util.h \
  {$(VPATH)}signal.h {$(VPATH)}vm_core.h {$(VPATH)}debug.h \
  {$(VPATH)}vm_opts.h {$(VPATH)}id.h {$(VPATH)}parse.c \
  {$(VPATH)}thread_$(THREAD_MODEL).h {$(VPATH)}dln.h
signal.$(OBJEXT): {$(VPATH)}signal.c $(RUBY_H_INCLUDES) \
  {$(VPATH)}st.h {$(VPATH)}signal.h {$(VPATH)}node.h {$(VPATH)}vm_core.h \
  {$(VPATH)}debug.h {$(VPATH)}vm_opts.h {$(VPATH)}id.h {$(VPATH)}parse.c \
  {$(VPATH)}thread_$(THREAD_MODEL).h
sprintf.$(OBJEXT): {$(VPATH)}sprintf.c $(RUBY_H_INCLUDES) {$(VPATH)}st.h \
  {$(VPATH)}re.h {$(VPATH)}regex.h {$(VPATH)}oniguruma.h \
  {$(VPATH)}encoding.h {$(VPATH)}vsnprintf.c
st.$(OBJEXT): {$(VPATH)}st.c {$(VPATH)}config.h {$(VPATH)}defines.h \
  {$(VPATH)}st.h
string.$(OBJEXT): {$(VPATH)}string.c $(RUBY_H_INCLUDES) \
  {$(VPATH)}st.h {$(VPATH)}re.h {$(VPATH)}regex.h {$(VPATH)}oniguruma.h \
  {$(VPATH)}encoding.h
struct.$(OBJEXT): {$(VPATH)}struct.c $(RUBY_H_INCLUDES) \
  {$(VPATH)}st.h
thread.$(OBJEXT): {$(VPATH)}thread.c {$(VPATH)}eval_intern.h \
  $(RUBY_H_INCLUDES) {$(VPATH)}st.h {$(VPATH)}node.h \
  {$(VPATH)}util.h {$(VPATH)}signal.h {$(VPATH)}vm_core.h \
  {$(VPATH)}debug.h {$(VPATH)}vm_opts.h {$(VPATH)}id.h {$(VPATH)}parse.c \
  {$(VPATH)}thread_$(THREAD_MODEL).h {$(VPATH)}dln.h {$(VPATH)}vm.h \
  {$(VPATH)}gc.h {$(VPATH)}thread_$(THREAD_MODEL).c
transcode.$(OBJEXT): {$(VPATH)}transcode.c $(RUBY_H_INCLUDES) {$(VPATH)}st.h \
  {$(VPATH)}encoding.h {$(VPATH)}oniguruma.h {$(VPATH)}transcode_data.h
cont.$(OBJEXT): {$(VPATH)}cont.c $(RUBY_H_INCLUDES) \
  {$(VPATH)}st.h {$(VPATH)}vm_core.h {$(VPATH)}signal.h {$(VPATH)}node.h \
  {$(VPATH)}debug.h {$(VPATH)}vm_opts.h {$(VPATH)}id.h {$(VPATH)}parse.c \
  {$(VPATH)}thread_$(THREAD_MODEL).h {$(VPATH)}gc.h \
  {$(VPATH)}eval_intern.h {$(VPATH)}util.h {$(VPATH)}dln.h
time.$(OBJEXT): {$(VPATH)}time.c $(RUBY_H_INCLUDES) \
  {$(VPATH)}st.h {$(VPATH)}encoding.h 
util.$(OBJEXT): {$(VPATH)}util.c $(RUBY_H_INCLUDES) \
  {$(VPATH)}st.h {$(VPATH)}util.h
variable.$(OBJEXT): {$(VPATH)}variable.c $(RUBY_H_INCLUDES) {$(VPATH)}st.h \
  {$(VPATH)}node.h {$(VPATH)}util.h
version.$(OBJEXT): {$(VPATH)}version.c $(RUBY_H_INCLUDES) {$(VPATH)}st.h \
  {$(VPATH)}version.h $(srcdir)/revision.h

compile.$(OBJEXT): {$(VPATH)}compile.c $(RUBY_H_INCLUDES) {$(VPATH)}st.h \
  {$(VPATH)}node.h {$(VPATH)}vm_core.h \
  {$(VPATH)}signal.h {$(VPATH)}debug.h {$(VPATH)}vm_opts.h \
  {$(VPATH)}id.h {$(VPATH)}parse.c \
  {$(VPATH)}thread_$(THREAD_MODEL).h {$(VPATH)}compile.h \
  {$(VPATH)}insns.inc {$(VPATH)}insns_info.inc {$(VPATH)}optinsn.inc
iseq.$(OBJEXT): {$(VPATH)}iseq.c $(RUBY_H_INCLUDES) \
  {$(VPATH)}st.h {$(VPATH)}node.h {$(VPATH)}gc.h {$(VPATH)}vm_core.h \
  {$(VPATH)}signal.h {$(VPATH)}debug.h {$(VPATH)}vm_opts.h \
  {$(VPATH)}id.h {$(VPATH)}parse.c \
  {$(VPATH)}thread_$(THREAD_MODEL).h {$(VPATH)}insns.inc \
  {$(VPATH)}insns_info.inc {$(VPATH)}node_name.inc
vm.$(OBJEXT): {$(VPATH)}vm.c $(RUBY_H_INCLUDES) \
  {$(VPATH)}st.h {$(VPATH)}node.h {$(VPATH)}encoding.h \
  {$(VPATH)}oniguruma.h {$(VPATH)}gc.h {$(VPATH)}insnhelper.h \
  {$(VPATH)}eval_intern.h {$(VPATH)}util.h {$(VPATH)}signal.h \
  {$(VPATH)}vm_core.h {$(VPATH)}debug.h {$(VPATH)}vm_opts.h \
  {$(VPATH)}id.h {$(VPATH)}parse.c \
  {$(VPATH)}thread_$(THREAD_MODEL).h {$(VPATH)}dln.h {$(VPATH)}vm.h \
  {$(VPATH)}vm_insnhelper.c {$(VPATH)}insns.inc {$(VPATH)}vm_evalbody.c \
  {$(VPATH)}vmtc.inc {$(VPATH)}vm.inc {$(VPATH)}insns.def \
  {$(VPATH)}vm_method.c {$(VPATH)}vm_eval.c
vm_dump.$(OBJEXT): {$(VPATH)}vm_dump.c $(RUBY_H_INCLUDES) {$(VPATH)}st.h \
  {$(VPATH)}node.h {$(VPATH)}vm_core.h \
  {$(VPATH)}signal.h {$(VPATH)}debug.h {$(VPATH)}vm_opts.h \
  {$(VPATH)}id.h {$(VPATH)}parse.c \
  {$(VPATH)}thread_$(THREAD_MODEL).h {$(VPATH)}vm.h
debug.$(OBJEXT): {$(VPATH)}debug.c $(RUBY_H_INCLUDES) \
  {$(VPATH)}st.h {$(VPATH)}encoding.h {$(VPATH)}oniguruma.h \
  {$(VPATH)}debug.h {$(VPATH)}node.h {$(VPATH)}vm_core.h \
  {$(VPATH)}signal.h {$(VPATH)}vm_opts.h {$(VPATH)}id.h {$(VPATH)}parse.c \
  {$(VPATH)}thread_$(THREAD_MODEL).h
blockinlining.$(OBJEXT): {$(VPATH)}blockinlining.c $(RUBY_H_INCLUDES) \
  {$(VPATH)}st.h {$(VPATH)}node.h {$(VPATH)}vm_core.h \
  {$(VPATH)}signal.h {$(VPATH)}debug.h {$(VPATH)}vm_opts.h \
  {$(VPATH)}id.h {$(VPATH)}parse.c \
  {$(VPATH)}thread_$(THREAD_MODEL).h
id.$(OBJEXT): {$(VPATH)}id.c $(RUBY_H_INCLUDES) \
  {$(VPATH)}st.h {$(VPATH)}id.h {$(VPATH)}parse.c
miniprelude.$(OBJEXT): {$(VPATH)}miniprelude.c $(RUBY_H_INCLUDES) \
  {$(VPATH)}st.h {$(VPATH)}vm_core.h {$(VPATH)}signal.h \
  {$(VPATH)}node.h {$(VPATH)}debug.h {$(VPATH)}vm_opts.h \
  {$(VPATH)}id.h {$(VPATH)}parse.c \
  {$(VPATH)}thread_$(THREAD_MODEL).h
prelude.$(OBJEXT): {$(VPATH)}prelude.c $(RUBY_H_INCLUDES) {$(VPATH)}st.h \
  {$(VPATH)}vm_core.h {$(VPATH)}signal.h \
  {$(VPATH)}node.h {$(VPATH)}debug.h {$(VPATH)}vm_opts.h \
  {$(VPATH)}id.h {$(VPATH)}parse.c \
  {$(VPATH)}thread_$(THREAD_MODEL).h
golf_prelude.$(OBJEXT): {$(VPATH)}golf_prelude.c $(RUBY_H_INCLUDES) \
  {$(VPATH)}st.h {$(VPATH)}vm_core.h {$(VPATH)}signal.h \
  {$(VPATH)}node.h {$(VPATH)}debug.h {$(VPATH)}vm_opts.h \
  {$(VPATH)}id.h {$(VPATH)}parse.c \
  {$(VPATH)}thread_$(THREAD_MODEL).h
goruby.$(OBJEXT): {$(VPATH)}goruby.c {$(VPATH)}main.c $(RUBY_H_INCLUDES) {$(VPATH)}st.h

ascii.$(OBJEXT): {$(VPATH)}ascii.c {$(VPATH)}regenc.h {$(VPATH)}config.h \
  {$(VPATH)}defines.h {$(VPATH)}oniguruma.h
us_ascii.$(OBJEXT): {$(VPATH)}us_ascii.c {$(VPATH)}regenc.h {$(VPATH)}config.h \
  {$(VPATH)}defines.h {$(VPATH)}oniguruma.h
unicode.$(OBJEXT): {$(VPATH)}unicode.c \
  {$(VPATH)}regint.h {$(VPATH)}vm_core.h {$(VPATH)}debug.h \
  {$(VPATH)}vm_opts.h {$(VPATH)}id.h {$(VPATH)}parse.c \
  {$(VPATH)}thread_$(THREAD_MODEL).h \
  {$(VPATH)}config.h {$(VPATH)}defines.h {$(VPATH)}regenc.h \
  {$(VPATH)}oniguruma.h {$(VPATH)}st.h
utf_8.$(OBJEXT): {$(VPATH)}utf_8.c {$(VPATH)}regenc.h {$(VPATH)}config.h \
  {$(VPATH)}defines.h {$(VPATH)}oniguruma.h

INSNS	= opt_sc.inc optinsn.inc optunifs.inc insns.inc insns_info.inc \
	  vmtc.inc vm.inc

INSNS2VMOPT = --srcdir="$(srcdir)"

$(INSNS): $(srcdir)/insns.def {$(VPATH)}vm_opts.h
	@$(RM) $(PROGRAM)
	$(BASERUBY) -Ks $(srcdir)/tool/insns2vm.rb $(INSNS2VMOPT) $@

minsns.inc: $(srcdir)/template/minsns.inc.tmpl

opt_sc.inc: $(srcdir)/template/opt_sc.inc.tmpl

optinsn.inc: $(srcdir)/template/optinsn.inc.tmpl

optunifs.inc: $(srcdir)/template/optunifs.inc.tmpl

insns.inc: $(srcdir)/template/insns.inc.tmpl

insns_info.inc: $(srcdir)/template/insns_info.inc.tmpl

vmtc.inc: $(srcdir)/template/vmtc.inc.tmpl

vm.inc: $(srcdir)/template/vm.inc.tmpl

srcs: {$(VPATH)}parse.c {$(VPATH)}lex.c $(srcdir)/ext/ripper/ripper.c srcs-enc

srcs-enc: enc.mk
	$(MAKE) -f enc.mk RUBY="$(MINIRUBY)" MINIRUBY="$(MINIRUBY)" $(MFLAGS) srcs

incs: $(INSNS) {$(VPATH)}node_name.inc {$(VPATH)}encdb.h {$(VPATH)}transdb.h $(srcdir)/revision.h

insns: $(INSNS)

node_name.inc: {$(VPATH)}node.h
	$(BASERUBY) -n $(srcdir)/tool/node_name.rb $? > $@

encdb.h: $(PREP)
	$(MINIRUBY) $(srcdir)/enc/make_encdb.rb $@.new $(srcdir)/enc enc
	$(IFCHANGE) "$@" "$@.new"

transdb.h: $(PREP) srcs-enc
	$(MINIRUBY) $(srcdir)/enc/trans/make_transdb.rb $@.new $(srcdir)/enc/trans enc/trans
	$(IFCHANGE) "$@" "$@.new"

miniprelude.c: $(srcdir)/tool/compile_prelude.rb $(srcdir)/prelude.rb
	$(BASERUBY) -I$(srcdir) $(srcdir)/tool/compile_prelude.rb $(srcdir)/prelude.rb $@

prelude.c: $(srcdir)/tool/compile_prelude.rb $(PRELUDE_SCRIPTS) $(PREP)
	$(COMPILE_PRELUDE) $(PRELUDE_SCRIPTS) $@

golf_prelude.c: $(srcdir)/tool/compile_prelude.rb $(srcdir)/prelude.rb $(srcdir)/golf_prelude.rb $(PREP)
	$(COMPILE_PRELUDE) $(srcdir)/golf_prelude.rb $@

prereq: incs srcs preludes

preludes: {$(VPATH)}miniprelude.c
preludes: {$(srcdir)}golf_prelude.c

docs:
	$(BASERUBY) -I$(srcdir) $(srcdir)/tool/makedocs.rb $(INSNS2VMOPT)

$(srcdir)/revision.h: $(REVISION_FORCE)
	@set LC_MESSAGES=C
	-@$(SET_LC_MESSAGES) $(VCS) info "$(@D)" | \
	sed -n "s/.*Rev:/#define RUBY_REVISION/p" > "$@.tmp"
	@$(IFCHANGE) "$@" "$@.tmp"

$(srcdir)/ext/ripper/ripper.c:
	cd $(srcdir)/ext/ripper && exec $(MAKE) -f depend $(MFLAGS) top_srcdir=../.. srcdir=.

##

run: miniruby$(EXEEXT) PHONY
	$(MINIRUBY) $(srcdir)/test.rb $(RUNOPT)

runruby: $(PROGRAM) PHONY
	$(RUNRUBY) $(srcdir)/test.rb

parse: miniruby$(EXEEXT) PHONY
	$(MINIRUBY) $(srcdir)/tool/parse.rb $(srcdir)/test.rb

COMPARE_RUBY = $(BASERUBY)
ITEM = 
OPTS = 

benchmark: $(PROGRAM) PHONY
	$(BASERUBY) $(srcdir)/benchmark/driver.rb -v \
	            --executables="$(COMPARE_RUBY); $(RUNRUBY)" \
	            --pattern='bm_' --directory=$(srcdir)/benchmark $(OPTS)

benchmark-each: $(PROGRAM) PHONY
	$(BASERUBY) $(srcdir)/benchmark/driver.rb -v \
	            --executables="$(COMPARE_RUBY); $(RUNRUBY)" \
	            --pattern=$(ITEM) --directory=$(srcdir)/benchmark $(OPTS)

tbench: $(PROGRAM) PHONY
	$(BASERUBY) $(srcdir)/benchmark/driver.rb -v \
	            --executables="$(COMPARE_RUBY); $(RUNRUBY)" \
	            --pattern='bmx_' --directory=$(srcdir)/benchmark $(OPTS)

aotc: $(PROGRAM) PHONY
	./$(PROGRAM) -I$(srcdir)/lib $(srcdir)/bin/ruby2cext $(srcdir)/test.rb

vmasm: vm.$(ASMEXT)

# vm.o : CFLAGS += -fno-crossjumping

run.gdb:
	echo b ruby_debug_breakpoint           > run.gdb
	echo '# handle SIGINT nostop'         >> run.gdb
	echo '# handle SIGPIPE nostop'        >> run.gdb
	echo '# b rb_longjmp'                 >> run.gdb
	echo source $(srcdir)/breakpoints.gdb >> run.gdb
	echo source $(srcdir)/.gdbinit        >> run.gdb
	echo run                              >> run.gdb

gdb: miniruby$(EXEEXT) run.gdb PHONY
	gdb -x run.gdb --quiet --args $(MINIRUBY) $(srcdir)/test.rb

# Intel VTune

vtune: miniruby$(EXEEXT)
	vtl activity -c sampling -app ".\miniruby$(EXEEXT)","-I$(srcdir)/lib $(srcdir)/test.rb" run
	vtl view -hf -mn miniruby$(EXEEXT) -sum -sort -cd
	vtl view -ha -mn miniruby$(EXEEXT) -sum -sort -cd | $(RUNRUBY) $(srcdir)/tool/vtlh.rb > ha.lines

dist: $(PREP) $(PROGRAM)
	$(SHELL) $(srcdir)/tool/make-snapshot . $(TARNAME)

up:
	@$(VCS) up "$(srcdir)"
	-@$(MAKE) $(MFLAGS) REVISION_FORCE=PHONY "$(srcdir)/revision.h"

help: PHONY
	@echo "                Makefile of Ruby"
	@echo ""
	@echo "targets:"
	@echo "  all:           compile ruby and extensions"
	@echo "  check:         equals make test test-all"
	@echo "  test:          ruby core tests"
	@echo "  test-all:      all ruby tests"
	@echo "  install:       install all ruby distributions"
	@echo "  install-nodoc: install without rdoc"
	@echo "  clean:         clean built objects"
	@echo "  golf:          for golfers"
