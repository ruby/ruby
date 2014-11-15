bin: $(PROGRAM) $(WPROGRAM)
lib: $(LIBRUBY)
dll: $(LIBRUBY_SO)

.SUFFIXES: .inc .h .c .y .i .$(DTRACE_EXT)

# V=0 quiet, V=1 verbose.  other values don't work.
V = 0
Q1 = $(V:1=)
Q = $(Q1:0=@)
ECHO = $(ECHO1:0=@echo)

UNICODE_VERSION = 7.0.0

RUBYLIB       = $(PATH_SEPARATOR)
RUBYOPT       = -
RUN_OPTS      = --disable-gems

SPEC_GIT_BASE = git://github.com/nurse
MSPEC_GIT_URL = $(SPEC_GIT_BASE)/mspec.git
RUBYSPEC_GIT_URL = $(SPEC_GIT_BASE)/rubyspec.git

SIMPLECOV_GIT_URL = git://github.com/hsbt/simplecov.git

STATIC_RUBY   = static-ruby

EXTCONF       = extconf.rb
LIBRUBY_EXTS  = ./.libruby-with-ext.time
REVISION_H    = ./.revision.time
PLATFORM_D    = ./$(PLATFORM_DIR)/.time
RDOCOUT       = $(EXTOUT)/rdoc
CAPIOUT       = doc/capi

DMYEXT	      = dmyext.$(OBJEXT)
NORMALMAINOBJ = main.$(OBJEXT)
MAINOBJ       = $(NORMALMAINOBJ)
EXTOBJS	      =
DLDOBJS	      = $(DMYEXT)
EXTSOLIBS     =
MINIOBJS      = $(ARCHMINIOBJS) miniinit.$(OBJEXT) miniprelude.$(OBJEXT)
ENC_MK        = enc.mk

COMMONOBJS    = array.$(OBJEXT) \
		bignum.$(OBJEXT) \
		class.$(OBJEXT) \
		compar.$(OBJEXT) \
		complex.$(OBJEXT) \
		dir.$(OBJEXT) \
		dln_find.$(OBJEXT) \
		encoding.$(OBJEXT) \
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
		node.$(OBJEXT) \
		numeric.$(OBJEXT) \
		object.$(OBJEXT) \
		pack.$(OBJEXT) \
		parse.$(OBJEXT) \
		process.$(OBJEXT) \
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
		safe.$(OBJEXT) \
		signal.$(OBJEXT) \
		sprintf.$(OBJEXT) \
		st.$(OBJEXT) \
		strftime.$(OBJEXT) \
		string.$(OBJEXT) \
		struct.$(OBJEXT) \
		symbol.$(OBJEXT) \
		time.$(OBJEXT) \
		transcode.$(OBJEXT) \
		util.$(OBJEXT) \
		variable.$(OBJEXT) \
		version.$(OBJEXT) \
		compile.$(OBJEXT) \
		debug.$(OBJEXT) \
		iseq.$(OBJEXT) \
		vm.$(OBJEXT) \
		vm_dump.$(OBJEXT) \
		vm_backtrace.$(OBJEXT) \
		vm_trace.$(OBJEXT) \
		thread.$(OBJEXT) \
		cont.$(OBJEXT) \
		$(BUILTIN_ENCOBJS) \
		$(BUILTIN_TRANSOBJS) \
		$(MISSING)

EXPORTOBJS    = $(DLNOBJ) \
		localeinit.$(OBJEXT) \
		loadpath.$(OBJEXT) \
		$(COMMONOBJS)

OBJS          = $(EXPORTOBJS) prelude.$(OBJEXT)
ALLOBJS       = $(NORMALMAINOBJ) $(MINIOBJS) $(COMMONOBJS) $(DMYEXT)

GOLFOBJS      = goruby.$(OBJEXT) golf_prelude.$(OBJEXT)

DEFAULT_PRELUDES = $(GEM_PRELUDE)
PRELUDE_SCRIPTS = $(srcdir)/prelude.rb $(srcdir)/enc/prelude.rb $(DEFAULT_PRELUDES)
GEM_PRELUDE   = $(srcdir)/gem_prelude.rb
PRELUDES      = {$(srcdir)}prelude.c {$(srcdir)}miniprelude.c
GOLFPRELUDES  = {$(srcdir)}golf_prelude.c

SCRIPT_ARGS   =	--dest-dir="$(DESTDIR)" \
		--extout="$(EXTOUT)" \
		--mflags="$(MFLAGS)" \
		--make-flags="$(MAKEFLAGS)"
EXTMK_ARGS    =	$(SCRIPT_ARGS) --extension $(EXTS) --extstatic $(EXTSTATIC) \
		--make-flags="V=$(V) MINIRUBY='$(MINIRUBY)'" --gnumake=$(gnumake) \
		--
INSTRUBY      =	$(SUDO) $(RUNRUBY) -r./$(arch)-fake $(srcdir)/tool/rbinstall.rb
INSTRUBY_ARGS =	$(SCRIPT_ARGS) \
		--data-mode=$(INSTALL_DATA_MODE) \
		--prog-mode=$(INSTALL_PROG_MODE) \
		--installed-list $(INSTALLED_LIST) \
		--mantype="$(MANTYPE)"
INSTALL_PROG_MODE = 0755
INSTALL_DATA_MODE = 0644

PRE_LIBRUBY_UPDATE = $(MINIRUBY) -e 'ARGV[1] or File.unlink(ARGV[0]) rescue nil' -- \
			$(LIBRUBY_EXTS) $(LIBRUBY_SO_UPDATE)

TESTSDIR      = $(srcdir)/test
TESTWORKDIR   = testwork

TESTRUN_SCRIPT = $(srcdir)/test.rb

BOOTSTRAPRUBY = $(BASERUBY)

COMPILE_PRELUDE = $(srcdir)/tool/generic_erb.rb $(srcdir)/template/prelude.c.tmpl

all: showflags main docs

main: showflags $(ENCSTATIC:static=lib)encs exts
	@$(NULLCMD)

.PHONY: showflags
exts enc trans: showflags
showflags:
	$(MESSAGE_BEGIN) \
	"	CC = $(CC)" \
	"	LD = $(LD)" \
	"	LDSHARED = $(LDSHARED)" \
	"	CFLAGS = $(CFLAGS)" \
	"	XCFLAGS = $(XCFLAGS)" \
	"	CPPFLAGS = $(CPPFLAGS)" \
	"	DLDFLAGS = $(DLDFLAGS)" \
	"	SOLIBS = $(SOLIBS)" \
	$(MESSAGE_END)
	-@$(CC_VERSION)

.PHONY: showconfig
showconfig:
	@$(ECHO_BEGIN) \
	$(configure_args) \
	$(ECHO_END)

exts: build-ext

EXTS_MK = exts.mk
$(EXTS_MK): $(MKFILES) all-incs $(PREP) $(RBCONFIG) $(LIBRUBY)
	$(ECHO) generating makefile $@
	$(Q)$(MINIRUBY) $(srcdir)/ext/extmk.rb --make="$(MAKE)" --command-output=$(EXTS_MK) $(EXTMK_ARGS) configure

configure-ext: $(EXTS_MK)

build-ext: $(EXTS_MK)
	$(Q)$(MAKE) -f $(EXTS_MK) $(MFLAGS) libdir="$(libdir)" LIBRUBY_EXTS=$(LIBRUBY_EXTS) \
	    ENCOBJS="$(ENCOBJS)" UPDATE_LIBRARIES=no $(EXTSTATIC)

prog: program wprogram

$(PREP): $(MKFILES)

miniruby$(EXEEXT): config.status $(ALLOBJS) $(ARCHFILE) $(DTRACE_OBJ)

objs: $(ALLOBJS)

GORUBY = go$(RUBY_INSTALL_NAME)
golf: $(LIBRUBY) $(GOLFOBJS) PHONY
	$(Q) $(MAKE) $(MFLAGS) MAINOBJ="$(GOLFOBJS)" PROGRAM=$(GORUBY)$(EXEEXT) program
capi: $(CAPIOUT)/.timestamp PHONY

$(CAPIOUT)/.timestamp: Doxyfile $(PREP)
	$(Q) $(MAKEDIRS) "$(@D)"
	$(ECHO) generating capi
	-$(Q) $(DOXYGEN) -b
	$(Q) $(MINIRUBY) -e 'File.open(ARGV[0], "w"){|f| f.puts(Time.now)}' "$@"

Doxyfile: $(srcdir)/template/Doxyfile.tmpl $(PREP) $(srcdir)/tool/generic_erb.rb $(RBCONFIG)
	$(ECHO) generating $@
	$(Q) $(MINIRUBY) $(srcdir)/tool/generic_erb.rb -o $@ $(srcdir)/template/Doxyfile.tmpl \
	--srcdir="$(srcdir)" --miniruby="$(MINIRUBY)"

program: showflags $(PROGRAM)
wprogram: showflags $(WPROGRAM)
mini: PHONY miniruby$(EXEEXT)

$(PROGRAM) $(WPROGRAM): $(LIBRUBY) $(MAINOBJ) $(OBJS) $(EXTOBJS) $(SETUP) $(PREP)

$(LIBRUBY_A):	$(OBJS) $(MAINOBJ) $(DTRACE_OBJ) $(DTRACE_GLOMMED_OBJ) $(DMYEXT) $(ARCHFILE)

$(LIBRUBY_SO):	$(OBJS) $(DLDOBJS) $(LIBRUBY_A) $(PREP) $(LIBRUBY_SO_UPDATE) $(BUILTIN_ENCOBJS)

$(LIBRUBY_EXTS):
	@exit > $@

$(STATIC_RUBY)$(EXEEXT): $(MAINOBJ) $(DLDOBJS) $(EXTOBJS) $(LIBRUBY_A)
	$(Q)$(RM) $@
	$(PURIFY) $(CC) $(MAINOBJ) $(DLDOBJS) $(EXTOBJS) $(LIBRUBY_A) $(MAINLIBS) $(EXTLIBS) $(LIBS) $(OUTFLAG)$@ $(LDFLAGS) $(XLDFLAGS)

ruby.imp: $(COMMONOBJS)
	$(Q)$(NM) -Pgp $(COMMONOBJS) | \
	awk 'BEGIN{print "#!"}; $$2~/^[BDT]$$/&&$$1!~/^(Init_|.*_threadptr_|\.)/{print $$1}' | \
	sort -u -o $@

install: install-$(INSTALLDOC)
docs: $(DOCTARGETS)
pkgconfig-data: $(ruby_pc)
$(ruby_pc): $(srcdir)/template/ruby.pc.in config.status

install-all: docs pre-install-all do-install-all post-install-all
pre-install-all:: all pre-install-local pre-install-ext pre-install-doc
do-install-all: pre-install-all
	$(INSTRUBY) --make="$(MAKE)" $(INSTRUBY_ARGS) --install=all --rdoc-output="$(RDOCOUT)"
post-install-all:: post-install-local post-install-ext post-install-doc
	@$(NULLCMD)

install-nodoc: pre-install-nodoc do-install-nodoc post-install-nodoc
pre-install-nodoc:: pre-install-local pre-install-ext
do-install-nodoc: main pre-install-nodoc
	$(INSTRUBY) --make="$(MAKE)" $(INSTRUBY_ARGS)
post-install-nodoc:: post-install-local post-install-ext

install-local: pre-install-local do-install-local post-install-local
pre-install-local:: pre-install-bin pre-install-lib pre-install-man
do-install-local: $(PROGRAM) pre-install-local
	$(INSTRUBY) --make="$(MAKE)" $(INSTRUBY_ARGS) --install=local
post-install-local:: post-install-bin post-install-lib post-install-man

install-ext: pre-install-ext do-install-ext post-install-ext
pre-install-ext:: pre-install-ext-arch pre-install-ext-comm
do-install-ext: exts pre-install-ext
	$(INSTRUBY) --make="$(MAKE)" $(INSTRUBY_ARGS) --install=ext
post-install-ext:: post-install-ext-arch post-install-ext-comm

install-arch: pre-install-arch do-install-arch post-install-arch
pre-install-arch:: pre-install-bin pre-install-ext-arch
do-install-arch: main do-install-arch
	$(INSTRUBY) --make="$(MAKE)" $(INSTRUBY_ARGS) --install=arch
post-install-arch:: post-install-bin post-install-ext-arch

install-comm: pre-install-comm do-install-comm post-install-comm
pre-install-comm:: pre-install-lib pre-install-ext-comm pre-install-man
do-install-comm: $(PREP) pre-install-comm
	$(INSTRUBY) --make="$(MAKE)" $(INSTRUBY_ARGS) --install=lib --install=ext-comm --install=man
post-install-comm:: post-install-lib post-install-ext-comm post-install-man

install-bin: pre-install-bin do-install-bin post-install-bin
pre-install-bin:: install-prereq
do-install-bin: $(PROGRAM) pre-install-bin
	$(INSTRUBY) --make="$(MAKE)" $(INSTRUBY_ARGS) --install=bin
post-install-bin::
	@$(NULLCMD)

install-lib: pre-install-lib do-install-lib post-install-lib
pre-install-lib:: install-prereq
do-install-lib: $(PREP) pre-install-lib
	$(INSTRUBY) --make="$(MAKE)" $(INSTRUBY_ARGS) --install=lib
post-install-lib::
	@$(NULLCMD)

install-ext-comm: pre-install-ext-comm do-install-ext-comm post-install-ext-comm
pre-install-ext-comm:: install-prereq
do-install-ext-comm: exts pre-install-ext-comm
	$(INSTRUBY) --make="$(MAKE)" $(INSTRUBY_ARGS) --install=ext-comm
post-install-ext-comm::
	@$(NULLCMD)

install-ext-arch: pre-install-ext-arch do-install-ext-arch post-install-ext-arch
pre-install-ext-arch:: install-prereq
do-install-ext-arch: exts pre-install-ext-arch
	$(INSTRUBY) --make="$(MAKE)" $(INSTRUBY_ARGS) --install=ext-arch
post-install-ext-arch::
	@$(NULLCMD)

install-man: pre-install-man do-install-man post-install-man
pre-install-man:: install-prereq
do-install-man: $(PREP) pre-install-man
	$(INSTRUBY) --make="$(MAKE)" $(INSTRUBY_ARGS) --install=man
post-install-man::
	@$(NULLCMD)

install-capi: capi pre-install-capi do-install-capi post-install-capi
pre-install-capi:: install-prereq
do-install-capi: $(PREP) pre-install-capi
	$(INSTRUBY) --make="$(MAKE)" $(INSTRUBY_ARGS) --install=capi
post-install-capi::
	@$(NULLCMD)

what-where: no-install
no-install: no-install-$(INSTALLDOC)
what-where-all: no-install-all
no-install-all: pre-no-install-all dont-install-all post-no-install-all
pre-no-install-all:: pre-no-install-local pre-no-install-ext pre-no-install-doc
dont-install-all: $(PROGRAM)
	$(INSTRUBY) -n --make="$(MAKE)" $(INSTRUBY_ARGS) --install=all --rdoc-output="$(RDOCOUT)"
post-no-install-all:: post-no-install-local post-no-install-ext post-no-install-doc
	@$(NULLCMD)

uninstall: $(INSTALLED_LIST) sudo-precheck
	$(Q)$(SUDO) $(MINIRUBY) $(srcdir)/tool/rbuninstall.rb --destdir=$(DESTDIR) $(INSTALLED_LIST)

reinstall: all uninstall install

what-where-nodoc: no-install-nodoc
no-install-nodoc: pre-no-install-nodoc dont-install-nodoc post-no-install-nodoc
pre-no-install-nodoc:: pre-no-install-local pre-no-install-ext
dont-install-nodoc:  $(PREP)
	$(INSTRUBY) -n --make="$(MAKE)" $(INSTRUBY_ARGS)
post-no-install-nodoc:: post-no-install-local post-no-install-ext

what-where-local: no-install-local
no-install-local: pre-no-install-local dont-install-local post-no-install-local
pre-no-install-local:: pre-no-install-bin pre-no-install-lib pre-no-install-man
dont-install-local: $(PREP)
	$(INSTRUBY) -n --make="$(MAKE)" $(INSTRUBY_ARGS) --install=local
post-no-install-local:: post-no-install-bin post-no-install-lib post-no-install-man

what-where-ext: no-install-ext
no-install-ext: pre-no-install-ext dont-install-ext post-no-install-ext
pre-no-install-ext:: pre-no-install-ext-arch pre-no-install-ext-comm
dont-install-ext: $(PREP)
	$(INSTRUBY) -n --make="$(MAKE)" $(INSTRUBY_ARGS) --install=ext
post-no-install-ext:: post-no-install-ext-arch post-no-install-ext-comm

what-where-arch: no-install-arch
no-install-arch: pre-no-install-arch dont-install-arch post-no-install-arch
pre-no-install-arch:: pre-no-install-bin pre-no-install-ext-arch
dont-install-arch: $(PREP)
	$(INSTRUBY) -n --make="$(MAKE)" $(INSTRUBY_ARGS) --install=bin --install=ext-arch
post-no-install-arch:: post-no-install-lib post-no-install-man post-no-install-ext-arch

what-where-comm: no-install-comm
no-install-comm: pre-no-install-comm dont-install-comm post-no-install-comm
pre-no-install-comm:: pre-no-install-lib pre-no-install-ext-comm pre-no-install-man
dont-install-comm: $(PREP)
	$(INSTRUBY) -n --make="$(MAKE)" $(INSTRUBY_ARGS) --install=lib --install=ext-comm --install=man
post-no-install-comm:: post-no-install-lib post-no-install-ext-comm post-no-install-man

what-where-bin: no-install-bin
no-install-bin: pre-no-install-bin dont-install-bin post-no-install-bin
pre-no-install-bin:: install-prereq
dont-install-bin: $(PREP)
	$(INSTRUBY) -n --make="$(MAKE)" $(INSTRUBY_ARGS) --install=bin
post-no-install-bin::
	@$(NULLCMD)

what-where-lib: no-install-lib
no-install-lib: pre-no-install-lib dont-install-lib post-no-install-lib
pre-no-install-lib:: install-prereq
dont-install-lib: $(PREP)
	$(INSTRUBY) -n --make="$(MAKE)" $(INSTRUBY_ARGS) --install=lib
post-no-install-lib::
	@$(NULLCMD)

what-where-ext-comm: no-install-ext-comm
no-install-ext-comm: pre-no-install-ext-comm dont-install-ext-comm post-no-install-ext-comm
pre-no-install-ext-comm:: install-prereq
dont-install-ext-comm: $(PREP)
	$(INSTRUBY) -n --make="$(MAKE)" $(INSTRUBY_ARGS) --install=ext-comm
post-no-install-ext-comm::
	@$(NULLCMD)

what-where-ext-arch: no-install-ext-arch
no-install-ext-arch: pre-no-install-ext-arch dont-install-ext-arch post-no-install-ext-arch
pre-no-install-ext-arch:: install-prereq
dont-install-ext-arch: $(PREP)
	$(INSTRUBY) -n --make="$(MAKE)" $(INSTRUBY_ARGS) --install=ext-arch
post-no-install-ext-arch::
	@$(NULLCMD)

what-where-man: no-install-man
no-install-man: pre-no-install-man dont-install-man post-no-install-man
pre-no-install-man:: install-prereq
dont-install-man: $(PREP)
	$(INSTRUBY) -n --make="$(MAKE)" $(INSTRUBY_ARGS) --install=man
post-no-install-man::
	@$(NULLCMD)

install-doc: rdoc pre-install-doc do-install-doc post-install-doc
pre-install-doc:: install-prereq
do-install-doc: $(PROGRAM) pre-install-doc
	$(INSTRUBY) --make="$(MAKE)" $(INSTRUBY_ARGS) --install=rdoc --rdoc-output="$(RDOCOUT)"
post-install-doc::
	@$(NULLCMD)

install-gem: pre-install-gem do-install-gem post-install-gem
pre-install-gem:: pre-install-bin pre-install-lib pre-install-man
do-install-gem: $(PROGRAM) pre-install-gem
	$(INSTRUBY) --make="$(MAKE)" $(INSTRUBY_ARGS) --install=gem
post-install-gem::
	@$(NULLCMD)

rdoc: PHONY main
	@echo Generating RDoc documentation
	$(Q) $(XRUBY) "$(srcdir)/bin/rdoc" --root "$(srcdir)" --page-dir "$(srcdir)/doc" --encoding=UTF-8 --no-force-update --all --ri --op "$(RDOCOUT)" --debug $(RDOCFLAGS) "$(srcdir)"

rdoc-coverage: PHONY main
	@echo Generating RDoc coverage report
	$(Q) $(XRUBY) "$(srcdir)/bin/rdoc" --root "$(srcdir)" --encoding=UTF-8 --all --quiet -C $(RDOCFLAGS) "$(srcdir)"

RDOCBENCHOUT=/tmp/rdocbench

GCBENCH_ITEM=null

gcbench: PHONY
	$(Q) $(XRUBY) "$(srcdir)/benchmark/gc/gcbench.rb" $(GCBENCH_ITEM)

gcbench-rdoc: PHONY
	$(Q) $(XRUBY) "$(srcdir)/benchmark/gc/gcbench.rb" rdoc

nodoc: PHONY

what-where-doc: no-install-doc
no-install-doc: pre-no-install-doc dont-install-doc post-no-install-doc
pre-no-install-doc:: install-prereq
dont-install-doc:: $(PREP)
	$(INSTRUBY) -n --make="$(MAKE)" $(INSTRUBY_ARGS) --install=rdoc --rdoc-output="$(RDOCOUT)"
post-no-install-doc::
	@$(NULLCMD)

CLEAR_INSTALLED_LIST = clear-installed-list

install-prereq: $(CLEAR_INSTALLED_LIST) yes-fake sudo-precheck PHONY

clear-installed-list: PHONY
	@> $(INSTALLED_LIST) set MAKE="$(MAKE)"

clean: clean-ext clean-local clean-enc clean-golf clean-rdoc clean-capi clean-extout clean-platform
clean-local:: clean-runnable
	$(Q)$(RM) $(OBJS) $(MINIOBJS) $(MAINOBJ) $(LIBRUBY_A) $(LIBRUBY_SO) $(LIBRUBY) $(LIBRUBY_ALIASES)
	$(Q)$(RM) $(PROGRAM) $(WPROGRAM) miniruby$(EXEEXT) dmyext.$(OBJEXT) $(ARCHFILE) .*.time
	$(Q)$(RM) y.tab.c y.output encdb.h transdb.h prelude.c config.log rbconfig.rb $(ruby_pc) probes.h probes.$(OBJEXT) probes.stamp ruby-glommed.$(OBJEXT)
	$(Q)$(RM) GNUmakefile.old Makefile.old $(arch)-fake.rb
clean-runnable:: PHONY
	$(Q)$(CHDIR) bin 2>$(NULL) && $(RM) $(PROGRAM) $(WPROGRAM) $(GORUBY)$(EXEEXT) bin/*.$(DLEXT) 2>$(NULL) || exit 0
	$(Q)$(CHDIR) lib 2>$(NULL) && $(RM) $(LIBRUBY_A) $(LIBRUBY) $(LIBRUBY_ALIASES) $(RUBY_BASE_NAME)/$(RUBY_PROGRAM_VERSION) $(RUBY_BASE_NAME)/vendor_ruby 2>$(NULL) || exit 0
	$(Q)$(RMDIR) lib/$(RUBY_BASE_NAME) lib bin 2>$(NULL) || exit 0
clean-ext:: PHONY
clean-golf: PHONY
	$(Q)$(RM) $(GORUBY)$(EXEEXT) $(GOLFOBJS)
clean-rdoc: PHONY
clean-capi: PHONY
clean-platform: PHONY
clean-extout: PHONY
	-$(Q)$(RMDIR) $(EXTOUT)/$(arch) $(EXTOUT) 2> $(NULL) || exit 0
clean-docs: clean-rdoc clean-capi

distclean: distclean-ext distclean-local distclean-enc distclean-golf distclean-extout distclean-platform
distclean-local:: clean-local
	$(Q)$(RM) $(MKFILES) yasmdata.rb *.inc
	$(Q)$(RM) config.cache config.status config.status.lineno
	$(Q)$(RM) *~ *.bak *.stackdump core *.core gmon.out $(PREP)
distclean-ext:: PHONY
distclean-golf: clean-golf
	$(Q)$(RM) $(GOLFPRELUDES)
distclean-rdoc: PHONY
distclean-capi: PHONY
distclean-extout: clean-extout
distclean-platform: clean-platform

realclean:: realclean-ext realclean-local realclean-enc realclean-golf realclean-extout
realclean-local:: distclean-local
	$(Q)$(RM) parse.c parse.h lex.c newline.c miniprelude.c revision.h
realclean-ext:: PHONY
realclean-golf: distclean-golf
realclean-capi: PHONY
realclean-extout: distclean-extout

clean-ext distclean-ext realclean-ext::
	$(Q)$(RM) $(EXTS_MK)
	$(Q)$(RM) $(EXTOUT)/.timestamp/.*.time
	$(Q)$(RMDIR) $(EXTOUT)/.timestamp 2> $(NULL) || exit 0

clean-enc distclean-enc realclean-enc: PHONY

clean-rdoc distclean-rdoc realclean-rdoc:
	@echo $(@:-rdoc=ing) rdoc
	$(Q)$(RMALL) $(RDOCOUT)

clean-capi distclean-capi realclean-capi:
	@echo $(@:-capi=ing) capi
	$(Q)$(RMALL) $(CAPIOUT)

clean-platform:
	$(Q) $(RM) $(PLATFORM_D)
	-$(Q) $(RMDIR) $(PLATFORM_DIR) 2> $(NULL) || exit 0

check: main test test-all
	$(ECHO) check succeeded
check-ruby: test test-ruby

fake: $(CROSS_COMPILING)-fake
yes-fake: $(arch)-fake.rb $(RBCONFIG) PHONY
no-fake: PHONY

btest: $(TEST_RUNNABLE)-btest
no-btest: PHONY
yes-btest: fake miniruby$(EXEEXT) PHONY
	$(BOOTSTRAPRUBY) "$(srcdir)/bootstraptest/runner.rb" --ruby="$(BTESTRUBY) $(RUN_OPTS)" $(OPTS) $(TESTOPTS)

btest-ruby: $(TEST_RUNNABLE)-btest-ruby
no-btest-ruby: PHONY
yes-btest-ruby: prog PHONY
	$(Q)$(RUNRUBY) "$(srcdir)/bootstraptest/runner.rb" --ruby="$(PROGRAM) -I$(srcdir)/lib $(RUN_OPTS)" -q $(OPTS) $(TESTOPTS)

test-sample: $(TEST_RUNNABLE)-test-sample
no-test-sample: PHONY
yes-test-sample: prog PHONY
	$(Q)$(RUNRUBY) $(srcdir)/tool/rubytest.rb --run-opt=$(RUN_OPTS) $(OPTS) $(TESTOPTS)

test-knownbugs: test-knownbug
test-knownbug: $(TEST_RUNNABLE)-test-knownbug
no-test-knownbug: PHONY
yes-test-knownbug: prog PHONY
	-$(RUNRUBY) "$(srcdir)/bootstraptest/runner.rb" --ruby="$(PROGRAM) $(RUN_OPTS)" $(OPTS) $(TESTOPTS) $(srcdir)/KNOWNBUGS.rb

test: test-sample btest-ruby test-knownbug

test-all: $(TEST_RUNNABLE)-test-all
yes-test-all: prog PHONY
	$(RUNRUBY) "$(srcdir)/test/runner.rb" --ruby="$(RUNRUBY)" $(TESTOPTS) $(TESTS)
TESTS_BUILD = mkmf
no-test-all: PHONY
	$(MINIRUBY) -I"$(srcdir)/lib" "$(srcdir)/test/runner.rb" $(TESTOPTS) $(TESTS_BUILD)

test-ruby: $(TEST_RUNNABLE)-test-ruby
no-test-ruby: PHONY
yes-test-ruby: prog encs PHONY
	$(RUNRUBY) "$(srcdir)/test/runner.rb" -q $(TESTOPTS) -- ruby -ext-

extconf: $(PREP)
	$(Q) $(MAKEDIRS) "$(EXTCONFDIR)"
	$(RUNRUBY) -C "$(EXTCONFDIR)" $(EXTCONF) $(EXTCONFARGS)

$(RBCONFIG): $(srcdir)/tool/mkconfig.rb config.status $(srcdir)/version.h $(PREP)
	$(Q)$(MINIRUBY) $(srcdir)/tool/mkconfig.rb -timestamp=$@ \
		-install_name=$(RUBY_INSTALL_NAME) \
		-so_name=$(RUBY_SO_NAME) rbconfig.rb

test-rubyspec-precheck:

test-rubyspec: test-rubyspec-precheck
	$(RUNRUBY) $(srcdir)/spec/mspec/bin/mspec run -B $(srcdir)/spec/default.mspec $(MSPECOPT)

RUNNABLE = $(LIBRUBY_RELATIVE:no=un)-runnable
runnable: $(RUNNABLE) prog $(srcdir)/tool/mkrunnable.rb PHONY
	$(Q) $(MINIRUBY) $(srcdir)/tool/mkrunnable.rb -v $(EXTOUT)
yes-runnable: PHONY

encs: enc trans
libencs: libenc libtrans
encs enc trans libencs libenc libtrans: showflags $(ENC_MK) $(LIBRUBY) $(PREP) PHONY
	$(ECHO) making $@
	$(Q) $(MAKE) -f $(ENC_MK) V="$(V)" \
		RUBY="$(MINIRUBY)" MINIRUBY="$(MINIRUBY)" \
		$(MFLAGS) $@


libenc enc: {$(VPATH)}encdb.h
libtrans trans: {$(VPATH)}transdb.h

$(ENC_MK): $(srcdir)/enc/make_encmake.rb $(srcdir)/enc/Makefile.in $(srcdir)/enc/depend \
	$(srcdir)/enc/encinit.c.erb $(srcdir)/lib/mkmf.rb $(RBCONFIG)
	$(ECHO) generating $@
	$(Q) $(MINIRUBY) $(srcdir)/enc/make_encmake.rb --builtin-encs="$(BUILTIN_ENCOBJS)" --builtin-transes="$(BUILTIN_TRANSOBJS)" --module$(ENCSTATIC) $@ $(ENCS)

.PRECIOUS: $(MKFILES)

.PHONY: PHONY all fake prereq incs srcs preludes help
.PHONY: test install install-nodoc install-doc dist
.PHONY: loadpath golf capi rdoc install-prereq clear-installed-list
.PHONY: clean clean-ext clean-local clean-enc clean-golf clean-rdoc clean-extout
.PHONY: distclean distclean-ext distclean-local distclean-enc distclean-golf distclean-extout
.PHONY: realclean realclean-ext realclean-local realclean-enc realclean-golf realclean-extout
.PHONY: check test test-all btest btest-ruby test-sample test-knownbug
.PHONY: run runruby parse benchmark benchmark-each tbench gdb gdb-ruby
.PHONY: update-mspec update-rubyspec test-rubyspec

PHONY:

{$(VPATH)}parse.c: {$(VPATH)}parse.y $(srcdir)/tool/ytab.sed {$(VPATH)}id.h
{$(VPATH)}parse.h: {$(VPATH)}parse.c

{$(srcdir)}.y.c:
	$(ECHO) generating $@
	$(Q)$(BASERUBY) $(srcdir)/tool/id2token.rb --path-separator=.$(PATH_SEPARATOR)./ --vpath=$(VPATH) id.h $(SRC_FILE) > parse.tmp.y
	$(Q)$(YACC) -d $(YFLAGS) -o y.tab.c parse.tmp.y
	$(Q)$(RM) parse.tmp.y
	$(Q)sed -f $(srcdir)/tool/ytab.sed -e "/^#/s!parse\.tmp\.[iy]!parse.y!" -e "/^#/s!y\.tab\.c!$@!" y.tab.c > $@.new
	$(Q)$(MV) $@.new $@
	$(Q)sed -e "/^#line.*y\.tab\.h/d;/^#line.*parse.*\.y/d" y.tab.h > $(@:.c=.h)
	$(Q)$(RM) y.tab.c y.tab.h

$(PLATFORM_D):
	$(Q) $(MAKEDIRS) $(PLATFORM_DIR)
	@exit > $@

###
CCAN_DIR = {$(VPATH)}ccan
CCAN_LIST_INCLUDES = $(CCAN_DIR)/build_assert/build_assert.h \
			$(CCAN_DIR)/check_type/check_type.h \
			$(CCAN_DIR)/container_of/container_of.h \
			$(CCAN_DIR)/list/list.h \
			$(CCAN_DIR)/str/str.h

RUBY_H_INCLUDES    = {$(VPATH)}ruby.h {$(VPATH)}config.h {$(VPATH)}defines.h \
		     {$(VPATH)}intern.h {$(VPATH)}missing.h {$(VPATH)}st.h \
		     {$(VPATH)}subst.h
ENCODING_H_INCLUDES= {$(VPATH)}encoding.h {$(VPATH)}oniguruma.h
PROBES_H_INCLUDES  = {$(VPATH)}probes.h
VM_CORE_H_INCLUDES = {$(VPATH)}vm_core.h {$(VPATH)}thread_$(THREAD_MODEL).h \
		     {$(VPATH)}node.h {$(VPATH)}method.h {$(VPATH)}ruby_atomic.h \
	             {$(VPATH)}vm_debug.h {$(VPATH)}id.h {$(VPATH)}thread_native.h \
	             $(CCAN_LIST_INCLUDES)

###

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
setproctitle.$(OBJEXT): {$(VPATH)}setproctitle.c
strchr.$(OBJEXT): {$(VPATH)}strchr.c
strdup.$(OBJEXT): {$(VPATH)}strdup.c
strerror.$(OBJEXT): {$(VPATH)}strerror.c
strlcat.$(OBJEXT): {$(VPATH)}strlcat.c
strlcpy.$(OBJEXT): {$(VPATH)}strlcpy.c
strstr.$(OBJEXT): {$(VPATH)}strstr.c
strtod.$(OBJEXT): {$(VPATH)}strtod.c
strtol.$(OBJEXT): {$(VPATH)}strtol.c
nt.$(OBJEXT): {$(VPATH)}nt.c
os2.$(OBJEXT): {$(VPATH)}os2.c
dl_os2.$(OBJEXT): {$(VPATH)}dl_os2.c
ia64.$(OBJEXT): {$(VPATH)}ia64.s
	$(CC) $(CFLAGS) -c $<

###

addr2line.$(OBJEXT): {$(VPATH)}addr2line.c
array.$(OBJEXT): {$(VPATH)}array.c
bignum.$(OBJEXT): {$(VPATH)}bignum.c
class.$(OBJEXT): {$(VPATH)}class.c
compar.$(OBJEXT): {$(VPATH)}compar.c
complex.$(OBJEXT): {$(VPATH)}complex.c
dir.$(OBJEXT): {$(VPATH)}dir.c
dln.$(OBJEXT): {$(VPATH)}dln.c
dln_find.$(OBJEXT): {$(VPATH)}dln_find.c
dmydln.$(OBJEXT): {$(VPATH)}dmydln.c
dmyext.$(OBJEXT): {$(VPATH)}dmyext.c
encoding.$(OBJEXT): {$(VPATH)}encoding.c
enum.$(OBJEXT): {$(VPATH)}enum.c
enumerator.$(OBJEXT): {$(VPATH)}enumerator.c
error.$(OBJEXT): {$(VPATH)}error.c
eval.$(OBJEXT): {$(VPATH)}eval.c
load.$(OBJEXT): {$(VPATH)}load.c
file.$(OBJEXT): {$(VPATH)}file.c
gc.$(OBJEXT): {$(VPATH)}gc.c
hash.$(OBJEXT): {$(VPATH)}hash.c
inits.$(OBJEXT): {$(VPATH)}inits.c
io.$(OBJEXT): {$(VPATH)}io.c
main.$(OBJEXT): {$(VPATH)}main.c
marshal.$(OBJEXT): {$(VPATH)}marshal.c
math.$(OBJEXT): {$(VPATH)}math.c
node.$(OBJEXT): {$(VPATH)}node.c
numeric.$(OBJEXT): {$(VPATH)}numeric.c
object.$(OBJEXT): {$(VPATH)}object.c
pack.$(OBJEXT): {$(VPATH)}pack.c
parse.$(OBJEXT): {$(VPATH)}parse.c
proc.$(OBJEXT): {$(VPATH)}proc.c
process.$(OBJEXT): {$(VPATH)}process.c
random.$(OBJEXT): {$(VPATH)}random.c
range.$(OBJEXT): {$(VPATH)}range.c
rational.$(OBJEXT): {$(VPATH)}rational.c
re.$(OBJEXT): {$(VPATH)}re.c
regcomp.$(OBJEXT): {$(VPATH)}regcomp.c
regenc.$(OBJEXT): {$(VPATH)}regenc.c
regerror.$(OBJEXT): {$(VPATH)}regerror.c
regexec.$(OBJEXT): {$(VPATH)}regexec.c
regparse.$(OBJEXT): {$(VPATH)}regparse.c
regsyntax.$(OBJEXT): {$(VPATH)}regsyntax.c
ruby.$(OBJEXT): {$(VPATH)}ruby.c
safe.$(OBJEXT): {$(VPATH)}safe.c
signal.$(OBJEXT): {$(VPATH)}signal.c
sprintf.$(OBJEXT): {$(VPATH)}sprintf.c
st.$(OBJEXT): {$(VPATH)}st.c
strftime.$(OBJEXT): {$(VPATH)}strftime.c
string.$(OBJEXT): {$(VPATH)}string.c
struct.$(OBJEXT): {$(VPATH)}struct.c
symbol.$(OBJEXT): {$(VPATH)}symbol.c
thread.$(OBJEXT): {$(VPATH)}thread.c
transcode.$(OBJEXT): {$(VPATH)}transcode.c
cont.$(OBJEXT): {$(VPATH)}cont.c
time.$(OBJEXT): {$(VPATH)}time.c
util.$(OBJEXT): {$(VPATH)}util.c
variable.$(OBJEXT): {$(VPATH)}variable.c
version.$(OBJEXT): {$(VPATH)}version.c
loadpath.$(OBJEXT): {$(VPATH)}loadpath.c
localeinit.$(OBJEXT): {$(VPATH)}localeinit.c
miniinit.$(OBJEXT): {$(VPATH)}miniinit.c

compile.$(OBJEXT): {$(VPATH)}compile.c {$(VPATH)}opt_sc.inc {$(VPATH)}optunifs.inc
iseq.$(OBJEXT): {$(VPATH)}iseq.c
vm.$(OBJEXT): {$(VPATH)}vm.c
vm_dump.$(OBJEXT): {$(VPATH)}vm_dump.c
debug.$(OBJEXT): {$(VPATH)}debug.c
id.$(OBJEXT): {$(VPATH)}id.c
vm_backtrace.$(OBJEXT): {$(VPATH)}vm_backtrace.c
vm_trace.$(OBJEXT): {$(VPATH)}vm_trace.c
miniprelude.$(OBJEXT): {$(VPATH)}miniprelude.c
prelude.$(OBJEXT): {$(VPATH)}prelude.c
golf_prelude.$(OBJEXT): {$(VPATH)}golf_prelude.c
goruby.$(OBJEXT): {$(VPATH)}goruby.c

ascii.$(OBJEXT): {$(VPATH)}ascii.c
us_ascii.$(OBJEXT): {$(VPATH)}us_ascii.c
unicode.$(OBJEXT): {$(VPATH)}unicode.c
utf_8.$(OBJEXT): {$(VPATH)}utf_8.c

win32/win32.$(OBJEXT): {$(VPATH)}win32/win32.c {$(VPATH)}dln.h {$(VPATH)}dln_find.c \
  {$(VPATH)}internal.h $(RUBY_H_INCLUDES) $(PLATFORM_D)
win32/file.$(OBJEXT): {$(VPATH)}win32/file.c $(RUBY_H_INCLUDES) $(PLATFORM_D)

$(NEWLINE_C): $(srcdir)/enc/trans/newline.trans $(srcdir)/tool/transcode-tblgen.rb
	$(Q) $(BASERUBY) "$(srcdir)/tool/transcode-tblgen.rb" -vo $@ $(srcdir)/enc/trans/newline.trans
newline.$(OBJEXT): $(NEWLINE_C)

verconf.h: $(srcdir)/template/verconf.h.tmpl $(srcdir)/tool/generic_erb.rb $(RBCONFIG)
	$(ECHO) creating $@
	$(Q) $(MINIRUBY) "$(srcdir)/tool/generic_erb.rb" $(srcdir)/template/verconf.h.tmpl > $@

DTRACE_DEPENDENT_OBJS = array.$(OBJEXT) \
		eval.$(OBJEXT) \
		gc.$(OBJEXT) \
		hash.$(OBJEXT) \
		load.$(OBJEXT) \
		object.$(OBJEXT) \
		parse.$(OBJEXT) \
		string.$(OBJEXT) \
		symbol.$(OBJEXT) \
		vm.$(OBJEXT)

probes.$(OBJEXT): $(DTRACE_DEPENDENT_OBJS)
ruby-glommed.$(OBJEXT): $(OBJS) $(DTRACE_OBJ)

$(OBJS):  {$(VPATH)}config.h {$(VPATH)}missing.h

INSNS2VMOPT = --srcdir="$(srcdir)"

{$(VPATH)}minsns.inc: $(srcdir)/template/minsns.inc.tmpl

{$(VPATH)}opt_sc.inc: $(srcdir)/template/opt_sc.inc.tmpl

{$(VPATH)}optinsn.inc: $(srcdir)/template/optinsn.inc.tmpl

{$(VPATH)}optunifs.inc: $(srcdir)/template/optunifs.inc.tmpl

{$(VPATH)}insns.inc: $(srcdir)/template/insns.inc.tmpl

{$(VPATH)}insns_info.inc: $(srcdir)/template/insns_info.inc.tmpl

{$(VPATH)}vmtc.inc: $(srcdir)/template/vmtc.inc.tmpl

{$(VPATH)}vm.inc: $(srcdir)/template/vm.inc.tmpl

common-srcs: {$(VPATH)}parse.c {$(VPATH)}lex.c {$(VPATH)}newline.c {$(VPATH)}id.c \
	     srcs-lib srcs-ext

srcs: common-srcs srcs-enc

EXT_SRCS = $(srcdir)/ext/ripper/ripper.c $(srcdir)/ext/json/parser/parser.c \
	   $(srcdir)/ext/rbconfig/sizeof/sizes.c

srcs-ext: $(EXT_SRCS)

LIB_SRCS = $(srcdir)/lib/unicode_normalize/tables.rb

srcs-lib: $(LIB_SRCS)

srcs-enc: $(ENC_MK)
	$(ECHO) making srcs under enc
	$(Q) $(MAKE) -f $(ENC_MK) RUBY="$(MINIRUBY)" MINIRUBY="$(MINIRUBY)" $(MFLAGS) srcs

all-incs: incs
incs: $(INSNS) {$(VPATH)}node_name.inc {$(VPATH)}encdb.h {$(VPATH)}transdb.h {$(VPATH)}known_errors.inc \
      $(srcdir)/revision.h $(REVISION_H) enc/unicode/name2ctype.h enc/jis/props.h \
      {$(VPATH)}id.h {$(VPATH)}probes.dmyh

insns: $(INSNS)

id.h: $(srcdir)/tool/generic_erb.rb $(srcdir)/template/id.h.tmpl $(srcdir)/defs/id.def
	$(ECHO) generating $@
	$(Q) $(BASERUBY) $(srcdir)/tool/generic_erb.rb --output=$@ \
		$(srcdir)/template/id.h.tmpl

id.c: $(srcdir)/tool/generic_erb.rb $(srcdir)/template/id.c.tmpl $(srcdir)/defs/id.def
	$(ECHO) generating $@
	$(Q) $(BASERUBY) $(srcdir)/tool/generic_erb.rb --output=$@ \
		$(srcdir)/template/id.c.tmpl

node_name.inc: {$(VPATH)}node.h
	$(ECHO) generating $@
	$(Q) $(BASERUBY) -n $(srcdir)/tool/node_name.rb < $? > $@

encdb.h: $(PREP) $(srcdir)/tool/generic_erb.rb $(srcdir)/template/encdb.h.tmpl
	$(ECHO) generating $@
	$(Q) $(MINIRUBY) $(srcdir)/tool/generic_erb.rb -c -o $@ $(srcdir)/template/encdb.h.tmpl $(srcdir)/enc enc

transdb.h: $(PREP) srcs-enc $(srcdir)/tool/generic_erb.rb $(srcdir)/template/transdb.h.tmpl
	$(ECHO) generating $@
	$(Q) $(MINIRUBY) $(srcdir)/tool/generic_erb.rb -c -o $@ $(srcdir)/template/transdb.h.tmpl $(srcdir)/enc/trans enc/trans

enc/encinit.c: $(ENC_MK) $(srcdir)/enc/encinit.c.erb

known_errors.inc: $(srcdir)/template/known_errors.inc.tmpl $(srcdir)/defs/known_errors.def
	$(ECHO) generating $@
	$(Q) $(BASERUBY) $(srcdir)/tool/generic_erb.rb -c -o $@ $(srcdir)/template/known_errors.inc.tmpl $(srcdir)/defs/known_errors.def

$(MINIPRELUDE_C): $(COMPILE_PRELUDE) {$(srcdir)}prelude.rb
	$(ECHO) generating $@
	$(Q) $(BASERUBY) $(srcdir)/tool/generic_erb.rb -I$(srcdir) -o $@ \
		$(srcdir)/template/prelude.c.tmpl prelude.rb

$(PRELUDE_C): $(COMPILE_PRELUDE) $(RBCONFIG) \
	   {$(srcdir)}lib/rubygems/defaults.rb \
	   {$(srcdir)}lib/rubygems/core_ext/kernel_gem.rb \
	   $(PRELUDE_SCRIPTS) $(PREP) $(LIB_SRCS)
	$(ECHO) generating $@
	$(Q) $(MINIRUBY) $(srcdir)/tool/generic_erb.rb -I$(srcdir) -c -o $@ \
		$(srcdir)/template/prelude.c.tmpl $(PRELUDE_SCRIPTS)

{$(VPATH)}golf_prelude.c: $(COMPILE_PRELUDE) $(RBCONFIG) {$(srcdir)}golf_prelude.rb $(PREP)
	$(ECHO) generating $@
	$(Q) $(MINIRUBY) $(srcdir)/tool/generic_erb.rb -I$(srcdir) -c -o $@ \
		$(srcdir)/template/prelude.c.tmpl golf_prelude.rb

probes.dmyh: {$(srcdir)}probes.d $(srcdir)/tool/gen_dummy_probes.rb
	$(BASERUBY) $(srcdir)/tool/gen_dummy_probes.rb $(srcdir)/probes.d > $@

probes.h: {$(VPATH)}probes.$(DTRACE_EXT)

prereq: incs srcs preludes PHONY

preludes: {$(VPATH)}prelude.c
preludes: {$(VPATH)}miniprelude.c
preludes: {$(srcdir)}golf_prelude.c

$(srcdir)/revision.h:
	@exit > $@

$(REVISION_H): $(srcdir)/version.h $(srcdir)/ChangeLog $(srcdir)/tool/file2lastrev.rb $(REVISION_FORCE)
	-$(Q) $(BASERUBY) $(srcdir)/tool/file2lastrev.rb --revision.h "$(srcdir)" > revision.tmp
	$(Q)$(IFCHANGE) "--timestamp=$@" "$(srcdir)/revision.h" revision.tmp

$(srcdir)/ext/ripper/ripper.c: parse.y id.h
	$(ECHO) generating $@
	$(Q) $(CHDIR) $(@D) && $(exec) $(MAKE) -f depend $(MFLAGS) \
		Q=$(Q) ECHO=$(ECHO) top_srcdir=../.. srcdir=. VPATH=../.. RUBY="$(BASERUBY)" PATH_SEPARATOR="$(PATH_SEPARATOR)"

$(srcdir)/ext/json/parser/parser.c: $(srcdir)/ext/json/parser/parser.rl
	$(ECHO) generating $@
	$(Q) $(CHDIR) $(@D) && $(exec) $(MAKE) -f prereq.mk $(MFLAGS) \
		Q=$(Q) ECHO=$(ECHO) top_srcdir=../../.. srcdir=. VPATH=../../.. BASERUBY="$(BASERUBY)"

$(srcdir)/ext/rbconfig/sizeof/sizes.c: $(srcdir)/ext/rbconfig/sizeof/depend \
		$(srcdir)/tool/generic_erb.rb $(srcdir)/template/sizes.c.tmpl $(srcdir)/configure.in
	$(ECHO) generating $@
	$(Q) $(CHDIR) $(@D) && $(exec) $(MAKE) -f depend $(MFLAGS) \
		Q=$(Q) ECHO=$(ECHO) top_srcdir=../../.. srcdir=. VPATH=../../.. RUBY="$(BASERUBY)"

##

run: fake miniruby$(EXEEXT) PHONY
	$(BTESTRUBY) $(TESTRUN_SCRIPT) $(RUNOPT)

runruby: $(PROGRAM) PHONY
	$(RUNRUBY) $(TESTRUN_SCRIPT)

parse: fake miniruby$(EXEEXT) PHONY
	$(BTESTRUBY) $(srcdir)/tool/parse.rb $(TESTRUN_SCRIPT)

bisect: PHONY
	$(srcdir)/tool/bisect.sh miniruby $(srcdir)

bisect-ruby: PHONY
	$(srcdir)/tool/bisect.sh ruby $(srcdir)

COMPARE_RUBY = $(BASERUBY)
ITEM =
OPTS =

benchmark: $(PROGRAM) PHONY
	$(BASERUBY) $(srcdir)/benchmark/driver.rb -v \
	            --executables="$(COMPARE_RUBY); built-ruby::$(RUNRUBY)" \
	            --pattern='bm_' --directory=$(srcdir)/benchmark $(OPTS)

benchmark-each: $(PROGRAM) PHONY
	$(BASERUBY) $(srcdir)/benchmark/driver.rb -v \
	            --executables="$(COMPARE_RUBY); built-ruby::$(RUNRUBY)" \
	            --pattern=$(ITEM) --directory=$(srcdir)/benchmark $(OPTS)

tbench: $(PROGRAM) PHONY
	$(BASERUBY) $(srcdir)/benchmark/driver.rb -v \
	            --executables="$(COMPARE_RUBY); built-ruby::$(RUNRUBY)" \
	            --pattern='bmx_' --directory=$(srcdir)/benchmark $(OPTS)

run.gdb:
	echo set breakpoint pending on         > run.gdb
	echo b ruby_debug_breakpoint          >> run.gdb
	echo '# handle SIGINT nostop'         >> run.gdb
	echo '# handle SIGPIPE nostop'        >> run.gdb
	echo '# b rb_longjmp'                 >> run.gdb
	echo source $(srcdir)/breakpoints.gdb >> run.gdb
	echo source $(srcdir)/.gdbinit        >> run.gdb
	echo 'set $$_exitcode = -999'         >> run.gdb
	echo run                              >> run.gdb
	echo 'if $$_exitcode != -999'         >> run.gdb
	echo '  quit'                         >> run.gdb
	echo end                              >> run.gdb


gdb: miniruby$(EXEEXT) run.gdb PHONY
	gdb -x run.gdb --quiet --args $(MINIRUBY) $(TESTRUN_SCRIPT)

gdb-ruby: $(PROGRAM) run.gdb PHONY
	$(Q) $(RUNRUBY_COMMAND) $(RUNRUBY_DEBUGGER) -- $(TESTRUN_SCRIPT)

dist:
	$(BASERUBY) $(srcdir)/tool/make-snapshot tmp $(RELNAME)

up::
	-$(Q)$(MAKE) $(MFLAGS) REVISION_FORCE=PHONY "$(REVISION_H)"

after-update:: update-unicode update-gems common-srcs

update-config_files: PHONY
	$(Q) $(BASERUBY) -C "$(srcdir)/tool" \
	    ../tool/downloader.rb -e gnu \
	    config.guess config.sub

update-gems: PHONY
	$(ECHO) Downloading bundled gem files...
	$(Q) $(RUNRUBY) -C "$(srcdir)/gems" \
	    -I../tool -rdownloader -answ \
	    -e 'gem, ver = *$$F' \
	    -e 'gem = "#{gem}-#{ver}.gem"' \
	    -e 'Downloader::RubyGems.download(gem)' \
	    bundled_gems

UPDATE_LIBRARIES = no

### set the following environment variable or uncomment the line if
### the Unicode data files are updated every minute.
# ALWAYS_UPDATE_UNICODE = yes

UNICODE_FILES = $(srcdir)/enc/unicode/data/$(UNICODE_VERSION)/UnicodeData.txt \
		$(srcdir)/enc/unicode/data/$(UNICODE_VERSION)/CompositionExclusions.txt \
		$(srcdir)/enc/unicode/data/$(UNICODE_VERSION)/NormalizationTest.txt

update-unicode: $(UNICODE_FILES) PHONY

UNICODE_FILES_DEPS0 = $(UPDATE_LIBRARIES:yes=download-unicode-data)
UNICODE_FILES_DEPS = $(UNICODE_FILES_DEPS0:no=)
$(UNICODE_FILES): $(UNICODE_FILES_DEPS)

download-unicode-data: ./.unicode-$(UNICODE_VERSION).time
./.unicode-$(UNICODE_VERSION).time: PHONY
	$(ECHO) Downloading Unicode $(UNICODE_VERSION) data files...
	$(Q) $(MAKEDIRS) "$(srcdir)/enc/unicode/data/$(UNICODE_VERSION)"
	$(Q) $(BASERUBY) -C "$(srcdir)" tool/downloader.rb \
	    -d enc/unicode/data/$(UNICODE_VERSION) \
	    -e $(ALWAYS_UPDATE_UNICODE:yes=-a) unicode \
	    $(UNICODE_VERSION)/ucd/UnicodeData.txt \
	    $(UNICODE_VERSION)/ucd/CompositionExclusions.txt \
	    $(UNICODE_VERSION)/ucd/NormalizationTest.txt
	@exit > $@

$(srcdir)/$(HAVE_BASERUBY:yes=lib/unicode_normalize/tables.rb): \
	$(UNICODE_FILES_DEPS:download-unicode-data=./.unicode-tables.time)

./.unicode-tables.time: $(srcdir)/tool/generic_erb.rb \
		$(UNICODE_FILES) $(UNICODE_FILES_DEPS) \
		$(srcdir)/template/unicode_norm_gen.tmpl
	$(Q) $(BASERUBY) $(srcdir)/tool/generic_erb.rb \
		-c -t$@ -o $(srcdir)/lib/unicode_normalize/tables.rb \
		-I $(srcdir) \
		$(srcdir)/template/unicode_norm_gen.tmpl \
		enc/unicode/data/$(UNICODE_VERSION) lib/unicode_normalize

info: info-program info-libruby_a info-libruby_so info-arch
info-program: PHONY
	@echo PROGRAM=$(PROGRAM)
info-libruby_a: PHONY
	@echo LIBRUBY_A=$(LIBRUBY_A)
info-libruby_so: PHONY
	@echo LIBRUBY_SO=$(LIBRUBY_SO)
info-arch: PHONY
	@echo arch=$(arch)

change: PHONY
	$(BASERUBY) -C "$(srcdir)" ./tool/change_maker.rb $(CHANGES) > change.log

love: sudo-precheck up all test install test-all
	@echo love is all you need

yes-test-all: sudo-precheck

sudo-precheck: PHONY
	@$(SUDO) echo > $(NULL)

help: PHONY
	$(MESSAGE_BEGIN) \
	"                Makefile of Ruby" \
	"" \
	"targets:" \
	"  all (default):   builds all of below" \
	"  miniruby:        builds only miniruby" \
	"  encs:            builds encodings" \
	"  exts:            builds extensions" \
	"  main:            builds encodings, extensions and ruby" \
	"  docs:            builds documents" \
	"  run:             runs test.rb by miniruby" \
	"  runruby:         runs test.rb by ruby you just built" \
	"  gdb:             runs test.rb by miniruby under gdb" \
	"  gdb-ruby:        runs test.rb by ruby under gdb" \
	"  check:           equals make test test-all" \
	"  test:            ruby core tests" \
	"  test-all:        all ruby tests [TESTS=<test files>]" \
	"  test-rubyspec:   run RubySpec test suite" \
	"  update-rubyspec: update local copy of RubySpec" \
	"  benchmark:       benchmark this ruby and COMPARE_RUBY" \
	"  gcbench:         gc benchmark [GCBENCH_ITEM=<item_name>]" \
	"  gcbench-rdoc:    gc benchmark with GCBENCH_ITEM=rdoc" \
	"  install:         install all ruby distributions" \
	"  install-nodoc:   install without rdoc" \
	"  install-cross:   install cross compiling staff" \
	"  clean:           clean for tarball" \
	"  distclean:       clean for repository" \
	"  change:          make change log template" \
	"  golf:            for golfers" \
	"" \
	"see DeveloperHowto for more detail: " \
	"  https://bugs.ruby-lang.org/projects/ruby/wiki/DeveloperHowto" \
	$(MESSAGE_END)

addr2line.$(OBJEXT): {$(VPATH)}addr2line.h # addr2line.o: addr2line.h
array.$(OBJEXT): $(hdrdir)/ruby/ruby.h # array.o: include/ruby/ruby.h
array.$(OBJEXT): {$(VPATH)}defines.h # array.o: include/ruby/defines.h
array.$(OBJEXT): {$(VPATH)}encoding.h # array.o: include/ruby/encoding.h
array.$(OBJEXT): {$(VPATH)}id.h # array.o: id.h
array.$(OBJEXT): {$(VPATH)}intern.h # array.o: include/ruby/intern.h
array.$(OBJEXT): {$(VPATH)}internal.h # array.o: internal.h
array.$(OBJEXT): {$(VPATH)}oniguruma.h # array.o: include/ruby/oniguruma.h
array.$(OBJEXT): {$(VPATH)}probes.h # array.o: probes.h
array.$(OBJEXT): {$(VPATH)}st.h # array.o: include/ruby/st.h
array.$(OBJEXT): {$(VPATH)}subst.h # array.o: include/ruby/subst.h
array.$(OBJEXT): {$(VPATH)}util.h # array.o: include/ruby/util.h
array.$(OBJEXT): {$(VPATH)}vm_opts.h # array.o: vm_opts.h
ascii.$(OBJEXT): {$(VPATH)}defines.h # ascii.o: include/ruby/defines.h
ascii.$(OBJEXT): {$(VPATH)}oniguruma.h # ascii.o: include/ruby/oniguruma.h
ascii.$(OBJEXT): {$(VPATH)}regenc.h # ascii.o: regenc.h
bignum.$(OBJEXT): $(hdrdir)/ruby/ruby.h # bignum.o: include/ruby/ruby.h
bignum.$(OBJEXT): {$(VPATH)}defines.h # bignum.o: include/ruby/defines.h
bignum.$(OBJEXT): {$(VPATH)}intern.h # bignum.o: include/ruby/intern.h
bignum.$(OBJEXT): {$(VPATH)}internal.h # bignum.o: internal.h
bignum.$(OBJEXT): {$(VPATH)}st.h # bignum.o: include/ruby/st.h
bignum.$(OBJEXT): {$(VPATH)}subst.h # bignum.o: include/ruby/subst.h
bignum.$(OBJEXT): {$(VPATH)}thread.h # bignum.o: include/ruby/thread.h
bignum.$(OBJEXT): {$(VPATH)}util.h # bignum.o: include/ruby/util.h
class.$(OBJEXT): $(CCAN_DIR)/check_type/check_type.h # class.o: ccan/check_type/check_type.h
class.$(OBJEXT): $(CCAN_DIR)/container_of/container_of.h # class.o: ccan/container_of/container_of.h
class.$(OBJEXT): $(CCAN_DIR)/list/list.h # class.o: ccan/list/list.h
class.$(OBJEXT): $(CCAN_DIR)/str/str.h # class.o: ccan/str/str.h
class.$(OBJEXT): $(hdrdir)/ruby/ruby.h # class.o: include/ruby/ruby.h
class.$(OBJEXT): {$(VPATH)}constant.h # class.o: constant.h
class.$(OBJEXT): {$(VPATH)}defines.h # class.o: include/ruby/defines.h
class.$(OBJEXT): {$(VPATH)}id.h # class.o: id.h
class.$(OBJEXT): {$(VPATH)}intern.h # class.o: include/ruby/intern.h
class.$(OBJEXT): {$(VPATH)}internal.h # class.o: internal.h
class.$(OBJEXT): {$(VPATH)}method.h # class.o: method.h
class.$(OBJEXT): {$(VPATH)}node.h # class.o: node.h
class.$(OBJEXT): {$(VPATH)}ruby_atomic.h # class.o: ruby_atomic.h
class.$(OBJEXT): {$(VPATH)}st.h # class.o: include/ruby/st.h
class.$(OBJEXT): {$(VPATH)}subst.h # class.o: include/ruby/subst.h
class.$(OBJEXT): {$(VPATH)}thread_$(THREAD_MODEL).h # class.o: thread_pthread.h
class.$(OBJEXT): {$(VPATH)}thread_native.h # class.o: include/ruby/thread_native.h
class.$(OBJEXT): {$(VPATH)}vm_core.h # class.o: vm_core.h
class.$(OBJEXT): {$(VPATH)}vm_debug.h # class.o: vm_debug.h
class.$(OBJEXT): {$(VPATH)}vm_opts.h # class.o: vm_opts.h
compar.$(OBJEXT): $(hdrdir)/ruby/ruby.h # compar.o: include/ruby/ruby.h
compar.$(OBJEXT): {$(VPATH)}defines.h # compar.o: include/ruby/defines.h
compar.$(OBJEXT): {$(VPATH)}intern.h # compar.o: include/ruby/intern.h
compar.$(OBJEXT): {$(VPATH)}st.h # compar.o: include/ruby/st.h
compar.$(OBJEXT): {$(VPATH)}subst.h # compar.o: include/ruby/subst.h
compile.$(OBJEXT): $(CCAN_DIR)/check_type/check_type.h # compile.o: ccan/check_type/check_type.h
compile.$(OBJEXT): $(CCAN_DIR)/container_of/container_of.h # compile.o: ccan/container_of/container_of.h
compile.$(OBJEXT): $(CCAN_DIR)/list/list.h # compile.o: ccan/list/list.h
compile.$(OBJEXT): $(CCAN_DIR)/str/str.h # compile.o: ccan/str/str.h
compile.$(OBJEXT): $(hdrdir)/ruby/ruby.h # compile.o: include/ruby/ruby.h
compile.$(OBJEXT): {$(VPATH)}defines.h # compile.o: include/ruby/defines.h
compile.$(OBJEXT): {$(VPATH)}id.h # compile.o: id.h
compile.$(OBJEXT): {$(VPATH)}insns.inc # compile.o: insns.inc
compile.$(OBJEXT): {$(VPATH)}insns_info.inc # compile.o: insns_info.inc
compile.$(OBJEXT): {$(VPATH)}intern.h # compile.o: include/ruby/intern.h
compile.$(OBJEXT): {$(VPATH)}internal.h # compile.o: internal.h
compile.$(OBJEXT): {$(VPATH)}iseq.h # compile.o: iseq.h
compile.$(OBJEXT): {$(VPATH)}method.h # compile.o: method.h
compile.$(OBJEXT): {$(VPATH)}node.h # compile.o: node.h
compile.$(OBJEXT): {$(VPATH)}optinsn.inc # compile.o: optinsn.inc
compile.$(OBJEXT): {$(VPATH)}ruby_atomic.h # compile.o: ruby_atomic.h
compile.$(OBJEXT): {$(VPATH)}st.h # compile.o: include/ruby/st.h
compile.$(OBJEXT): {$(VPATH)}subst.h # compile.o: include/ruby/subst.h
compile.$(OBJEXT): {$(VPATH)}thread_$(THREAD_MODEL).h # compile.o: thread_pthread.h
compile.$(OBJEXT): {$(VPATH)}thread_native.h # compile.o: include/ruby/thread_native.h
compile.$(OBJEXT): {$(VPATH)}vm_core.h # compile.o: vm_core.h
compile.$(OBJEXT): {$(VPATH)}vm_debug.h # compile.o: vm_debug.h
compile.$(OBJEXT): {$(VPATH)}vm_opts.h # compile.o: vm_opts.h
complex.$(OBJEXT): $(hdrdir)/ruby.h # complex.o: include/ruby.h
complex.$(OBJEXT): $(hdrdir)/ruby/ruby.h # complex.o: include/ruby/ruby.h
complex.$(OBJEXT): {$(VPATH)}defines.h # complex.o: include/ruby/defines.h
complex.$(OBJEXT): {$(VPATH)}intern.h # complex.o: include/ruby/intern.h
complex.$(OBJEXT): {$(VPATH)}internal.h # complex.o: internal.h
complex.$(OBJEXT): {$(VPATH)}st.h # complex.o: include/ruby/st.h
complex.$(OBJEXT): {$(VPATH)}subst.h # complex.o: include/ruby/subst.h
cont.$(OBJEXT): $(CCAN_DIR)/check_type/check_type.h # cont.o: ccan/check_type/check_type.h
cont.$(OBJEXT): $(CCAN_DIR)/container_of/container_of.h # cont.o: ccan/container_of/container_of.h
cont.$(OBJEXT): $(CCAN_DIR)/list/list.h # cont.o: ccan/list/list.h
cont.$(OBJEXT): $(CCAN_DIR)/str/str.h # cont.o: ccan/str/str.h
cont.$(OBJEXT): $(hdrdir)/ruby/ruby.h # cont.o: include/ruby/ruby.h
cont.$(OBJEXT): {$(VPATH)}defines.h # cont.o: include/ruby/defines.h
cont.$(OBJEXT): {$(VPATH)}eval_intern.h # cont.o: eval_intern.h
cont.$(OBJEXT): {$(VPATH)}gc.h # cont.o: gc.h
cont.$(OBJEXT): {$(VPATH)}id.h # cont.o: id.h
cont.$(OBJEXT): {$(VPATH)}intern.h # cont.o: include/ruby/intern.h
cont.$(OBJEXT): {$(VPATH)}internal.h # cont.o: internal.h
cont.$(OBJEXT): {$(VPATH)}method.h # cont.o: method.h
cont.$(OBJEXT): {$(VPATH)}node.h # cont.o: node.h
cont.$(OBJEXT): {$(VPATH)}ruby_atomic.h # cont.o: ruby_atomic.h
cont.$(OBJEXT): {$(VPATH)}st.h # cont.o: include/ruby/st.h
cont.$(OBJEXT): {$(VPATH)}subst.h # cont.o: include/ruby/subst.h
cont.$(OBJEXT): {$(VPATH)}thread_$(THREAD_MODEL).h # cont.o: thread_pthread.h
cont.$(OBJEXT): {$(VPATH)}thread_native.h # cont.o: include/ruby/thread_native.h
cont.$(OBJEXT): {$(VPATH)}vm_core.h # cont.o: vm_core.h
cont.$(OBJEXT): {$(VPATH)}vm_debug.h # cont.o: vm_debug.h
cont.$(OBJEXT): {$(VPATH)}vm_opts.h # cont.o: vm_opts.h
debug.$(OBJEXT): $(CCAN_DIR)/check_type/check_type.h # debug.o: ccan/check_type/check_type.h
debug.$(OBJEXT): $(CCAN_DIR)/container_of/container_of.h # debug.o: ccan/container_of/container_of.h
debug.$(OBJEXT): $(CCAN_DIR)/list/list.h # debug.o: ccan/list/list.h
debug.$(OBJEXT): $(CCAN_DIR)/str/str.h # debug.o: ccan/str/str.h
debug.$(OBJEXT): $(hdrdir)/ruby/ruby.h # debug.o: include/ruby/ruby.h
debug.$(OBJEXT): {$(VPATH)}defines.h # debug.o: include/ruby/defines.h
debug.$(OBJEXT): {$(VPATH)}encoding.h # debug.o: include/ruby/encoding.h
debug.$(OBJEXT): {$(VPATH)}eval_intern.h # debug.o: eval_intern.h
debug.$(OBJEXT): {$(VPATH)}id.h # debug.o: id.h
debug.$(OBJEXT): {$(VPATH)}intern.h # debug.o: include/ruby/intern.h
debug.$(OBJEXT): {$(VPATH)}internal.h # debug.o: internal.h
debug.$(OBJEXT): {$(VPATH)}method.h # debug.o: method.h
debug.$(OBJEXT): {$(VPATH)}node.h # debug.o: node.h
debug.$(OBJEXT): {$(VPATH)}oniguruma.h # debug.o: include/ruby/oniguruma.h
debug.$(OBJEXT): {$(VPATH)}ruby_atomic.h # debug.o: ruby_atomic.h
debug.$(OBJEXT): {$(VPATH)}st.h # debug.o: include/ruby/st.h
debug.$(OBJEXT): {$(VPATH)}subst.h # debug.o: include/ruby/subst.h
debug.$(OBJEXT): {$(VPATH)}thread_$(THREAD_MODEL).h # debug.o: thread_pthread.h
debug.$(OBJEXT): {$(VPATH)}thread_native.h # debug.o: include/ruby/thread_native.h
debug.$(OBJEXT): {$(VPATH)}util.h # debug.o: include/ruby/util.h
debug.$(OBJEXT): {$(VPATH)}vm_core.h # debug.o: vm_core.h
debug.$(OBJEXT): {$(VPATH)}vm_debug.h # debug.o: vm_debug.h
debug.$(OBJEXT): {$(VPATH)}vm_opts.h # debug.o: vm_opts.h
dir.$(OBJEXT): $(hdrdir)/ruby/ruby.h # dir.o: include/ruby/ruby.h
dir.$(OBJEXT): {$(VPATH)}defines.h # dir.o: include/ruby/defines.h
dir.$(OBJEXT): {$(VPATH)}encoding.h # dir.o: include/ruby/encoding.h
dir.$(OBJEXT): {$(VPATH)}intern.h # dir.o: include/ruby/intern.h
dir.$(OBJEXT): {$(VPATH)}internal.h # dir.o: internal.h
dir.$(OBJEXT): {$(VPATH)}oniguruma.h # dir.o: include/ruby/oniguruma.h
dir.$(OBJEXT): {$(VPATH)}st.h # dir.o: include/ruby/st.h
dir.$(OBJEXT): {$(VPATH)}subst.h # dir.o: include/ruby/subst.h
dir.$(OBJEXT): {$(VPATH)}util.h # dir.o: include/ruby/util.h
dln.$(OBJEXT): $(hdrdir)/ruby/ruby.h # dln.o: include/ruby/ruby.h
dln.$(OBJEXT): {$(VPATH)}defines.h # dln.o: include/ruby/defines.h
dln.$(OBJEXT): {$(VPATH)}dln.h # dln.o: dln.h
dln.$(OBJEXT): {$(VPATH)}intern.h # dln.o: include/ruby/intern.h
dln.$(OBJEXT): {$(VPATH)}st.h # dln.o: include/ruby/st.h
dln.$(OBJEXT): {$(VPATH)}subst.h # dln.o: include/ruby/subst.h
dln_find.$(OBJEXT): $(hdrdir)/ruby/ruby.h # dln_find.o: include/ruby/ruby.h
dln_find.$(OBJEXT): {$(VPATH)}defines.h # dln_find.o: include/ruby/defines.h
dln_find.$(OBJEXT): {$(VPATH)}dln.h # dln_find.o: dln.h
dln_find.$(OBJEXT): {$(VPATH)}intern.h # dln_find.o: include/ruby/intern.h
dln_find.$(OBJEXT): {$(VPATH)}st.h # dln_find.o: include/ruby/st.h
dln_find.$(OBJEXT): {$(VPATH)}subst.h # dln_find.o: include/ruby/subst.h
dmydln.$(OBJEXT): $(hdrdir)/ruby/ruby.h # dmydln.o: include/ruby/ruby.h
dmydln.$(OBJEXT): {$(VPATH)}config.h # dmydln.o: .ext/include/x86_64-linux/ruby/config.h
dmydln.$(OBJEXT): {$(VPATH)}defines.h # dmydln.o: include/ruby/defines.h
dmydln.$(OBJEXT): {$(VPATH)}intern.h # dmydln.o: include/ruby/intern.h
dmydln.$(OBJEXT): {$(VPATH)}missing.h # dmydln.o: include/ruby/missing.h
dmydln.$(OBJEXT): {$(VPATH)}st.h # dmydln.o: include/ruby/st.h
dmydln.$(OBJEXT): {$(VPATH)}subst.h # dmydln.o: include/ruby/subst.h
encoding.$(OBJEXT): $(hdrdir)/ruby/ruby.h # encoding.o: include/ruby/ruby.h
encoding.$(OBJEXT): {$(VPATH)}defines.h # encoding.o: include/ruby/defines.h
encoding.$(OBJEXT): {$(VPATH)}encoding.h # encoding.o: include/ruby/encoding.h
encoding.$(OBJEXT): {$(VPATH)}intern.h # encoding.o: include/ruby/intern.h
encoding.$(OBJEXT): {$(VPATH)}internal.h # encoding.o: internal.h
encoding.$(OBJEXT): {$(VPATH)}oniguruma.h # encoding.o: include/ruby/oniguruma.h
encoding.$(OBJEXT): {$(VPATH)}regenc.h # encoding.o: regenc.h
encoding.$(OBJEXT): {$(VPATH)}st.h # encoding.o: include/ruby/st.h
encoding.$(OBJEXT): {$(VPATH)}subst.h # encoding.o: include/ruby/subst.h
encoding.$(OBJEXT): {$(VPATH)}util.h # encoding.o: include/ruby/util.h
enum.$(OBJEXT): $(hdrdir)/ruby/ruby.h # enum.o: include/ruby/ruby.h
enum.$(OBJEXT): {$(VPATH)}defines.h # enum.o: include/ruby/defines.h
enum.$(OBJEXT): {$(VPATH)}id.h # enum.o: id.h
enum.$(OBJEXT): {$(VPATH)}intern.h # enum.o: include/ruby/intern.h
enum.$(OBJEXT): {$(VPATH)}internal.h # enum.o: internal.h
enum.$(OBJEXT): {$(VPATH)}node.h # enum.o: node.h
enum.$(OBJEXT): {$(VPATH)}st.h # enum.o: include/ruby/st.h
enum.$(OBJEXT): {$(VPATH)}subst.h # enum.o: include/ruby/subst.h
enum.$(OBJEXT): {$(VPATH)}util.h # enum.o: include/ruby/util.h
enumerator.$(OBJEXT): $(hdrdir)/ruby/ruby.h # enumerator.o: include/ruby/ruby.h
enumerator.$(OBJEXT): {$(VPATH)}defines.h # enumerator.o: include/ruby/defines.h
enumerator.$(OBJEXT): {$(VPATH)}intern.h # enumerator.o: include/ruby/intern.h
enumerator.$(OBJEXT): {$(VPATH)}internal.h # enumerator.o: internal.h
enumerator.$(OBJEXT): {$(VPATH)}node.h # enumerator.o: node.h
enumerator.$(OBJEXT): {$(VPATH)}st.h # enumerator.o: include/ruby/st.h
enumerator.$(OBJEXT): {$(VPATH)}subst.h # enumerator.o: include/ruby/subst.h
error.$(OBJEXT): $(CCAN_DIR)/check_type/check_type.h # error.o: ccan/check_type/check_type.h
error.$(OBJEXT): $(CCAN_DIR)/container_of/container_of.h # error.o: ccan/container_of/container_of.h
error.$(OBJEXT): $(CCAN_DIR)/list/list.h # error.o: ccan/list/list.h
error.$(OBJEXT): $(CCAN_DIR)/str/str.h # error.o: ccan/str/str.h
error.$(OBJEXT): $(hdrdir)/ruby/ruby.h # error.o: include/ruby/ruby.h
error.$(OBJEXT): {$(VPATH)}defines.h # error.o: include/ruby/defines.h
error.$(OBJEXT): {$(VPATH)}encoding.h # error.o: include/ruby/encoding.h
error.$(OBJEXT): {$(VPATH)}id.h # error.o: id.h
error.$(OBJEXT): {$(VPATH)}intern.h # error.o: include/ruby/intern.h
error.$(OBJEXT): {$(VPATH)}internal.h # error.o: internal.h
error.$(OBJEXT): {$(VPATH)}known_errors.inc # error.o: known_errors.inc
error.$(OBJEXT): {$(VPATH)}method.h # error.o: method.h
error.$(OBJEXT): {$(VPATH)}node.h # error.o: node.h
error.$(OBJEXT): {$(VPATH)}oniguruma.h # error.o: include/ruby/oniguruma.h
error.$(OBJEXT): {$(VPATH)}ruby_atomic.h # error.o: ruby_atomic.h
error.$(OBJEXT): {$(VPATH)}st.h # error.o: include/ruby/st.h
error.$(OBJEXT): {$(VPATH)}subst.h # error.o: include/ruby/subst.h
error.$(OBJEXT): {$(VPATH)}thread_$(THREAD_MODEL).h # error.o: thread_pthread.h
error.$(OBJEXT): {$(VPATH)}thread_native.h # error.o: include/ruby/thread_native.h
error.$(OBJEXT): {$(VPATH)}vm_core.h # error.o: vm_core.h
error.$(OBJEXT): {$(VPATH)}vm_debug.h # error.o: vm_debug.h
error.$(OBJEXT): {$(VPATH)}vm_opts.h # error.o: vm_opts.h
eval.$(OBJEXT): $(CCAN_DIR)/check_type/check_type.h # eval.o: ccan/check_type/check_type.h
eval.$(OBJEXT): $(CCAN_DIR)/container_of/container_of.h # eval.o: ccan/container_of/container_of.h
eval.$(OBJEXT): $(CCAN_DIR)/list/list.h # eval.o: ccan/list/list.h
eval.$(OBJEXT): $(CCAN_DIR)/str/str.h # eval.o: ccan/str/str.h
eval.$(OBJEXT): $(hdrdir)/ruby/ruby.h # eval.o: include/ruby/ruby.h
eval.$(OBJEXT): {$(VPATH)}defines.h # eval.o: include/ruby/defines.h
eval.$(OBJEXT): {$(VPATH)}encoding.h # eval.o: include/ruby/encoding.h
eval.$(OBJEXT): {$(VPATH)}eval_error.c # eval.o: eval_error.c
eval.$(OBJEXT): {$(VPATH)}eval_intern.h # eval.o: eval_intern.h
eval.$(OBJEXT): {$(VPATH)}eval_jump.c # eval.o: eval_jump.c
eval.$(OBJEXT): {$(VPATH)}gc.h # eval.o: gc.h
eval.$(OBJEXT): {$(VPATH)}id.h # eval.o: id.h
eval.$(OBJEXT): {$(VPATH)}intern.h # eval.o: include/ruby/intern.h
eval.$(OBJEXT): {$(VPATH)}internal.h # eval.o: internal.h
eval.$(OBJEXT): {$(VPATH)}iseq.h # eval.o: iseq.h
eval.$(OBJEXT): {$(VPATH)}method.h # eval.o: method.h
eval.$(OBJEXT): {$(VPATH)}node.h # eval.o: node.h
eval.$(OBJEXT): {$(VPATH)}oniguruma.h # eval.o: include/ruby/oniguruma.h
eval.$(OBJEXT): {$(VPATH)}probes.h # eval.o: probes.h
eval.$(OBJEXT): {$(VPATH)}probes_helper.h # eval.o: probes_helper.h
eval.$(OBJEXT): {$(VPATH)}ruby_atomic.h # eval.o: ruby_atomic.h
eval.$(OBJEXT): {$(VPATH)}st.h # eval.o: include/ruby/st.h
eval.$(OBJEXT): {$(VPATH)}subst.h # eval.o: include/ruby/subst.h
eval.$(OBJEXT): {$(VPATH)}thread_$(THREAD_MODEL).h # eval.o: thread_pthread.h
eval.$(OBJEXT): {$(VPATH)}thread_native.h # eval.o: include/ruby/thread_native.h
eval.$(OBJEXT): {$(VPATH)}vm.h # eval.o: include/ruby/vm.h
eval.$(OBJEXT): {$(VPATH)}vm_core.h # eval.o: vm_core.h
eval.$(OBJEXT): {$(VPATH)}vm_debug.h # eval.o: vm_debug.h
eval.$(OBJEXT): {$(VPATH)}vm_opts.h # eval.o: vm_opts.h
file.$(OBJEXT): $(hdrdir)/ruby/ruby.h # file.o: include/ruby/ruby.h
file.$(OBJEXT): {$(VPATH)}defines.h # file.o: include/ruby/defines.h
file.$(OBJEXT): {$(VPATH)}dln.h # file.o: dln.h
file.$(OBJEXT): {$(VPATH)}encoding.h # file.o: include/ruby/encoding.h
file.$(OBJEXT): {$(VPATH)}intern.h # file.o: include/ruby/intern.h
file.$(OBJEXT): {$(VPATH)}internal.h # file.o: internal.h
file.$(OBJEXT): {$(VPATH)}io.h # file.o: include/ruby/io.h
file.$(OBJEXT): {$(VPATH)}oniguruma.h # file.o: include/ruby/oniguruma.h
file.$(OBJEXT): {$(VPATH)}st.h # file.o: include/ruby/st.h
file.$(OBJEXT): {$(VPATH)}subst.h # file.o: include/ruby/subst.h
file.$(OBJEXT): {$(VPATH)}util.h # file.o: include/ruby/util.h
gc.$(OBJEXT): $(CCAN_DIR)/check_type/check_type.h # gc.o: ccan/check_type/check_type.h
gc.$(OBJEXT): $(CCAN_DIR)/container_of/container_of.h # gc.o: ccan/container_of/container_of.h
gc.$(OBJEXT): $(CCAN_DIR)/list/list.h # gc.o: ccan/list/list.h
gc.$(OBJEXT): $(CCAN_DIR)/str/str.h # gc.o: ccan/str/str.h
gc.$(OBJEXT): $(hdrdir)/ruby/ruby.h # gc.o: include/ruby/ruby.h
gc.$(OBJEXT): {$(VPATH)}constant.h # gc.o: constant.h
gc.$(OBJEXT): {$(VPATH)}debug.h # gc.o: include/ruby/debug.h
gc.$(OBJEXT): {$(VPATH)}defines.h # gc.o: include/ruby/defines.h
gc.$(OBJEXT): {$(VPATH)}encoding.h # gc.o: include/ruby/encoding.h
gc.$(OBJEXT): {$(VPATH)}eval_intern.h # gc.o: eval_intern.h
gc.$(OBJEXT): {$(VPATH)}gc.h # gc.o: gc.h
gc.$(OBJEXT): {$(VPATH)}id.h # gc.o: id.h
gc.$(OBJEXT): {$(VPATH)}intern.h # gc.o: include/ruby/intern.h
gc.$(OBJEXT): {$(VPATH)}internal.h # gc.o: internal.h
gc.$(OBJEXT): {$(VPATH)}io.h # gc.o: include/ruby/io.h
gc.$(OBJEXT): {$(VPATH)}method.h # gc.o: method.h
gc.$(OBJEXT): {$(VPATH)}node.h # gc.o: node.h
gc.$(OBJEXT): {$(VPATH)}oniguruma.h # gc.o: include/ruby/oniguruma.h
gc.$(OBJEXT): {$(VPATH)}probes.h # gc.o: probes.h
gc.$(OBJEXT): {$(VPATH)}re.h # gc.o: include/ruby/re.h
gc.$(OBJEXT): {$(VPATH)}regenc.h # gc.o: regenc.h
gc.$(OBJEXT): {$(VPATH)}regex.h # gc.o: include/ruby/regex.h
gc.$(OBJEXT): {$(VPATH)}regint.h # gc.o: regint.h
gc.$(OBJEXT): {$(VPATH)}ruby_atomic.h # gc.o: ruby_atomic.h
gc.$(OBJEXT): {$(VPATH)}st.h # gc.o: include/ruby/st.h
gc.$(OBJEXT): {$(VPATH)}subst.h # gc.o: include/ruby/subst.h
gc.$(OBJEXT): {$(VPATH)}thread.h # gc.o: include/ruby/thread.h
gc.$(OBJEXT): {$(VPATH)}thread_$(THREAD_MODEL).h # gc.o: thread_pthread.h
gc.$(OBJEXT): {$(VPATH)}thread_native.h # gc.o: include/ruby/thread_native.h
gc.$(OBJEXT): {$(VPATH)}util.h # gc.o: include/ruby/util.h
gc.$(OBJEXT): {$(VPATH)}vm_core.h # gc.o: vm_core.h
gc.$(OBJEXT): {$(VPATH)}vm_debug.h # gc.o: vm_debug.h
gc.$(OBJEXT): {$(VPATH)}vm_opts.h # gc.o: vm_opts.h
golf_prelude.$(OBJEXT): $(CCAN_DIR)/check_type/check_type.h # golf_prelude.o: ccan/check_type/check_type.h
golf_prelude.$(OBJEXT): $(CCAN_DIR)/container_of/container_of.h # golf_prelude.o: ccan/container_of/container_of.h
golf_prelude.$(OBJEXT): $(CCAN_DIR)/list/list.h # golf_prelude.o: ccan/list/list.h
golf_prelude.$(OBJEXT): $(CCAN_DIR)/str/str.h # golf_prelude.o: ccan/str/str.h
golf_prelude.$(OBJEXT): $(hdrdir)/ruby/ruby.h # golf_prelude.o: include/ruby/ruby.h
golf_prelude.$(OBJEXT): {$(VPATH)}config.h # golf_prelude.o: .ext/include/x86_64-linux/ruby/config.h
golf_prelude.$(OBJEXT): {$(VPATH)}defines.h # golf_prelude.o: include/ruby/defines.h
golf_prelude.$(OBJEXT): {$(VPATH)}id.h # golf_prelude.o: id.h
golf_prelude.$(OBJEXT): {$(VPATH)}intern.h # golf_prelude.o: include/ruby/intern.h
golf_prelude.$(OBJEXT): {$(VPATH)}internal.h # golf_prelude.o: internal.h
golf_prelude.$(OBJEXT): {$(VPATH)}method.h # golf_prelude.o: method.h
golf_prelude.$(OBJEXT): {$(VPATH)}missing.h # golf_prelude.o: include/ruby/missing.h
golf_prelude.$(OBJEXT): {$(VPATH)}node.h # golf_prelude.o: node.h
golf_prelude.$(OBJEXT): {$(VPATH)}ruby_atomic.h # golf_prelude.o: ruby_atomic.h
golf_prelude.$(OBJEXT): {$(VPATH)}st.h # golf_prelude.o: include/ruby/st.h
golf_prelude.$(OBJEXT): {$(VPATH)}subst.h # golf_prelude.o: include/ruby/subst.h
golf_prelude.$(OBJEXT): {$(VPATH)}thread_$(THREAD_MODEL).h # golf_prelude.o: thread_pthread.h
golf_prelude.$(OBJEXT): {$(VPATH)}thread_native.h # golf_prelude.o: include/ruby/thread_native.h
golf_prelude.$(OBJEXT): {$(VPATH)}vm_core.h # golf_prelude.o: vm_core.h
golf_prelude.$(OBJEXT): {$(VPATH)}vm_debug.h # golf_prelude.o: vm_debug.h
golf_prelude.$(OBJEXT): {$(VPATH)}vm_opts.h # golf_prelude.o: vm_opts.h
goruby.$(OBJEXT): $(hdrdir)/ruby.h # goruby.o: include/ruby.h
goruby.$(OBJEXT): $(hdrdir)/ruby/ruby.h # goruby.o: include/ruby/ruby.h
goruby.$(OBJEXT): {$(VPATH)}config.h # goruby.o: .ext/include/x86_64-linux/ruby/config.h
goruby.$(OBJEXT): {$(VPATH)}defines.h # goruby.o: include/ruby/defines.h
goruby.$(OBJEXT): {$(VPATH)}intern.h # goruby.o: include/ruby/intern.h
goruby.$(OBJEXT): {$(VPATH)}main.c # goruby.o: main.c
goruby.$(OBJEXT): {$(VPATH)}missing.h # goruby.o: include/ruby/missing.h
goruby.$(OBJEXT): {$(VPATH)}node.h # goruby.o: node.h
goruby.$(OBJEXT): {$(VPATH)}st.h # goruby.o: include/ruby/st.h
goruby.$(OBJEXT): {$(VPATH)}subst.h # goruby.o: include/ruby/subst.h
goruby.$(OBJEXT): {$(VPATH)}vm_debug.h # goruby.o: vm_debug.h
hash.$(OBJEXT): $(hdrdir)/ruby/ruby.h # hash.o: include/ruby/ruby.h
hash.$(OBJEXT): {$(VPATH)}defines.h # hash.o: include/ruby/defines.h
hash.$(OBJEXT): {$(VPATH)}encoding.h # hash.o: include/ruby/encoding.h
hash.$(OBJEXT): {$(VPATH)}id.h # hash.o: id.h
hash.$(OBJEXT): {$(VPATH)}intern.h # hash.o: include/ruby/intern.h
hash.$(OBJEXT): {$(VPATH)}internal.h # hash.o: internal.h
hash.$(OBJEXT): {$(VPATH)}oniguruma.h # hash.o: include/ruby/oniguruma.h
hash.$(OBJEXT): {$(VPATH)}probes.h # hash.o: probes.h
hash.$(OBJEXT): {$(VPATH)}st.h # hash.o: include/ruby/st.h
hash.$(OBJEXT): {$(VPATH)}subst.h # hash.o: include/ruby/subst.h
hash.$(OBJEXT): {$(VPATH)}util.h # hash.o: include/ruby/util.h
hash.$(OBJEXT): {$(VPATH)}vm_opts.h # hash.o: vm_opts.h
inits.$(OBJEXT): $(hdrdir)/ruby/ruby.h # inits.o: include/ruby/ruby.h
inits.$(OBJEXT): {$(VPATH)}defines.h # inits.o: include/ruby/defines.h
inits.$(OBJEXT): {$(VPATH)}intern.h # inits.o: include/ruby/intern.h
inits.$(OBJEXT): {$(VPATH)}internal.h # inits.o: internal.h
inits.$(OBJEXT): {$(VPATH)}st.h # inits.o: include/ruby/st.h
inits.$(OBJEXT): {$(VPATH)}subst.h # inits.o: include/ruby/subst.h
io.$(OBJEXT): $(hdrdir)/ruby/ruby.h # io.o: include/ruby/ruby.h
io.$(OBJEXT): {$(VPATH)}defines.h # io.o: include/ruby/defines.h
io.$(OBJEXT): {$(VPATH)}dln.h # io.o: dln.h
io.$(OBJEXT): {$(VPATH)}encoding.h # io.o: include/ruby/encoding.h
io.$(OBJEXT): {$(VPATH)}id.h # io.o: id.h
io.$(OBJEXT): {$(VPATH)}intern.h # io.o: include/ruby/intern.h
io.$(OBJEXT): {$(VPATH)}internal.h # io.o: internal.h
io.$(OBJEXT): {$(VPATH)}io.h # io.o: include/ruby/io.h
io.$(OBJEXT): {$(VPATH)}oniguruma.h # io.o: include/ruby/oniguruma.h
io.$(OBJEXT): {$(VPATH)}ruby_atomic.h # io.o: ruby_atomic.h
io.$(OBJEXT): {$(VPATH)}st.h # io.o: include/ruby/st.h
io.$(OBJEXT): {$(VPATH)}subst.h # io.o: include/ruby/subst.h
io.$(OBJEXT): {$(VPATH)}thread.h # io.o: include/ruby/thread.h
io.$(OBJEXT): {$(VPATH)}util.h # io.o: include/ruby/util.h
iseq.$(OBJEXT): $(CCAN_DIR)/check_type/check_type.h # iseq.o: ccan/check_type/check_type.h
iseq.$(OBJEXT): $(CCAN_DIR)/container_of/container_of.h # iseq.o: ccan/container_of/container_of.h
iseq.$(OBJEXT): $(CCAN_DIR)/list/list.h # iseq.o: ccan/list/list.h
iseq.$(OBJEXT): $(CCAN_DIR)/str/str.h # iseq.o: ccan/str/str.h
iseq.$(OBJEXT): $(hdrdir)/ruby/ruby.h # iseq.o: include/ruby/ruby.h
iseq.$(OBJEXT): {$(VPATH)}defines.h # iseq.o: include/ruby/defines.h
iseq.$(OBJEXT): {$(VPATH)}eval_intern.h # iseq.o: eval_intern.h
iseq.$(OBJEXT): {$(VPATH)}gc.h # iseq.o: gc.h
iseq.$(OBJEXT): {$(VPATH)}id.h # iseq.o: id.h
iseq.$(OBJEXT): {$(VPATH)}insns.inc # iseq.o: insns.inc
iseq.$(OBJEXT): {$(VPATH)}insns_info.inc # iseq.o: insns_info.inc
iseq.$(OBJEXT): {$(VPATH)}intern.h # iseq.o: include/ruby/intern.h
iseq.$(OBJEXT): {$(VPATH)}internal.h # iseq.o: internal.h
iseq.$(OBJEXT): {$(VPATH)}iseq.h # iseq.o: iseq.h
iseq.$(OBJEXT): {$(VPATH)}method.h # iseq.o: method.h
iseq.$(OBJEXT): {$(VPATH)}node.h # iseq.o: node.h
iseq.$(OBJEXT): {$(VPATH)}node_name.inc # iseq.o: node_name.inc
iseq.$(OBJEXT): {$(VPATH)}ruby_atomic.h # iseq.o: ruby_atomic.h
iseq.$(OBJEXT): {$(VPATH)}st.h # iseq.o: include/ruby/st.h
iseq.$(OBJEXT): {$(VPATH)}subst.h # iseq.o: include/ruby/subst.h
iseq.$(OBJEXT): {$(VPATH)}thread_$(THREAD_MODEL).h # iseq.o: thread_pthread.h
iseq.$(OBJEXT): {$(VPATH)}thread_native.h # iseq.o: include/ruby/thread_native.h
iseq.$(OBJEXT): {$(VPATH)}util.h # iseq.o: include/ruby/util.h
iseq.$(OBJEXT): {$(VPATH)}vm_core.h # iseq.o: vm_core.h
iseq.$(OBJEXT): {$(VPATH)}vm_debug.h # iseq.o: vm_debug.h
iseq.$(OBJEXT): {$(VPATH)}vm_opts.h # iseq.o: vm_opts.h
load.$(OBJEXT): $(CCAN_DIR)/check_type/check_type.h # load.o: ccan/check_type/check_type.h
load.$(OBJEXT): $(CCAN_DIR)/container_of/container_of.h # load.o: ccan/container_of/container_of.h
load.$(OBJEXT): $(CCAN_DIR)/list/list.h # load.o: ccan/list/list.h
load.$(OBJEXT): $(CCAN_DIR)/str/str.h # load.o: ccan/str/str.h
load.$(OBJEXT): $(hdrdir)/ruby/ruby.h # load.o: include/ruby/ruby.h
load.$(OBJEXT): {$(VPATH)}defines.h # load.o: include/ruby/defines.h
load.$(OBJEXT): {$(VPATH)}dln.h # load.o: dln.h
load.$(OBJEXT): {$(VPATH)}eval_intern.h # load.o: eval_intern.h
load.$(OBJEXT): {$(VPATH)}id.h # load.o: id.h
load.$(OBJEXT): {$(VPATH)}intern.h # load.o: include/ruby/intern.h
load.$(OBJEXT): {$(VPATH)}internal.h # load.o: internal.h
load.$(OBJEXT): {$(VPATH)}method.h # load.o: method.h
load.$(OBJEXT): {$(VPATH)}node.h # load.o: node.h
load.$(OBJEXT): {$(VPATH)}probes.h # load.o: probes.h
load.$(OBJEXT): {$(VPATH)}ruby_atomic.h # load.o: ruby_atomic.h
load.$(OBJEXT): {$(VPATH)}st.h # load.o: include/ruby/st.h
load.$(OBJEXT): {$(VPATH)}subst.h # load.o: include/ruby/subst.h
load.$(OBJEXT): {$(VPATH)}thread_$(THREAD_MODEL).h # load.o: thread_pthread.h
load.$(OBJEXT): {$(VPATH)}thread_native.h # load.o: include/ruby/thread_native.h
load.$(OBJEXT): {$(VPATH)}util.h # load.o: include/ruby/util.h
load.$(OBJEXT): {$(VPATH)}vm_core.h # load.o: vm_core.h
load.$(OBJEXT): {$(VPATH)}vm_debug.h # load.o: vm_debug.h
load.$(OBJEXT): {$(VPATH)}vm_opts.h # load.o: vm_opts.h
loadpath.$(OBJEXT): $(hdrdir)/ruby/ruby.h # loadpath.o: include/ruby/ruby.h
loadpath.$(OBJEXT): $(srcdir)/include/ruby/version.h # loadpath.o: include/ruby/version.h
loadpath.$(OBJEXT): $(srcdir)/version.h # loadpath.o: version.h
loadpath.$(OBJEXT): {$(VPATH)}defines.h # loadpath.o: include/ruby/defines.h
loadpath.$(OBJEXT): {$(VPATH)}intern.h # loadpath.o: include/ruby/intern.h
loadpath.$(OBJEXT): {$(VPATH)}st.h # loadpath.o: include/ruby/st.h
loadpath.$(OBJEXT): {$(VPATH)}subst.h # loadpath.o: include/ruby/subst.h
loadpath.$(OBJEXT): {$(VPATH)}verconf.h # loadpath.o: verconf.h
localeinit.$(OBJEXT): $(hdrdir)/ruby/ruby.h # localeinit.o: include/ruby/ruby.h
localeinit.$(OBJEXT): {$(VPATH)}defines.h # localeinit.o: include/ruby/defines.h
localeinit.$(OBJEXT): {$(VPATH)}encoding.h # localeinit.o: include/ruby/encoding.h
localeinit.$(OBJEXT): {$(VPATH)}intern.h # localeinit.o: include/ruby/intern.h
localeinit.$(OBJEXT): {$(VPATH)}internal.h # localeinit.o: internal.h
localeinit.$(OBJEXT): {$(VPATH)}oniguruma.h # localeinit.o: include/ruby/oniguruma.h
localeinit.$(OBJEXT): {$(VPATH)}st.h # localeinit.o: include/ruby/st.h
localeinit.$(OBJEXT): {$(VPATH)}subst.h # localeinit.o: include/ruby/subst.h
main.$(OBJEXT): $(hdrdir)/ruby.h # main.o: include/ruby.h
main.$(OBJEXT): $(hdrdir)/ruby/ruby.h # main.o: include/ruby/ruby.h
main.$(OBJEXT): {$(VPATH)}config.h # main.o: .ext/include/x86_64-linux/ruby/config.h
main.$(OBJEXT): {$(VPATH)}defines.h # main.o: include/ruby/defines.h
main.$(OBJEXT): {$(VPATH)}intern.h # main.o: include/ruby/intern.h
main.$(OBJEXT): {$(VPATH)}missing.h # main.o: include/ruby/missing.h
main.$(OBJEXT): {$(VPATH)}node.h # main.o: node.h
main.$(OBJEXT): {$(VPATH)}st.h # main.o: include/ruby/st.h
main.$(OBJEXT): {$(VPATH)}subst.h # main.o: include/ruby/subst.h
main.$(OBJEXT): {$(VPATH)}vm_debug.h # main.o: vm_debug.h
marshal.$(OBJEXT): $(hdrdir)/ruby/ruby.h # marshal.o: include/ruby/ruby.h
marshal.$(OBJEXT): {$(VPATH)}defines.h # marshal.o: include/ruby/defines.h
marshal.$(OBJEXT): {$(VPATH)}encoding.h # marshal.o: include/ruby/encoding.h
marshal.$(OBJEXT): {$(VPATH)}intern.h # marshal.o: include/ruby/intern.h
marshal.$(OBJEXT): {$(VPATH)}internal.h # marshal.o: internal.h
marshal.$(OBJEXT): {$(VPATH)}io.h # marshal.o: include/ruby/io.h
marshal.$(OBJEXT): {$(VPATH)}oniguruma.h # marshal.o: include/ruby/oniguruma.h
marshal.$(OBJEXT): {$(VPATH)}st.h # marshal.o: include/ruby/st.h
marshal.$(OBJEXT): {$(VPATH)}subst.h # marshal.o: include/ruby/subst.h
marshal.$(OBJEXT): {$(VPATH)}util.h # marshal.o: include/ruby/util.h
math.$(OBJEXT): $(hdrdir)/ruby/ruby.h # math.o: include/ruby/ruby.h
math.$(OBJEXT): {$(VPATH)}defines.h # math.o: include/ruby/defines.h
math.$(OBJEXT): {$(VPATH)}intern.h # math.o: include/ruby/intern.h
math.$(OBJEXT): {$(VPATH)}internal.h # math.o: internal.h
math.$(OBJEXT): {$(VPATH)}st.h # math.o: include/ruby/st.h
math.$(OBJEXT): {$(VPATH)}subst.h # math.o: include/ruby/subst.h
miniinit.$(OBJEXT): $(hdrdir)/ruby/ruby.h # miniinit.o: include/ruby/ruby.h
miniinit.$(OBJEXT): {$(VPATH)}config.h # miniinit.o: .ext/include/x86_64-linux/ruby/config.h
miniinit.$(OBJEXT): {$(VPATH)}defines.h # miniinit.o: include/ruby/defines.h
miniinit.$(OBJEXT): {$(VPATH)}encoding.h # miniinit.o: include/ruby/encoding.h
miniinit.$(OBJEXT): {$(VPATH)}intern.h # miniinit.o: include/ruby/intern.h
miniinit.$(OBJEXT): {$(VPATH)}missing.h # miniinit.o: include/ruby/missing.h
miniinit.$(OBJEXT): {$(VPATH)}oniguruma.h # miniinit.o: include/ruby/oniguruma.h
miniinit.$(OBJEXT): {$(VPATH)}st.h # miniinit.o: include/ruby/st.h
miniinit.$(OBJEXT): {$(VPATH)}subst.h # miniinit.o: include/ruby/subst.h
miniprelude.$(OBJEXT): $(CCAN_DIR)/check_type/check_type.h # miniprelude.o: ccan/check_type/check_type.h
miniprelude.$(OBJEXT): $(CCAN_DIR)/container_of/container_of.h # miniprelude.o: ccan/container_of/container_of.h
miniprelude.$(OBJEXT): $(CCAN_DIR)/list/list.h # miniprelude.o: ccan/list/list.h
miniprelude.$(OBJEXT): $(CCAN_DIR)/str/str.h # miniprelude.o: ccan/str/str.h
miniprelude.$(OBJEXT): $(hdrdir)/ruby/ruby.h # miniprelude.o: include/ruby/ruby.h
miniprelude.$(OBJEXT): {$(VPATH)}config.h # miniprelude.o: .ext/include/x86_64-linux/ruby/config.h
miniprelude.$(OBJEXT): {$(VPATH)}defines.h # miniprelude.o: include/ruby/defines.h
miniprelude.$(OBJEXT): {$(VPATH)}id.h # miniprelude.o: id.h
miniprelude.$(OBJEXT): {$(VPATH)}intern.h # miniprelude.o: include/ruby/intern.h
miniprelude.$(OBJEXT): {$(VPATH)}internal.h # miniprelude.o: internal.h
miniprelude.$(OBJEXT): {$(VPATH)}method.h # miniprelude.o: method.h
miniprelude.$(OBJEXT): {$(VPATH)}missing.h # miniprelude.o: include/ruby/missing.h
miniprelude.$(OBJEXT): {$(VPATH)}node.h # miniprelude.o: node.h
miniprelude.$(OBJEXT): {$(VPATH)}ruby_atomic.h # miniprelude.o: ruby_atomic.h
miniprelude.$(OBJEXT): {$(VPATH)}st.h # miniprelude.o: include/ruby/st.h
miniprelude.$(OBJEXT): {$(VPATH)}subst.h # miniprelude.o: include/ruby/subst.h
miniprelude.$(OBJEXT): {$(VPATH)}thread_$(THREAD_MODEL).h # miniprelude.o: thread_pthread.h
miniprelude.$(OBJEXT): {$(VPATH)}thread_native.h # miniprelude.o: include/ruby/thread_native.h
miniprelude.$(OBJEXT): {$(VPATH)}vm_core.h # miniprelude.o: vm_core.h
miniprelude.$(OBJEXT): {$(VPATH)}vm_debug.h # miniprelude.o: vm_debug.h
miniprelude.$(OBJEXT): {$(VPATH)}vm_opts.h # miniprelude.o: vm_opts.h
newline.$(OBJEXT): $(hdrdir)/ruby/ruby.h # newline.o: include/ruby/ruby.h
newline.$(OBJEXT): {$(VPATH)}defines.h # newline.o: include/ruby/defines.h
newline.$(OBJEXT): {$(VPATH)}intern.h # newline.o: include/ruby/intern.h
newline.$(OBJEXT): {$(VPATH)}st.h # newline.o: include/ruby/st.h
newline.$(OBJEXT): {$(VPATH)}subst.h # newline.o: include/ruby/subst.h
newline.$(OBJEXT): {$(VPATH)}transcode_data.h # newline.o: transcode_data.h
node.$(OBJEXT): $(CCAN_DIR)/check_type/check_type.h # node.o: ccan/check_type/check_type.h
node.$(OBJEXT): $(CCAN_DIR)/container_of/container_of.h # node.o: ccan/container_of/container_of.h
node.$(OBJEXT): $(CCAN_DIR)/list/list.h # node.o: ccan/list/list.h
node.$(OBJEXT): $(CCAN_DIR)/str/str.h # node.o: ccan/str/str.h
node.$(OBJEXT): $(hdrdir)/ruby/ruby.h # node.o: include/ruby/ruby.h
node.$(OBJEXT): {$(VPATH)}defines.h # node.o: include/ruby/defines.h
node.$(OBJEXT): {$(VPATH)}id.h # node.o: id.h
node.$(OBJEXT): {$(VPATH)}intern.h # node.o: include/ruby/intern.h
node.$(OBJEXT): {$(VPATH)}internal.h # node.o: internal.h
node.$(OBJEXT): {$(VPATH)}method.h # node.o: method.h
node.$(OBJEXT): {$(VPATH)}node.h # node.o: node.h
node.$(OBJEXT): {$(VPATH)}ruby_atomic.h # node.o: ruby_atomic.h
node.$(OBJEXT): {$(VPATH)}st.h # node.o: include/ruby/st.h
node.$(OBJEXT): {$(VPATH)}subst.h # node.o: include/ruby/subst.h
node.$(OBJEXT): {$(VPATH)}thread_$(THREAD_MODEL).h # node.o: thread_pthread.h
node.$(OBJEXT): {$(VPATH)}thread_native.h # node.o: include/ruby/thread_native.h
node.$(OBJEXT): {$(VPATH)}vm_core.h # node.o: vm_core.h
node.$(OBJEXT): {$(VPATH)}vm_debug.h # node.o: vm_debug.h
node.$(OBJEXT): {$(VPATH)}vm_opts.h # node.o: vm_opts.h
numeric.$(OBJEXT): $(hdrdir)/ruby/ruby.h # numeric.o: include/ruby/ruby.h
numeric.$(OBJEXT): {$(VPATH)}defines.h # numeric.o: include/ruby/defines.h
numeric.$(OBJEXT): {$(VPATH)}encoding.h # numeric.o: include/ruby/encoding.h
numeric.$(OBJEXT): {$(VPATH)}id.h # numeric.o: id.h
numeric.$(OBJEXT): {$(VPATH)}intern.h # numeric.o: include/ruby/intern.h
numeric.$(OBJEXT): {$(VPATH)}internal.h # numeric.o: internal.h
numeric.$(OBJEXT): {$(VPATH)}oniguruma.h # numeric.o: include/ruby/oniguruma.h
numeric.$(OBJEXT): {$(VPATH)}st.h # numeric.o: include/ruby/st.h
numeric.$(OBJEXT): {$(VPATH)}subst.h # numeric.o: include/ruby/subst.h
numeric.$(OBJEXT): {$(VPATH)}util.h # numeric.o: include/ruby/util.h
object.$(OBJEXT): $(hdrdir)/ruby/ruby.h # object.o: include/ruby/ruby.h
object.$(OBJEXT): {$(VPATH)}constant.h # object.o: constant.h
object.$(OBJEXT): {$(VPATH)}defines.h # object.o: include/ruby/defines.h
object.$(OBJEXT): {$(VPATH)}encoding.h # object.o: include/ruby/encoding.h
object.$(OBJEXT): {$(VPATH)}id.h # object.o: id.h
object.$(OBJEXT): {$(VPATH)}intern.h # object.o: include/ruby/intern.h
object.$(OBJEXT): {$(VPATH)}internal.h # object.o: internal.h
object.$(OBJEXT): {$(VPATH)}oniguruma.h # object.o: include/ruby/oniguruma.h
object.$(OBJEXT): {$(VPATH)}probes.h # object.o: probes.h
object.$(OBJEXT): {$(VPATH)}st.h # object.o: include/ruby/st.h
object.$(OBJEXT): {$(VPATH)}subst.h # object.o: include/ruby/subst.h
object.$(OBJEXT): {$(VPATH)}util.h # object.o: include/ruby/util.h
object.$(OBJEXT): {$(VPATH)}vm_opts.h # object.o: vm_opts.h
pack.$(OBJEXT): $(hdrdir)/ruby/ruby.h # pack.o: include/ruby/ruby.h
pack.$(OBJEXT): {$(VPATH)}defines.h # pack.o: include/ruby/defines.h
pack.$(OBJEXT): {$(VPATH)}encoding.h # pack.o: include/ruby/encoding.h
pack.$(OBJEXT): {$(VPATH)}intern.h # pack.o: include/ruby/intern.h
pack.$(OBJEXT): {$(VPATH)}internal.h # pack.o: internal.h
pack.$(OBJEXT): {$(VPATH)}oniguruma.h # pack.o: include/ruby/oniguruma.h
pack.$(OBJEXT): {$(VPATH)}st.h # pack.o: include/ruby/st.h
pack.$(OBJEXT): {$(VPATH)}subst.h # pack.o: include/ruby/subst.h
parse.$(OBJEXT): $(hdrdir)/ruby/ruby.h # parse.o: include/ruby/ruby.h
parse.$(OBJEXT): {$(VPATH)}defines.h # parse.o: include/ruby/defines.h
parse.$(OBJEXT): {$(VPATH)}defs/keywords # parse.o: defs/keywords
parse.$(OBJEXT): {$(VPATH)}encoding.h # parse.o: include/ruby/encoding.h
parse.$(OBJEXT): {$(VPATH)}id.h # parse.o: id.h
parse.$(OBJEXT): {$(VPATH)}intern.h # parse.o: include/ruby/intern.h
parse.$(OBJEXT): {$(VPATH)}internal.h # parse.o: internal.h
parse.$(OBJEXT): {$(VPATH)}lex.c # parse.o: lex.c
parse.$(OBJEXT): {$(VPATH)}node.h # parse.o: node.h
parse.$(OBJEXT): {$(VPATH)}oniguruma.h # parse.o: include/ruby/oniguruma.h
parse.$(OBJEXT): {$(VPATH)}parse.h # parse.o: parse.h
parse.$(OBJEXT): {$(VPATH)}parse.y # parse.o: parse.y
parse.$(OBJEXT): {$(VPATH)}probes.h # parse.o: probes.h
parse.$(OBJEXT): {$(VPATH)}regenc.h # parse.o: regenc.h
parse.$(OBJEXT): {$(VPATH)}regex.h # parse.o: include/ruby/regex.h
parse.$(OBJEXT): {$(VPATH)}st.h # parse.o: include/ruby/st.h
parse.$(OBJEXT): {$(VPATH)}subst.h # parse.o: include/ruby/subst.h
parse.$(OBJEXT): {$(VPATH)}symbol.h # parse.o: symbol.h
parse.$(OBJEXT): {$(VPATH)}util.h # parse.o: include/ruby/util.h
parse.$(OBJEXT): {$(VPATH)}vm_opts.h # parse.o: vm_opts.h
prelude.$(OBJEXT): $(CCAN_DIR)/check_type/check_type.h # prelude.o: ccan/check_type/check_type.h
prelude.$(OBJEXT): $(CCAN_DIR)/container_of/container_of.h # prelude.o: ccan/container_of/container_of.h
prelude.$(OBJEXT): $(CCAN_DIR)/list/list.h # prelude.o: ccan/list/list.h
prelude.$(OBJEXT): $(CCAN_DIR)/str/str.h # prelude.o: ccan/str/str.h
prelude.$(OBJEXT): $(hdrdir)/ruby/ruby.h # prelude.o: include/ruby/ruby.h
prelude.$(OBJEXT): {$(VPATH)}defines.h # prelude.o: include/ruby/defines.h
prelude.$(OBJEXT): {$(VPATH)}id.h # prelude.o: id.h
prelude.$(OBJEXT): {$(VPATH)}intern.h # prelude.o: include/ruby/intern.h
prelude.$(OBJEXT): {$(VPATH)}internal.h # prelude.o: internal.h
prelude.$(OBJEXT): {$(VPATH)}method.h # prelude.o: method.h
prelude.$(OBJEXT): {$(VPATH)}node.h # prelude.o: node.h
prelude.$(OBJEXT): {$(VPATH)}ruby_atomic.h # prelude.o: ruby_atomic.h
prelude.$(OBJEXT): {$(VPATH)}st.h # prelude.o: include/ruby/st.h
prelude.$(OBJEXT): {$(VPATH)}subst.h # prelude.o: include/ruby/subst.h
prelude.$(OBJEXT): {$(VPATH)}thread_$(THREAD_MODEL).h # prelude.o: thread_pthread.h
prelude.$(OBJEXT): {$(VPATH)}thread_native.h # prelude.o: include/ruby/thread_native.h
prelude.$(OBJEXT): {$(VPATH)}vm_core.h # prelude.o: vm_core.h
prelude.$(OBJEXT): {$(VPATH)}vm_debug.h # prelude.o: vm_debug.h
prelude.$(OBJEXT): {$(VPATH)}vm_opts.h # prelude.o: vm_opts.h
proc.$(OBJEXT): $(CCAN_DIR)/check_type/check_type.h # proc.o: ccan/check_type/check_type.h
proc.$(OBJEXT): $(CCAN_DIR)/container_of/container_of.h # proc.o: ccan/container_of/container_of.h
proc.$(OBJEXT): $(CCAN_DIR)/list/list.h # proc.o: ccan/list/list.h
proc.$(OBJEXT): $(CCAN_DIR)/str/str.h # proc.o: ccan/str/str.h
proc.$(OBJEXT): $(hdrdir)/ruby/ruby.h # proc.o: include/ruby/ruby.h
proc.$(OBJEXT): {$(VPATH)}defines.h # proc.o: include/ruby/defines.h
proc.$(OBJEXT): {$(VPATH)}eval_intern.h # proc.o: eval_intern.h
proc.$(OBJEXT): {$(VPATH)}gc.h # proc.o: gc.h
proc.$(OBJEXT): {$(VPATH)}id.h # proc.o: id.h
proc.$(OBJEXT): {$(VPATH)}intern.h # proc.o: include/ruby/intern.h
proc.$(OBJEXT): {$(VPATH)}internal.h # proc.o: internal.h
proc.$(OBJEXT): {$(VPATH)}iseq.h # proc.o: iseq.h
proc.$(OBJEXT): {$(VPATH)}method.h # proc.o: method.h
proc.$(OBJEXT): {$(VPATH)}node.h # proc.o: node.h
proc.$(OBJEXT): {$(VPATH)}ruby_atomic.h # proc.o: ruby_atomic.h
proc.$(OBJEXT): {$(VPATH)}st.h # proc.o: include/ruby/st.h
proc.$(OBJEXT): {$(VPATH)}subst.h # proc.o: include/ruby/subst.h
proc.$(OBJEXT): {$(VPATH)}thread_$(THREAD_MODEL).h # proc.o: thread_pthread.h
proc.$(OBJEXT): {$(VPATH)}thread_native.h # proc.o: include/ruby/thread_native.h
proc.$(OBJEXT): {$(VPATH)}vm_core.h # proc.o: vm_core.h
proc.$(OBJEXT): {$(VPATH)}vm_debug.h # proc.o: vm_debug.h
proc.$(OBJEXT): {$(VPATH)}vm_opts.h # proc.o: vm_opts.h
process.$(OBJEXT): $(CCAN_DIR)/check_type/check_type.h # process.o: ccan/check_type/check_type.h
process.$(OBJEXT): $(CCAN_DIR)/container_of/container_of.h # process.o: ccan/container_of/container_of.h
process.$(OBJEXT): $(CCAN_DIR)/list/list.h # process.o: ccan/list/list.h
process.$(OBJEXT): $(CCAN_DIR)/str/str.h # process.o: ccan/str/str.h
process.$(OBJEXT): $(hdrdir)/ruby/ruby.h # process.o: include/ruby/ruby.h
process.$(OBJEXT): {$(VPATH)}defines.h # process.o: include/ruby/defines.h
process.$(OBJEXT): {$(VPATH)}dln.h # process.o: dln.h
process.$(OBJEXT): {$(VPATH)}encoding.h # process.o: include/ruby/encoding.h
process.$(OBJEXT): {$(VPATH)}id.h # process.o: id.h
process.$(OBJEXT): {$(VPATH)}intern.h # process.o: include/ruby/intern.h
process.$(OBJEXT): {$(VPATH)}internal.h # process.o: internal.h
process.$(OBJEXT): {$(VPATH)}io.h # process.o: include/ruby/io.h
process.$(OBJEXT): {$(VPATH)}method.h # process.o: method.h
process.$(OBJEXT): {$(VPATH)}node.h # process.o: node.h
process.$(OBJEXT): {$(VPATH)}oniguruma.h # process.o: include/ruby/oniguruma.h
process.$(OBJEXT): {$(VPATH)}ruby_atomic.h # process.o: ruby_atomic.h
process.$(OBJEXT): {$(VPATH)}st.h # process.o: include/ruby/st.h
process.$(OBJEXT): {$(VPATH)}subst.h # process.o: include/ruby/subst.h
process.$(OBJEXT): {$(VPATH)}thread.h # process.o: include/ruby/thread.h
process.$(OBJEXT): {$(VPATH)}thread_$(THREAD_MODEL).h # process.o: thread_pthread.h
process.$(OBJEXT): {$(VPATH)}thread_native.h # process.o: include/ruby/thread_native.h
process.$(OBJEXT): {$(VPATH)}util.h # process.o: include/ruby/util.h
process.$(OBJEXT): {$(VPATH)}vm_core.h # process.o: vm_core.h
process.$(OBJEXT): {$(VPATH)}vm_debug.h # process.o: vm_debug.h
process.$(OBJEXT): {$(VPATH)}vm_opts.h # process.o: vm_opts.h
random.$(OBJEXT): $(hdrdir)/ruby/ruby.h # random.o: include/ruby/ruby.h
random.$(OBJEXT): {$(VPATH)}defines.h # random.o: include/ruby/defines.h
random.$(OBJEXT): {$(VPATH)}intern.h # random.o: include/ruby/intern.h
random.$(OBJEXT): {$(VPATH)}internal.h # random.o: internal.h
random.$(OBJEXT): {$(VPATH)}siphash.c # random.o: siphash.c
random.$(OBJEXT): {$(VPATH)}siphash.h # random.o: siphash.h
random.$(OBJEXT): {$(VPATH)}st.h # random.o: include/ruby/st.h
random.$(OBJEXT): {$(VPATH)}subst.h # random.o: include/ruby/subst.h
range.$(OBJEXT): $(hdrdir)/ruby/ruby.h # range.o: include/ruby/ruby.h
range.$(OBJEXT): {$(VPATH)}defines.h # range.o: include/ruby/defines.h
range.$(OBJEXT): {$(VPATH)}encoding.h # range.o: include/ruby/encoding.h
range.$(OBJEXT): {$(VPATH)}id.h # range.o: id.h
range.$(OBJEXT): {$(VPATH)}intern.h # range.o: include/ruby/intern.h
range.$(OBJEXT): {$(VPATH)}internal.h # range.o: internal.h
range.$(OBJEXT): {$(VPATH)}oniguruma.h # range.o: include/ruby/oniguruma.h
range.$(OBJEXT): {$(VPATH)}st.h # range.o: include/ruby/st.h
range.$(OBJEXT): {$(VPATH)}subst.h # range.o: include/ruby/subst.h
rational.$(OBJEXT): $(hdrdir)/ruby.h # rational.o: include/ruby.h
rational.$(OBJEXT): $(hdrdir)/ruby/ruby.h # rational.o: include/ruby/ruby.h
rational.$(OBJEXT): {$(VPATH)}defines.h # rational.o: include/ruby/defines.h
rational.$(OBJEXT): {$(VPATH)}intern.h # rational.o: include/ruby/intern.h
rational.$(OBJEXT): {$(VPATH)}internal.h # rational.o: internal.h
rational.$(OBJEXT): {$(VPATH)}st.h # rational.o: include/ruby/st.h
rational.$(OBJEXT): {$(VPATH)}subst.h # rational.o: include/ruby/subst.h
re.$(OBJEXT): $(hdrdir)/ruby/ruby.h # re.o: include/ruby/ruby.h
re.$(OBJEXT): {$(VPATH)}defines.h # re.o: include/ruby/defines.h
re.$(OBJEXT): {$(VPATH)}encoding.h # re.o: include/ruby/encoding.h
re.$(OBJEXT): {$(VPATH)}intern.h # re.o: include/ruby/intern.h
re.$(OBJEXT): {$(VPATH)}internal.h # re.o: internal.h
re.$(OBJEXT): {$(VPATH)}oniguruma.h # re.o: include/ruby/oniguruma.h
re.$(OBJEXT): {$(VPATH)}re.h # re.o: include/ruby/re.h
re.$(OBJEXT): {$(VPATH)}regenc.h # re.o: regenc.h
re.$(OBJEXT): {$(VPATH)}regex.h # re.o: include/ruby/regex.h
re.$(OBJEXT): {$(VPATH)}regint.h # re.o: regint.h
re.$(OBJEXT): {$(VPATH)}st.h # re.o: include/ruby/st.h
re.$(OBJEXT): {$(VPATH)}subst.h # re.o: include/ruby/subst.h
re.$(OBJEXT): {$(VPATH)}util.h # re.o: include/ruby/util.h
regcomp.$(OBJEXT): $(hdrdir)/ruby/ruby.h # regcomp.o: include/ruby/ruby.h
regcomp.$(OBJEXT): {$(VPATH)}defines.h # regcomp.o: include/ruby/defines.h
regcomp.$(OBJEXT): {$(VPATH)}intern.h # regcomp.o: include/ruby/intern.h
regcomp.$(OBJEXT): {$(VPATH)}oniguruma.h # regcomp.o: include/ruby/oniguruma.h
regcomp.$(OBJEXT): {$(VPATH)}regenc.h # regcomp.o: regenc.h
regcomp.$(OBJEXT): {$(VPATH)}regint.h # regcomp.o: regint.h
regcomp.$(OBJEXT): {$(VPATH)}regparse.h # regcomp.o: regparse.h
regcomp.$(OBJEXT): {$(VPATH)}st.h # regcomp.o: include/ruby/st.h
regcomp.$(OBJEXT): {$(VPATH)}subst.h # regcomp.o: include/ruby/subst.h
regenc.$(OBJEXT): $(hdrdir)/ruby/ruby.h # regenc.o: include/ruby/ruby.h
regenc.$(OBJEXT): {$(VPATH)}defines.h # regenc.o: include/ruby/defines.h
regenc.$(OBJEXT): {$(VPATH)}intern.h # regenc.o: include/ruby/intern.h
regenc.$(OBJEXT): {$(VPATH)}oniguruma.h # regenc.o: include/ruby/oniguruma.h
regenc.$(OBJEXT): {$(VPATH)}regenc.h # regenc.o: regenc.h
regenc.$(OBJEXT): {$(VPATH)}regint.h # regenc.o: regint.h
regenc.$(OBJEXT): {$(VPATH)}st.h # regenc.o: include/ruby/st.h
regenc.$(OBJEXT): {$(VPATH)}subst.h # regenc.o: include/ruby/subst.h
regerror.$(OBJEXT): $(hdrdir)/ruby/ruby.h # regerror.o: include/ruby/ruby.h
regerror.$(OBJEXT): {$(VPATH)}defines.h # regerror.o: include/ruby/defines.h
regerror.$(OBJEXT): {$(VPATH)}intern.h # regerror.o: include/ruby/intern.h
regerror.$(OBJEXT): {$(VPATH)}oniguruma.h # regerror.o: include/ruby/oniguruma.h
regerror.$(OBJEXT): {$(VPATH)}regenc.h # regerror.o: regenc.h
regerror.$(OBJEXT): {$(VPATH)}regint.h # regerror.o: regint.h
regerror.$(OBJEXT): {$(VPATH)}st.h # regerror.o: include/ruby/st.h
regerror.$(OBJEXT): {$(VPATH)}subst.h # regerror.o: include/ruby/subst.h
regexec.$(OBJEXT): $(hdrdir)/ruby/ruby.h # regexec.o: include/ruby/ruby.h
regexec.$(OBJEXT): {$(VPATH)}defines.h # regexec.o: include/ruby/defines.h
regexec.$(OBJEXT): {$(VPATH)}intern.h # regexec.o: include/ruby/intern.h
regexec.$(OBJEXT): {$(VPATH)}oniguruma.h # regexec.o: include/ruby/oniguruma.h
regexec.$(OBJEXT): {$(VPATH)}regenc.h # regexec.o: regenc.h
regexec.$(OBJEXT): {$(VPATH)}regint.h # regexec.o: regint.h
regexec.$(OBJEXT): {$(VPATH)}st.h # regexec.o: include/ruby/st.h
regexec.$(OBJEXT): {$(VPATH)}subst.h # regexec.o: include/ruby/subst.h
regparse.$(OBJEXT): $(hdrdir)/ruby/ruby.h # regparse.o: include/ruby/ruby.h
regparse.$(OBJEXT): {$(VPATH)}defines.h # regparse.o: include/ruby/defines.h
regparse.$(OBJEXT): {$(VPATH)}intern.h # regparse.o: include/ruby/intern.h
regparse.$(OBJEXT): {$(VPATH)}oniguruma.h # regparse.o: include/ruby/oniguruma.h
regparse.$(OBJEXT): {$(VPATH)}regenc.h # regparse.o: regenc.h
regparse.$(OBJEXT): {$(VPATH)}regint.h # regparse.o: regint.h
regparse.$(OBJEXT): {$(VPATH)}regparse.h # regparse.o: regparse.h
regparse.$(OBJEXT): {$(VPATH)}st.h # regparse.o: include/ruby/st.h
regparse.$(OBJEXT): {$(VPATH)}subst.h # regparse.o: include/ruby/subst.h
regsyntax.$(OBJEXT): $(hdrdir)/ruby/ruby.h # regsyntax.o: include/ruby/ruby.h
regsyntax.$(OBJEXT): {$(VPATH)}defines.h # regsyntax.o: include/ruby/defines.h
regsyntax.$(OBJEXT): {$(VPATH)}intern.h # regsyntax.o: include/ruby/intern.h
regsyntax.$(OBJEXT): {$(VPATH)}oniguruma.h # regsyntax.o: include/ruby/oniguruma.h
regsyntax.$(OBJEXT): {$(VPATH)}regenc.h # regsyntax.o: regenc.h
regsyntax.$(OBJEXT): {$(VPATH)}regint.h # regsyntax.o: regint.h
regsyntax.$(OBJEXT): {$(VPATH)}st.h # regsyntax.o: include/ruby/st.h
regsyntax.$(OBJEXT): {$(VPATH)}subst.h # regsyntax.o: include/ruby/subst.h
ruby.$(OBJEXT): $(CCAN_DIR)/check_type/check_type.h # ruby.o: ccan/check_type/check_type.h
ruby.$(OBJEXT): $(CCAN_DIR)/container_of/container_of.h # ruby.o: ccan/container_of/container_of.h
ruby.$(OBJEXT): $(CCAN_DIR)/list/list.h # ruby.o: ccan/list/list.h
ruby.$(OBJEXT): $(CCAN_DIR)/str/str.h # ruby.o: ccan/str/str.h
ruby.$(OBJEXT): $(hdrdir)/ruby/ruby.h # ruby.o: include/ruby/ruby.h
ruby.$(OBJEXT): {$(VPATH)}defines.h # ruby.o: include/ruby/defines.h
ruby.$(OBJEXT): {$(VPATH)}dln.h # ruby.o: dln.h
ruby.$(OBJEXT): {$(VPATH)}encoding.h # ruby.o: include/ruby/encoding.h
ruby.$(OBJEXT): {$(VPATH)}eval_intern.h # ruby.o: eval_intern.h
ruby.$(OBJEXT): {$(VPATH)}id.h # ruby.o: id.h
ruby.$(OBJEXT): {$(VPATH)}intern.h # ruby.o: include/ruby/intern.h
ruby.$(OBJEXT): {$(VPATH)}internal.h # ruby.o: internal.h
ruby.$(OBJEXT): {$(VPATH)}method.h # ruby.o: method.h
ruby.$(OBJEXT): {$(VPATH)}node.h # ruby.o: node.h
ruby.$(OBJEXT): {$(VPATH)}oniguruma.h # ruby.o: include/ruby/oniguruma.h
ruby.$(OBJEXT): {$(VPATH)}ruby_atomic.h # ruby.o: ruby_atomic.h
ruby.$(OBJEXT): {$(VPATH)}st.h # ruby.o: include/ruby/st.h
ruby.$(OBJEXT): {$(VPATH)}subst.h # ruby.o: include/ruby/subst.h
ruby.$(OBJEXT): {$(VPATH)}thread_$(THREAD_MODEL).h # ruby.o: thread_pthread.h
ruby.$(OBJEXT): {$(VPATH)}thread_native.h # ruby.o: include/ruby/thread_native.h
ruby.$(OBJEXT): {$(VPATH)}util.h # ruby.o: include/ruby/util.h
ruby.$(OBJEXT): {$(VPATH)}vm_core.h # ruby.o: vm_core.h
ruby.$(OBJEXT): {$(VPATH)}vm_debug.h # ruby.o: vm_debug.h
ruby.$(OBJEXT): {$(VPATH)}vm_opts.h # ruby.o: vm_opts.h
safe.$(OBJEXT): $(CCAN_DIR)/check_type/check_type.h # safe.o: ccan/check_type/check_type.h
safe.$(OBJEXT): $(CCAN_DIR)/container_of/container_of.h # safe.o: ccan/container_of/container_of.h
safe.$(OBJEXT): $(CCAN_DIR)/list/list.h # safe.o: ccan/list/list.h
safe.$(OBJEXT): $(CCAN_DIR)/str/str.h # safe.o: ccan/str/str.h
safe.$(OBJEXT): $(hdrdir)/ruby/ruby.h # safe.o: include/ruby/ruby.h
safe.$(OBJEXT): {$(VPATH)}defines.h # safe.o: include/ruby/defines.h
safe.$(OBJEXT): {$(VPATH)}id.h # safe.o: id.h
safe.$(OBJEXT): {$(VPATH)}intern.h # safe.o: include/ruby/intern.h
safe.$(OBJEXT): {$(VPATH)}internal.h # safe.o: internal.h
safe.$(OBJEXT): {$(VPATH)}method.h # safe.o: method.h
safe.$(OBJEXT): {$(VPATH)}node.h # safe.o: node.h
safe.$(OBJEXT): {$(VPATH)}ruby_atomic.h # safe.o: ruby_atomic.h
safe.$(OBJEXT): {$(VPATH)}st.h # safe.o: include/ruby/st.h
safe.$(OBJEXT): {$(VPATH)}subst.h # safe.o: include/ruby/subst.h
safe.$(OBJEXT): {$(VPATH)}thread_$(THREAD_MODEL).h # safe.o: thread_pthread.h
safe.$(OBJEXT): {$(VPATH)}thread_native.h # safe.o: include/ruby/thread_native.h
safe.$(OBJEXT): {$(VPATH)}vm_core.h # safe.o: vm_core.h
safe.$(OBJEXT): {$(VPATH)}vm_debug.h # safe.o: vm_debug.h
safe.$(OBJEXT): {$(VPATH)}vm_opts.h # safe.o: vm_opts.h
setproctitle.$(OBJEXT): $(hdrdir)/ruby.h # setproctitle.o: include/ruby.h
setproctitle.$(OBJEXT): $(hdrdir)/ruby/ruby.h # setproctitle.o: include/ruby/ruby.h
setproctitle.$(OBJEXT): {$(VPATH)}defines.h # setproctitle.o: include/ruby/defines.h
setproctitle.$(OBJEXT): {$(VPATH)}intern.h # setproctitle.o: include/ruby/intern.h
setproctitle.$(OBJEXT): {$(VPATH)}st.h # setproctitle.o: include/ruby/st.h
setproctitle.$(OBJEXT): {$(VPATH)}subst.h # setproctitle.o: include/ruby/subst.h
setproctitle.$(OBJEXT): {$(VPATH)}util.h # setproctitle.o: include/ruby/util.h
signal.$(OBJEXT): $(CCAN_DIR)/check_type/check_type.h # signal.o: ccan/check_type/check_type.h
signal.$(OBJEXT): $(CCAN_DIR)/container_of/container_of.h # signal.o: ccan/container_of/container_of.h
signal.$(OBJEXT): $(CCAN_DIR)/list/list.h # signal.o: ccan/list/list.h
signal.$(OBJEXT): $(CCAN_DIR)/str/str.h # signal.o: ccan/str/str.h
signal.$(OBJEXT): $(hdrdir)/ruby/ruby.h # signal.o: include/ruby/ruby.h
signal.$(OBJEXT): {$(VPATH)}defines.h # signal.o: include/ruby/defines.h
signal.$(OBJEXT): {$(VPATH)}eval_intern.h # signal.o: eval_intern.h
signal.$(OBJEXT): {$(VPATH)}id.h # signal.o: id.h
signal.$(OBJEXT): {$(VPATH)}intern.h # signal.o: include/ruby/intern.h
signal.$(OBJEXT): {$(VPATH)}internal.h # signal.o: internal.h
signal.$(OBJEXT): {$(VPATH)}method.h # signal.o: method.h
signal.$(OBJEXT): {$(VPATH)}node.h # signal.o: node.h
signal.$(OBJEXT): {$(VPATH)}ruby_atomic.h # signal.o: ruby_atomic.h
signal.$(OBJEXT): {$(VPATH)}st.h # signal.o: include/ruby/st.h
signal.$(OBJEXT): {$(VPATH)}subst.h # signal.o: include/ruby/subst.h
signal.$(OBJEXT): {$(VPATH)}thread_$(THREAD_MODEL).h # signal.o: thread_pthread.h
signal.$(OBJEXT): {$(VPATH)}thread_native.h # signal.o: include/ruby/thread_native.h
signal.$(OBJEXT): {$(VPATH)}vm_core.h # signal.o: vm_core.h
signal.$(OBJEXT): {$(VPATH)}vm_debug.h # signal.o: vm_debug.h
signal.$(OBJEXT): {$(VPATH)}vm_opts.h # signal.o: vm_opts.h
sprintf.$(OBJEXT): $(hdrdir)/ruby/ruby.h # sprintf.o: include/ruby/ruby.h
sprintf.$(OBJEXT): {$(VPATH)}defines.h # sprintf.o: include/ruby/defines.h
sprintf.$(OBJEXT): {$(VPATH)}encoding.h # sprintf.o: include/ruby/encoding.h
sprintf.$(OBJEXT): {$(VPATH)}id.h # sprintf.o: id.h
sprintf.$(OBJEXT): {$(VPATH)}intern.h # sprintf.o: include/ruby/intern.h
sprintf.$(OBJEXT): {$(VPATH)}internal.h # sprintf.o: internal.h
sprintf.$(OBJEXT): {$(VPATH)}oniguruma.h # sprintf.o: include/ruby/oniguruma.h
sprintf.$(OBJEXT): {$(VPATH)}re.h # sprintf.o: include/ruby/re.h
sprintf.$(OBJEXT): {$(VPATH)}regex.h # sprintf.o: include/ruby/regex.h
sprintf.$(OBJEXT): {$(VPATH)}st.h # sprintf.o: include/ruby/st.h
sprintf.$(OBJEXT): {$(VPATH)}subst.h # sprintf.o: include/ruby/subst.h
sprintf.$(OBJEXT): {$(VPATH)}vsnprintf.c # sprintf.o: vsnprintf.c
st.$(OBJEXT): $(hdrdir)/ruby/ruby.h # st.o: include/ruby/ruby.h
st.$(OBJEXT): {$(VPATH)}defines.h # st.o: include/ruby/defines.h
st.$(OBJEXT): {$(VPATH)}intern.h # st.o: include/ruby/intern.h
st.$(OBJEXT): {$(VPATH)}internal.h # st.o: internal.h
st.$(OBJEXT): {$(VPATH)}st.h # st.o: include/ruby/st.h
st.$(OBJEXT): {$(VPATH)}subst.h # st.o: include/ruby/subst.h
strftime.$(OBJEXT): $(hdrdir)/ruby/ruby.h # strftime.o: include/ruby/ruby.h
strftime.$(OBJEXT): {$(VPATH)}defines.h # strftime.o: include/ruby/defines.h
strftime.$(OBJEXT): {$(VPATH)}encoding.h # strftime.o: include/ruby/encoding.h
strftime.$(OBJEXT): {$(VPATH)}intern.h # strftime.o: include/ruby/intern.h
strftime.$(OBJEXT): {$(VPATH)}oniguruma.h # strftime.o: include/ruby/oniguruma.h
strftime.$(OBJEXT): {$(VPATH)}st.h # strftime.o: include/ruby/st.h
strftime.$(OBJEXT): {$(VPATH)}subst.h # strftime.o: include/ruby/subst.h
strftime.$(OBJEXT): {$(VPATH)}timev.h # strftime.o: timev.h
string.$(OBJEXT): $(hdrdir)/ruby/ruby.h # string.o: include/ruby/ruby.h
string.$(OBJEXT): {$(VPATH)}defines.h # string.o: include/ruby/defines.h
string.$(OBJEXT): {$(VPATH)}encoding.h # string.o: include/ruby/encoding.h
string.$(OBJEXT): {$(VPATH)}gc.h # string.o: gc.h
string.$(OBJEXT): {$(VPATH)}intern.h # string.o: include/ruby/intern.h
string.$(OBJEXT): {$(VPATH)}internal.h # string.o: internal.h
string.$(OBJEXT): {$(VPATH)}oniguruma.h # string.o: include/ruby/oniguruma.h
string.$(OBJEXT): {$(VPATH)}probes.h # string.o: probes.h
string.$(OBJEXT): {$(VPATH)}re.h # string.o: include/ruby/re.h
string.$(OBJEXT): {$(VPATH)}regex.h # string.o: include/ruby/regex.h
string.$(OBJEXT): {$(VPATH)}st.h # string.o: include/ruby/st.h
string.$(OBJEXT): {$(VPATH)}subst.h # string.o: include/ruby/subst.h
string.$(OBJEXT): {$(VPATH)}vm_opts.h # string.o: vm_opts.h
struct.$(OBJEXT): $(hdrdir)/ruby/ruby.h # struct.o: include/ruby/ruby.h
struct.$(OBJEXT): {$(VPATH)}defines.h # struct.o: include/ruby/defines.h
struct.$(OBJEXT): {$(VPATH)}intern.h # struct.o: include/ruby/intern.h
struct.$(OBJEXT): {$(VPATH)}internal.h # struct.o: internal.h
struct.$(OBJEXT): {$(VPATH)}st.h # struct.o: include/ruby/st.h
struct.$(OBJEXT): {$(VPATH)}subst.h # struct.o: include/ruby/subst.h
symbol.$(OBJEXT): $(hdrdir)/ruby/ruby.h # symbol.o: include/ruby/ruby.h
symbol.$(OBJEXT): {$(VPATH)}defines.h # symbol.o: include/ruby/defines.h
symbol.$(OBJEXT): {$(VPATH)}encoding.h # symbol.o: include/ruby/encoding.h
symbol.$(OBJEXT): {$(VPATH)}gc.h # symbol.o: gc.h
symbol.$(OBJEXT): {$(VPATH)}id.c # symbol.o: id.c
symbol.$(OBJEXT): {$(VPATH)}id.h # symbol.o: id.h
symbol.$(OBJEXT): {$(VPATH)}intern.h # symbol.o: include/ruby/intern.h
symbol.$(OBJEXT): {$(VPATH)}internal.h # symbol.o: internal.h
symbol.$(OBJEXT): {$(VPATH)}node.h # symbol.o: node.h
symbol.$(OBJEXT): {$(VPATH)}oniguruma.h # symbol.o: include/ruby/oniguruma.h
symbol.$(OBJEXT): {$(VPATH)}probes.h # symbol.o: probes.h
symbol.$(OBJEXT): {$(VPATH)}st.h # symbol.o: include/ruby/st.h
symbol.$(OBJEXT): {$(VPATH)}subst.h # symbol.o: include/ruby/subst.h
symbol.$(OBJEXT): {$(VPATH)}symbol.h # symbol.o: symbol.h
symbol.$(OBJEXT): {$(VPATH)}vm_opts.h # symbol.o: vm_opts.h
thread.$(OBJEXT): $(CCAN_DIR)/check_type/check_type.h # thread.o: ccan/check_type/check_type.h
thread.$(OBJEXT): $(CCAN_DIR)/container_of/container_of.h # thread.o: ccan/container_of/container_of.h
thread.$(OBJEXT): $(CCAN_DIR)/list/list.h # thread.o: ccan/list/list.h
thread.$(OBJEXT): $(CCAN_DIR)/str/str.h # thread.o: ccan/str/str.h
thread.$(OBJEXT): $(hdrdir)/ruby/ruby.h # thread.o: include/ruby/ruby.h
thread.$(OBJEXT): {$(VPATH)}defines.h # thread.o: include/ruby/defines.h
thread.$(OBJEXT): {$(VPATH)}encoding.h # thread.o: include/ruby/encoding.h
thread.$(OBJEXT): {$(VPATH)}eval_intern.h # thread.o: eval_intern.h
thread.$(OBJEXT): {$(VPATH)}gc.h # thread.o: gc.h
thread.$(OBJEXT): {$(VPATH)}id.h # thread.o: id.h
thread.$(OBJEXT): {$(VPATH)}intern.h # thread.o: include/ruby/intern.h
thread.$(OBJEXT): {$(VPATH)}internal.h # thread.o: internal.h
thread.$(OBJEXT): {$(VPATH)}io.h # thread.o: include/ruby/io.h
thread.$(OBJEXT): {$(VPATH)}method.h # thread.o: method.h
thread.$(OBJEXT): {$(VPATH)}node.h # thread.o: node.h
thread.$(OBJEXT): {$(VPATH)}oniguruma.h # thread.o: include/ruby/oniguruma.h
thread.$(OBJEXT): {$(VPATH)}ruby_atomic.h # thread.o: ruby_atomic.h
thread.$(OBJEXT): {$(VPATH)}st.h # thread.o: include/ruby/st.h
thread.$(OBJEXT): {$(VPATH)}subst.h # thread.o: include/ruby/subst.h
thread.$(OBJEXT): {$(VPATH)}thread.h # thread.o: include/ruby/thread.h
thread.$(OBJEXT): {$(VPATH)}thread_$(THREAD_MODEL).c # thread.o: thread_pthread.c
thread.$(OBJEXT): {$(VPATH)}thread_$(THREAD_MODEL).h # thread.o: thread_pthread.h
thread.$(OBJEXT): {$(VPATH)}thread_native.h # thread.o: include/ruby/thread_native.h
thread.$(OBJEXT): {$(VPATH)}timev.h # thread.o: timev.h
thread.$(OBJEXT): {$(VPATH)}vm_core.h # thread.o: vm_core.h
thread.$(OBJEXT): {$(VPATH)}vm_debug.h # thread.o: vm_debug.h
thread.$(OBJEXT): {$(VPATH)}vm_opts.h # thread.o: vm_opts.h
time.$(OBJEXT): $(hdrdir)/ruby/ruby.h # time.o: include/ruby/ruby.h
time.$(OBJEXT): {$(VPATH)}defines.h # time.o: include/ruby/defines.h
time.$(OBJEXT): {$(VPATH)}encoding.h # time.o: include/ruby/encoding.h
time.$(OBJEXT): {$(VPATH)}intern.h # time.o: include/ruby/intern.h
time.$(OBJEXT): {$(VPATH)}internal.h # time.o: internal.h
time.$(OBJEXT): {$(VPATH)}oniguruma.h # time.o: include/ruby/oniguruma.h
time.$(OBJEXT): {$(VPATH)}st.h # time.o: include/ruby/st.h
time.$(OBJEXT): {$(VPATH)}subst.h # time.o: include/ruby/subst.h
time.$(OBJEXT): {$(VPATH)}timev.h # time.o: timev.h
transcode.$(OBJEXT): $(hdrdir)/ruby/ruby.h # transcode.o: include/ruby/ruby.h
transcode.$(OBJEXT): {$(VPATH)}defines.h # transcode.o: include/ruby/defines.h
transcode.$(OBJEXT): {$(VPATH)}encoding.h # transcode.o: include/ruby/encoding.h
transcode.$(OBJEXT): {$(VPATH)}intern.h # transcode.o: include/ruby/intern.h
transcode.$(OBJEXT): {$(VPATH)}internal.h # transcode.o: internal.h
transcode.$(OBJEXT): {$(VPATH)}oniguruma.h # transcode.o: include/ruby/oniguruma.h
transcode.$(OBJEXT): {$(VPATH)}st.h # transcode.o: include/ruby/st.h
transcode.$(OBJEXT): {$(VPATH)}subst.h # transcode.o: include/ruby/subst.h
transcode.$(OBJEXT): {$(VPATH)}transcode_data.h # transcode.o: transcode_data.h
unicode.$(OBJEXT): $(hdrdir)/ruby/ruby.h # unicode.o: include/ruby/ruby.h
unicode.$(OBJEXT): {$(VPATH)}defines.h # unicode.o: include/ruby/defines.h
unicode.$(OBJEXT): {$(VPATH)}intern.h # unicode.o: include/ruby/intern.h
unicode.$(OBJEXT): {$(VPATH)}oniguruma.h # unicode.o: include/ruby/oniguruma.h
unicode.$(OBJEXT): {$(VPATH)}regenc.h # unicode.o: regenc.h
unicode.$(OBJEXT): {$(VPATH)}regint.h # unicode.o: regint.h
unicode.$(OBJEXT): {$(VPATH)}st.h # unicode.o: include/ruby/st.h
unicode.$(OBJEXT): {$(VPATH)}subst.h # unicode.o: include/ruby/subst.h
unicode.$(OBJEXT): {$(VPATH)}unicode/casefold.h # unicode.o: enc/unicode/casefold.h
unicode.$(OBJEXT): {$(VPATH)}unicode/name2ctype.h # unicode.o: enc/unicode/name2ctype.h
us_ascii.$(OBJEXT): {$(VPATH)}defines.h # us_ascii.o: include/ruby/defines.h
us_ascii.$(OBJEXT): {$(VPATH)}oniguruma.h # us_ascii.o: include/ruby/oniguruma.h
us_ascii.$(OBJEXT): {$(VPATH)}regenc.h # us_ascii.o: regenc.h
utf_8.$(OBJEXT): {$(VPATH)}defines.h # utf_8.o: include/ruby/defines.h
utf_8.$(OBJEXT): {$(VPATH)}oniguruma.h # utf_8.o: include/ruby/oniguruma.h
utf_8.$(OBJEXT): {$(VPATH)}regenc.h # utf_8.o: regenc.h
util.$(OBJEXT): $(hdrdir)/ruby/ruby.h # util.o: include/ruby/ruby.h
util.$(OBJEXT): {$(VPATH)}defines.h # util.o: include/ruby/defines.h
util.$(OBJEXT): {$(VPATH)}intern.h # util.o: include/ruby/intern.h
util.$(OBJEXT): {$(VPATH)}internal.h # util.o: internal.h
util.$(OBJEXT): {$(VPATH)}st.h # util.o: include/ruby/st.h
util.$(OBJEXT): {$(VPATH)}subst.h # util.o: include/ruby/subst.h
util.$(OBJEXT): {$(VPATH)}util.h # util.o: include/ruby/util.h
variable.$(OBJEXT): $(hdrdir)/ruby/ruby.h # variable.o: include/ruby/ruby.h
variable.$(OBJEXT): {$(VPATH)}constant.h # variable.o: constant.h
variable.$(OBJEXT): {$(VPATH)}defines.h # variable.o: include/ruby/defines.h
variable.$(OBJEXT): {$(VPATH)}encoding.h # variable.o: include/ruby/encoding.h
variable.$(OBJEXT): {$(VPATH)}id.h # variable.o: id.h
variable.$(OBJEXT): {$(VPATH)}intern.h # variable.o: include/ruby/intern.h
variable.$(OBJEXT): {$(VPATH)}internal.h # variable.o: internal.h
variable.$(OBJEXT): {$(VPATH)}node.h # variable.o: node.h
variable.$(OBJEXT): {$(VPATH)}oniguruma.h # variable.o: include/ruby/oniguruma.h
variable.$(OBJEXT): {$(VPATH)}st.h # variable.o: include/ruby/st.h
variable.$(OBJEXT): {$(VPATH)}subst.h # variable.o: include/ruby/subst.h
variable.$(OBJEXT): {$(VPATH)}util.h # variable.o: include/ruby/util.h
version.$(OBJEXT): $(hdrdir)/ruby/ruby.h # version.o: include/ruby/ruby.h
version.$(OBJEXT): $(srcdir)/include/ruby/version.h # version.o: include/ruby/version.h
version.$(OBJEXT): $(srcdir)/revision.h # version.o: revision.h
version.$(OBJEXT): $(srcdir)/version.h # version.o: version.h
version.$(OBJEXT): {$(VPATH)}defines.h # version.o: include/ruby/defines.h
version.$(OBJEXT): {$(VPATH)}intern.h # version.o: include/ruby/intern.h
version.$(OBJEXT): {$(VPATH)}st.h # version.o: include/ruby/st.h
version.$(OBJEXT): {$(VPATH)}subst.h # version.o: include/ruby/subst.h
vm.$(OBJEXT): $(CCAN_DIR)/check_type/check_type.h # vm.o: ccan/check_type/check_type.h
vm.$(OBJEXT): $(CCAN_DIR)/container_of/container_of.h # vm.o: ccan/container_of/container_of.h
vm.$(OBJEXT): $(CCAN_DIR)/list/list.h # vm.o: ccan/list/list.h
vm.$(OBJEXT): $(CCAN_DIR)/str/str.h # vm.o: ccan/str/str.h
vm.$(OBJEXT): $(hdrdir)/ruby/ruby.h # vm.o: include/ruby/ruby.h
vm.$(OBJEXT): {$(VPATH)}constant.h # vm.o: constant.h
vm.$(OBJEXT): {$(VPATH)}defines.h # vm.o: include/ruby/defines.h
vm.$(OBJEXT): {$(VPATH)}encoding.h # vm.o: include/ruby/encoding.h
vm.$(OBJEXT): {$(VPATH)}eval_intern.h # vm.o: eval_intern.h
vm.$(OBJEXT): {$(VPATH)}gc.h # vm.o: gc.h
vm.$(OBJEXT): {$(VPATH)}id.h # vm.o: id.h
vm.$(OBJEXT): {$(VPATH)}insns.def # vm.o: insns.def
vm.$(OBJEXT): {$(VPATH)}insns.inc # vm.o: insns.inc
vm.$(OBJEXT): {$(VPATH)}intern.h # vm.o: include/ruby/intern.h
vm.$(OBJEXT): {$(VPATH)}internal.h # vm.o: internal.h
vm.$(OBJEXT): {$(VPATH)}iseq.h # vm.o: iseq.h
vm.$(OBJEXT): {$(VPATH)}method.h # vm.o: method.h
vm.$(OBJEXT): {$(VPATH)}node.h # vm.o: node.h
vm.$(OBJEXT): {$(VPATH)}oniguruma.h # vm.o: include/ruby/oniguruma.h
vm.$(OBJEXT): {$(VPATH)}probes.h # vm.o: probes.h
vm.$(OBJEXT): {$(VPATH)}probes_helper.h # vm.o: probes_helper.h
vm.$(OBJEXT): {$(VPATH)}ruby_atomic.h # vm.o: ruby_atomic.h
vm.$(OBJEXT): {$(VPATH)}st.h # vm.o: include/ruby/st.h
vm.$(OBJEXT): {$(VPATH)}subst.h # vm.o: include/ruby/subst.h
vm.$(OBJEXT): {$(VPATH)}thread_$(THREAD_MODEL).h # vm.o: thread_pthread.h
vm.$(OBJEXT): {$(VPATH)}thread_native.h # vm.o: include/ruby/thread_native.h
vm.$(OBJEXT): {$(VPATH)}vm.h # vm.o: include/ruby/vm.h
vm.$(OBJEXT): {$(VPATH)}vm.inc # vm.o: vm.inc
vm.$(OBJEXT): {$(VPATH)}vm_args.c # vm.o: vm_args.c
vm.$(OBJEXT): {$(VPATH)}vm_core.h # vm.o: vm_core.h
vm.$(OBJEXT): {$(VPATH)}vm_debug.h # vm.o: vm_debug.h
vm.$(OBJEXT): {$(VPATH)}vm_eval.c # vm.o: vm_eval.c
vm.$(OBJEXT): {$(VPATH)}vm_exec.c # vm.o: vm_exec.c
vm.$(OBJEXT): {$(VPATH)}vm_exec.h # vm.o: vm_exec.h
vm.$(OBJEXT): {$(VPATH)}vm_insnhelper.c # vm.o: vm_insnhelper.c
vm.$(OBJEXT): {$(VPATH)}vm_insnhelper.h # vm.o: vm_insnhelper.h
vm.$(OBJEXT): {$(VPATH)}vm_method.c # vm.o: vm_method.c
vm.$(OBJEXT): {$(VPATH)}vm_opts.h # vm.o: vm_opts.h
vm.$(OBJEXT): {$(VPATH)}vmtc.inc # vm.o: vmtc.inc
vm_backtrace.$(OBJEXT): $(CCAN_DIR)/check_type/check_type.h # vm_backtrace.o: ccan/check_type/check_type.h
vm_backtrace.$(OBJEXT): $(CCAN_DIR)/container_of/container_of.h # vm_backtrace.o: ccan/container_of/container_of.h
vm_backtrace.$(OBJEXT): $(CCAN_DIR)/list/list.h # vm_backtrace.o: ccan/list/list.h
vm_backtrace.$(OBJEXT): $(CCAN_DIR)/str/str.h # vm_backtrace.o: ccan/str/str.h
vm_backtrace.$(OBJEXT): $(hdrdir)/ruby/ruby.h # vm_backtrace.o: include/ruby/ruby.h
vm_backtrace.$(OBJEXT): {$(VPATH)}debug.h # vm_backtrace.o: include/ruby/debug.h
vm_backtrace.$(OBJEXT): {$(VPATH)}defines.h # vm_backtrace.o: include/ruby/defines.h
vm_backtrace.$(OBJEXT): {$(VPATH)}encoding.h # vm_backtrace.o: include/ruby/encoding.h
vm_backtrace.$(OBJEXT): {$(VPATH)}eval_intern.h # vm_backtrace.o: eval_intern.h
vm_backtrace.$(OBJEXT): {$(VPATH)}id.h # vm_backtrace.o: id.h
vm_backtrace.$(OBJEXT): {$(VPATH)}intern.h # vm_backtrace.o: include/ruby/intern.h
vm_backtrace.$(OBJEXT): {$(VPATH)}internal.h # vm_backtrace.o: internal.h
vm_backtrace.$(OBJEXT): {$(VPATH)}iseq.h # vm_backtrace.o: iseq.h
vm_backtrace.$(OBJEXT): {$(VPATH)}method.h # vm_backtrace.o: method.h
vm_backtrace.$(OBJEXT): {$(VPATH)}node.h # vm_backtrace.o: node.h
vm_backtrace.$(OBJEXT): {$(VPATH)}oniguruma.h # vm_backtrace.o: include/ruby/oniguruma.h
vm_backtrace.$(OBJEXT): {$(VPATH)}ruby_atomic.h # vm_backtrace.o: ruby_atomic.h
vm_backtrace.$(OBJEXT): {$(VPATH)}st.h # vm_backtrace.o: include/ruby/st.h
vm_backtrace.$(OBJEXT): {$(VPATH)}subst.h # vm_backtrace.o: include/ruby/subst.h
vm_backtrace.$(OBJEXT): {$(VPATH)}thread_$(THREAD_MODEL).h # vm_backtrace.o: thread_pthread.h
vm_backtrace.$(OBJEXT): {$(VPATH)}thread_native.h # vm_backtrace.o: include/ruby/thread_native.h
vm_backtrace.$(OBJEXT): {$(VPATH)}vm_core.h # vm_backtrace.o: vm_core.h
vm_backtrace.$(OBJEXT): {$(VPATH)}vm_debug.h # vm_backtrace.o: vm_debug.h
vm_backtrace.$(OBJEXT): {$(VPATH)}vm_opts.h # vm_backtrace.o: vm_opts.h
vm_dump.$(OBJEXT): $(CCAN_DIR)/check_type/check_type.h # vm_dump.o: ccan/check_type/check_type.h
vm_dump.$(OBJEXT): $(CCAN_DIR)/container_of/container_of.h # vm_dump.o: ccan/container_of/container_of.h
vm_dump.$(OBJEXT): $(CCAN_DIR)/list/list.h # vm_dump.o: ccan/list/list.h
vm_dump.$(OBJEXT): $(CCAN_DIR)/str/str.h # vm_dump.o: ccan/str/str.h
vm_dump.$(OBJEXT): $(hdrdir)/ruby/ruby.h # vm_dump.o: include/ruby/ruby.h
vm_dump.$(OBJEXT): {$(VPATH)}addr2line.h # vm_dump.o: addr2line.h
vm_dump.$(OBJEXT): {$(VPATH)}defines.h # vm_dump.o: include/ruby/defines.h
vm_dump.$(OBJEXT): {$(VPATH)}id.h # vm_dump.o: id.h
vm_dump.$(OBJEXT): {$(VPATH)}intern.h # vm_dump.o: include/ruby/intern.h
vm_dump.$(OBJEXT): {$(VPATH)}internal.h # vm_dump.o: internal.h
vm_dump.$(OBJEXT): {$(VPATH)}iseq.h # vm_dump.o: iseq.h
vm_dump.$(OBJEXT): {$(VPATH)}method.h # vm_dump.o: method.h
vm_dump.$(OBJEXT): {$(VPATH)}node.h # vm_dump.o: node.h
vm_dump.$(OBJEXT): {$(VPATH)}ruby_atomic.h # vm_dump.o: ruby_atomic.h
vm_dump.$(OBJEXT): {$(VPATH)}st.h # vm_dump.o: include/ruby/st.h
vm_dump.$(OBJEXT): {$(VPATH)}subst.h # vm_dump.o: include/ruby/subst.h
vm_dump.$(OBJEXT): {$(VPATH)}thread_$(THREAD_MODEL).h # vm_dump.o: thread_pthread.h
vm_dump.$(OBJEXT): {$(VPATH)}thread_native.h # vm_dump.o: include/ruby/thread_native.h
vm_dump.$(OBJEXT): {$(VPATH)}vm_core.h # vm_dump.o: vm_core.h
vm_dump.$(OBJEXT): {$(VPATH)}vm_debug.h # vm_dump.o: vm_debug.h
vm_dump.$(OBJEXT): {$(VPATH)}vm_opts.h # vm_dump.o: vm_opts.h
vm_trace.$(OBJEXT): $(CCAN_DIR)/check_type/check_type.h # vm_trace.o: ccan/check_type/check_type.h
vm_trace.$(OBJEXT): $(CCAN_DIR)/container_of/container_of.h # vm_trace.o: ccan/container_of/container_of.h
vm_trace.$(OBJEXT): $(CCAN_DIR)/list/list.h # vm_trace.o: ccan/list/list.h
vm_trace.$(OBJEXT): $(CCAN_DIR)/str/str.h # vm_trace.o: ccan/str/str.h
vm_trace.$(OBJEXT): $(hdrdir)/ruby/ruby.h # vm_trace.o: include/ruby/ruby.h
vm_trace.$(OBJEXT): {$(VPATH)}debug.h # vm_trace.o: include/ruby/debug.h
vm_trace.$(OBJEXT): {$(VPATH)}defines.h # vm_trace.o: include/ruby/defines.h
vm_trace.$(OBJEXT): {$(VPATH)}encoding.h # vm_trace.o: include/ruby/encoding.h
vm_trace.$(OBJEXT): {$(VPATH)}eval_intern.h # vm_trace.o: eval_intern.h
vm_trace.$(OBJEXT): {$(VPATH)}id.h # vm_trace.o: id.h
vm_trace.$(OBJEXT): {$(VPATH)}intern.h # vm_trace.o: include/ruby/intern.h
vm_trace.$(OBJEXT): {$(VPATH)}internal.h # vm_trace.o: internal.h
vm_trace.$(OBJEXT): {$(VPATH)}method.h # vm_trace.o: method.h
vm_trace.$(OBJEXT): {$(VPATH)}node.h # vm_trace.o: node.h
vm_trace.$(OBJEXT): {$(VPATH)}oniguruma.h # vm_trace.o: include/ruby/oniguruma.h
vm_trace.$(OBJEXT): {$(VPATH)}ruby_atomic.h # vm_trace.o: ruby_atomic.h
vm_trace.$(OBJEXT): {$(VPATH)}st.h # vm_trace.o: include/ruby/st.h
vm_trace.$(OBJEXT): {$(VPATH)}subst.h # vm_trace.o: include/ruby/subst.h
vm_trace.$(OBJEXT): {$(VPATH)}thread_$(THREAD_MODEL).h # vm_trace.o: thread_pthread.h
vm_trace.$(OBJEXT): {$(VPATH)}thread_native.h # vm_trace.o: include/ruby/thread_native.h
vm_trace.$(OBJEXT): {$(VPATH)}vm_core.h # vm_trace.o: vm_core.h
vm_trace.$(OBJEXT): {$(VPATH)}vm_debug.h # vm_trace.o: vm_debug.h
vm_trace.$(OBJEXT): {$(VPATH)}vm_opts.h # vm_trace.o: vm_opts.h
