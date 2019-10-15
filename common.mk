# -*- mode: makefile-gmake; indent-tabs-mode: t -*-

bin: $(PROGRAM) $(WPROGRAM)
lib: $(LIBRUBY)
dll: $(LIBRUBY_SO)

.SUFFIXES: .inc .h .c .y .i .$(ASMEXT) .$(DTRACE_EXT)

# V=0 quiet, V=1 verbose.  other values don't work.
V = 0
Q1 = $(V:1=)
Q = $(Q1:0=@)
ECHO0 = $(ECHO1:0=echo)
ECHO = @$(ECHO0)

mflags = $(MFLAGS)
gnumake_recursive =
enable_shared = $(ENABLE_SHARED:no=)

UNICODE_VERSION = 12.1.0
UNICODE_EMOJI_VERSION = 12.0
UNICODE_BETA = NO

### set the following environment variable or uncomment the line if
### the Unicode data files should be updated completely on every update ('make up',...).
# ALWAYS_UPDATE_UNICODE = yes
UNICODE_DATA_DIR = enc/unicode/data/$(UNICODE_VERSION)/ucd
UNICODE_SRC_DATA_DIR = $(srcdir)/$(UNICODE_DATA_DIR)
UNICODE_SRC_EMOJI_DATA_DIR = $(srcdir)/enc/unicode/data/emoji/$(UNICODE_EMOJI_VERSION)
UNICODE_HDR_DIR = $(srcdir)/enc/unicode/$(UNICODE_VERSION)
UNICODE_DATA_HEADERS = \
	$(UNICODE_HDR_DIR)/casefold.h \
	$(UNICODE_HDR_DIR)/name2ctype.h \
	$(empty)

RUBY_RELEASE_DATE = $(RUBY_RELEASE_YEAR)-$(RUBY_RELEASE_MONTH)-$(RUBY_RELEASE_DAY)
RUBYLIB       = $(PATH_SEPARATOR)
RUBYOPT       = -
RUN_OPTS      = --disable-gems

GITPULLOPTIONS = --rebase

INCFLAGS = -I. -I$(arch_hdrdir) -I$(hdrdir) -I$(srcdir) -I$(UNICODE_HDR_DIR)

GEM_HOME =
GEM_PATH =
GEM_VENDOR =

BENCHMARK_DRIVER_GIT_URL = https://github.com/benchmark-driver/benchmark-driver
BENCHMARK_DRIVER_GIT_REF = v0.15.6
SIMPLECOV_GIT_URL = https://github.com/colszowka/simplecov.git
SIMPLECOV_GIT_REF = v0.17.0
SIMPLECOV_HTML_GIT_URL = https://github.com/colszowka/simplecov-html.git
SIMPLECOV_HTML_GIT_REF = v0.10.2
DOCLIE_GIT_URL = https://github.com/ms-ati/docile.git
DOCLIE_GIT_REF = v1.3.2

STATIC_RUBY   = static-ruby

TIMESTAMPDIR  = $(EXTOUT)/.timestamp
EXTCONF       = extconf.rb
LIBRUBY_EXTS  = ./.libruby-with-ext.time
REVISION_H    = ./.revision.time
PLATFORM_D    = $(TIMESTAMPDIR)/.$(PLATFORM_DIR).time
ENC_TRANS_D   = $(TIMESTAMPDIR)/.enc-trans.time
RDOC          = $(XRUBY) "$(srcdir)/libexec/rdoc" --root "$(srcdir)" --encoding=UTF-8 --all
RDOCOUT       = $(EXTOUT)/rdoc
HTMLOUT       = $(EXTOUT)/html
CAPIOUT       = doc/capi
INSTALL_DOC_OPTS = --rdoc-output="$(RDOCOUT)" --html-output="$(HTMLOUT)"
RDOC_GEN_OPTS = --page-dir "$(srcdir)/doc" --no-force-update

INITOBJS      = dmyext.$(OBJEXT) dmyenc.$(OBJEXT)
NORMALMAINOBJ = main.$(OBJEXT)
MAINOBJ       = $(NORMALMAINOBJ)
DLDOBJS	      = $(INITOBJS)
EXTSOLIBS     =
MINIOBJS      = $(ARCHMINIOBJS) miniinit.$(OBJEXT) dmyext.$(OBJEXT) miniprelude.$(OBJEXT)
ENC_MK        = enc.mk
MAKE_ENC      = -f $(ENC_MK) V="$(V)" UNICODE_HDR_DIR="$(UNICODE_HDR_DIR)" \
		RUBY="$(MINIRUBY)" MINIRUBY="$(MINIRUBY)" $(mflags)

COMMONOBJS    = array.$(OBJEXT) \
		ast.$(OBJEXT) \
		bignum.$(OBJEXT) \
		class.$(OBJEXT) \
		compar.$(OBJEXT) \
		compile.$(OBJEXT) \
		complex.$(OBJEXT) \
		cont.$(OBJEXT) \
		debug.$(OBJEXT) \
		debug_counter.$(OBJEXT) \
		dir.$(OBJEXT) \
		dln_find.$(OBJEXT) \
		encoding.$(OBJEXT) \
		enum.$(OBJEXT) \
		enumerator.$(OBJEXT) \
		error.$(OBJEXT) \
		eval.$(OBJEXT) \
		file.$(OBJEXT) \
		gc.$(OBJEXT) \
		hash.$(OBJEXT) \
		inits.$(OBJEXT) \
		io.$(OBJEXT) \
		iseq.$(OBJEXT) \
		load.$(OBJEXT) \
		marshal.$(OBJEXT) \
		math.$(OBJEXT) \
		mjit.$(OBJEXT) \
		mjit_compile.$(OBJEXT) \
		node.$(OBJEXT) \
		numeric.$(OBJEXT) \
		object.$(OBJEXT) \
		pack.$(OBJEXT) \
		parse.$(OBJEXT) \
		proc.$(OBJEXT) \
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
		thread.$(OBJEXT) \
		time.$(OBJEXT) \
		transcode.$(OBJEXT) \
		transient_heap.$(OBJEXT) \
		util.$(OBJEXT) \
		variable.$(OBJEXT) \
		version.$(OBJEXT) \
		vm.$(OBJEXT) \
		vm_backtrace.$(OBJEXT) \
		vm_dump.$(OBJEXT) \
		vm_trace.$(OBJEXT) \
		$(COROUTINE_OBJ) \
		$(DTRACE_OBJ) \
		$(BUILTIN_ENCOBJS) \
		$(BUILTIN_TRANSOBJS) \
		$(MISSING)

EXPORTOBJS    = $(DLNOBJ) \
		localeinit.$(OBJEXT) \
		loadpath.$(OBJEXT) \
		$(COMMONOBJS)

OBJS          = $(EXPORTOBJS) prelude.$(OBJEXT)
ALLOBJS       = $(NORMALMAINOBJ) $(MINIOBJS) $(COMMONOBJS) $(INITOBJS)

GOLFOBJS      = goruby.$(OBJEXT) golf_prelude.$(OBJEXT)

DEFAULT_PRELUDES = $(GEM_PRELUDE)
PRELUDE_SCRIPTS = $(srcdir)/prelude.rb $(DEFAULT_PRELUDES)
GEM_PRELUDE   = $(srcdir)/gem_prelude.rb
PRELUDES      = {$(srcdir)}prelude.c {$(srcdir)}miniprelude.c
GOLFPRELUDES  = {$(srcdir)}golf_prelude.c

SCRIPT_ARGS   =	--dest-dir="$(DESTDIR)" \
		--extout="$(EXTOUT)" \
		--mflags="$(MFLAGS)" \
		--make-flags="$(MAKEFLAGS)"
EXTMK_ARGS    =	$(SCRIPT_ARGS) --extension $(EXTS) --extstatic $(EXTSTATIC) \
		--make-flags="V=$(V) MINIRUBY='$(MINIRUBY)'" \
		--gnumake=$(gnumake) --extflags="$(EXTLDFLAGS)" \
		--
INSTRUBY      =	$(SUDO) $(RUNRUBY) -r./$(arch)-fake $(srcdir)/tool/rbinstall.rb
INSTRUBY_ARGS =	$(SCRIPT_ARGS) \
		--data-mode=$(INSTALL_DATA_MODE) \
		--prog-mode=$(INSTALL_PROG_MODE) \
		--installed-list $(INSTALLED_LIST) \
		--mantype="$(MANTYPE)"
INSTALL_PROG_MODE = 0755
INSTALL_DATA_MODE = 0644

TESTSDIR      = $(srcdir)/test
TOOL_TESTSDIR = $(srcdir)/tool/test
TEST_EXCLUDES = --excludes-dir=$(TESTSDIR)/excludes --name=!/memory_leak/
TESTWORKDIR   = testwork
TESTOPTS      = $(RUBY_TESTOPTS)

TESTRUN_SCRIPT = $(srcdir)/test.rb

COMPILE_PRELUDE = $(srcdir)/tool/generic_erb.rb $(srcdir)/template/prelude.c.tmpl

SHOWFLAGS = showflags

MAKE_LINK = $(MINIRUBY) -rfileutils -e "include FileUtils::Verbose" \
	  -e "src, dest = ARGV" \
	  -e "exit if File.identical?(src, dest) or cmp(src, dest) rescue nil" \
	  -e "def noraise; yield; rescue; rescue NotImplementedError; end" \
	  -e "noraise {ln_sf('../'*dest.count('/')+src, dest)} or" \
	  -e "noraise {ln(src, dest)} or" \
	  -e "cp(src, dest)"


all: $(SHOWFLAGS) main docs

main: $(SHOWFLAGS) exts $(ENCSTATIC:static=lib)encs
	@$(NULLCMD)

mjit-headers: $(MJIT_SUPPORT)-mjit-headers
no-mjit-headers: PHONY
yes-mjit-headers: mjit_config.h PHONY

mjit.$(OBJEXT): mjit_config.h
mjit_config.h: Makefile


# These rules using MJIT_HEADER_SUFFIX must be in common.mk, not
# Makefile.in, in order to override the macro in defs/universal.mk.

# Other `-Dxxx`s preceding `-DMJIT_HEADER` will be removed in transform_mjit_header.rb.
# So `-DMJIT_HEADER` should be passed first when rb_mjit_header.h is generated.
$(TIMESTAMPDIR)/$(MJIT_HEADER:.h=)$(MJIT_HEADER_SUFFIX).time: probes.h vm.$(OBJEXT) \
		$(TIMESTAMPDIR)/$(arch)/.time
	$(ECHO) building $(@F:.time=.h)
	$(Q) $(CPP) -DMJIT_HEADER $(MJIT_HEADER_FLAGS) $(CFLAGS) $(XCFLAGS) $(CPPFLAGS) $(srcdir)/vm.c $(CPPOUTFLAG)$(@F:.time=.h).new
	$(Q) $(IFCHANGE) "--timestamp=$@" $(@F:.time=.h) $(@F:.time=.h).new

$(MJIT_HEADER:.h=)$(MJIT_HEADER_SUFFIX).h: $(TIMESTAMPDIR)/$(MJIT_HEADER:.h=)$(MJIT_HEADER_SUFFIX).time

$(MJIT_MIN_HEADER:.h=)$(MJIT_HEADER_SUFFIX).h: \
		$(TIMESTAMPDIR)/$(MJIT_HEADER:.h=)$(MJIT_HEADER_SUFFIX).time \
		$(srcdir)/tool/transform_mjit_header.rb $(PREP) \
		$(MJIT_HEADER:.h=)$(MJIT_HEADER_SUFFIX).h
	$(ECHO) building $@
	$(MINIRUBY) $(srcdir)/tool/transform_mjit_header.rb "$(CC) $(ARCH_FLAG) $(CFLAGS)" $(MJIT_HEADER:.h=)$(MJIT_HEADER_ARCH).h $@
	$(Q) $(MAKEDIRS) $(MJIT_HEADER_INSTALL_DIR)
	$(Q) $(MAKE_LINK) $@ $(MJIT_HEADER_INSTALL_DIR)/$(@F)

.PHONY: showflags
exts enc trans: $(SHOWFLAGS)
showflags:
	$(MESSAGE_BEGIN) \
	"	BASERUBY = $(BASERUBY)" \
	"	CC = $(CC)" \
	"	LD = $(LD)" \
	"	LDSHARED = $(LDSHARED)" \
	"	CFLAGS = $(CFLAGS)" \
	"	XCFLAGS = $(XCFLAGS)" \
	"	CPPFLAGS = $(CPPFLAGS)" \
	"	DLDFLAGS = $(DLDFLAGS)" \
	"	SOLIBS = $(SOLIBS)" \
	"	LANG = $(LANG)" \
	"	LC_ALL = $(LC_ALL)" \
	"	LC_CTYPE = $(LC_CTYPE)" \
	"	MFLAGS = $(MFLAGS)" \
	$(MESSAGE_END)
	-@$(CC_VERSION)

.PHONY: showconfig
showconfig:
	@$(ECHO_BEGIN) \
	$(configure_args) \
	$(ECHO_END)

EXTS_NOTE = -f $(EXTS_MK) $(mflags) RUBY="$(MINIRUBY)" top_srcdir="$(srcdir)" note

exts: build-ext

EXTS_MK = exts.mk
$(EXTS_MK): ext/configure-ext.mk $(TIMESTAMPDIR)/$(arch)/.time $(srcdir)/template/exts.mk.tmpl
	$(Q)$(MAKE) -f ext/configure-ext.mk $(mflags) V=$(V) EXTSTATIC=$(EXTSTATIC) \
		gnumake=$(gnumake) MINIRUBY="$(MINIRUBY)" \
		EXTLDFLAGS="$(EXTLDFLAGS)" srcdir="$(srcdir)"
	$(ECHO) generating makefile $@
	$(Q)$(MINIRUBY) $(srcdir)/tool/generic_erb.rb -o $@ -c \
	    $(srcdir)/template/exts.mk.tmpl --gnumake=$(gnumake)

ext/configure-ext.mk: $(PREP) all-incs $(MKFILES) $(RBCONFIG) $(LIBRUBY) \
		$(srcdir)/template/configure-ext.mk.tmpl
	$(ECHO) generating makefiles $@
	$(Q)$(MAKEDIRS) $(@D)
	$(Q)$(MINIRUBY) $(srcdir)/tool/generic_erb.rb -o $@ -c \
	    $(srcdir)/template/$(@F).tmpl --srcdir="$(srcdir)" \
	    --miniruby="$(MINIRUBY)" --script-args='$(SCRIPT_ARGS)'

configure-ext: $(EXTS_MK)

build-ext: $(EXTS_MK)
	$(Q)$(MAKE) -f $(EXTS_MK) $(mflags) libdir="$(libdir)" LIBRUBY_EXTS=$(LIBRUBY_EXTS) \
	    EXTENCS="$(ENCOBJS)" UPDATE_LIBRARIES=no $(EXTSTATIC)
	$(Q)$(MAKE) $(EXTS_NOTE)

exts-note: $(EXTS_MK)
	$(Q)$(MAKE) $(EXTS_NOTE)

ext/extinit.c: $(srcdir)/template/extinit.c.tmpl
	$(Q)$(MINIRUBY) $(srcdir)/tool/generic_erb.rb -o $@ -c \
	    $(srcdir)/template/extinit.c.tmpl $(EXTINITS)

prog: program wprogram
programs: $(PROGRAM) $(WPROGRAM)

$(PREP): $(MKFILES)

miniruby$(EXEEXT): config.status $(ALLOBJS) $(ARCHFILE)

objs: $(ALLOBJS)

GORUBY = go$(RUBY_INSTALL_NAME)
GOLF = $(GORUBY)
golf: $(GOLF)
$(GOLF): $(LIBRUBY) $(GOLFOBJS) PHONY
	$(Q) $(MAKE) $(mflags) \
		GOLF=_dummy_golf_target_to_avoid_conflict_just_in_case_ \
		MAINOBJ=goruby.$(OBJEXT) \
		EXTOBJS="golf_prelude.$(OBJEXT) $(EXTOBJS)" \
		PROGRAM=$(GORUBY)$(EXEEXT) \
		V=$(V) \
	program
capi: $(CAPIOUT)/.timestamp PHONY

$(CAPIOUT)/.timestamp: Doxyfile $(PREP)
	$(Q) $(MAKEDIRS) "$(@D)"
	$(ECHO) generating capi
	-$(Q) $(DOXYGEN) -b
	$(Q) $(MINIRUBY) -e 'File.open(ARGV[0], "w"){'"|f|"' f.puts(Time.now)}' "$@"

Doxyfile: $(srcdir)/template/Doxyfile.tmpl $(PREP) $(srcdir)/tool/generic_erb.rb $(RBCONFIG)
	$(ECHO) generating $@
	$(Q) $(MINIRUBY) $(srcdir)/tool/generic_erb.rb -o $@ $(srcdir)/template/Doxyfile.tmpl \
	--srcdir="$(srcdir)" --miniruby="$(MINIRUBY)"

program: $(SHOWFLAGS) $(PROGRAM)
wprogram: $(SHOWFLAGS) $(WPROGRAM)
mini: PHONY miniruby$(EXEEXT)

$(PROGRAM) $(WPROGRAM): $(LIBRUBY) $(MAINOBJ) $(OBJS) $(EXTOBJS) $(SETUP) $(PREP)

$(LIBRUBY_A):	$(LIBRUBY_A_OBJS) $(MAINOBJ) $(INITOBJS) $(ARCHFILE)

$(LIBRUBY_SO):	$(OBJS) $(DLDOBJS) $(LIBRUBY_A) $(PREP) $(BUILTIN_ENCOBJS)

$(LIBRUBY_EXTS):
	@exit > $@

$(STATIC_RUBY)$(EXEEXT): $(MAINOBJ) $(DLDOBJS) $(EXTOBJS) $(LIBRUBY_A)
	$(Q)$(RM) $@
	$(PURIFY) $(CC) $(MAINOBJ) $(DLDOBJS) $(LIBRUBY_A) $(MAINLIBS) $(EXTLIBS) $(LIBS) $(OUTFLAG)$@ $(LDFLAGS) $(XLDFLAGS)

ruby.imp: $(COMMONOBJS)
	$(Q){ \
	$(NM) -Pgp $(COMMONOBJS) | \
	awk 'BEGIN{print "#!"}; $$2~/^[BDT]$$/&&$$1!~/^$(SYMBOL_PREFIX)(Init_|InitVM_|ruby_static_id_|.*_threadptr_|rb_ec_)|^\./{print $$1}'; \
	($(CHDIR) $(srcdir) && \
	 exec sed -n '/^MJIT_FUNC_EXPORTED/!d;N;s/.*\n\(rb_[a-zA-Z_0-9]*\).*/$(SYMBOL_PREFIX)\1/p' cont.c gc.c thread*c vm*.c) \
	} | \
	sort -u -o $@

install: install-$(INSTALLDOC)
docs: $(DOCTARGETS)
pkgconfig-data: $(ruby_pc)
$(ruby_pc): $(srcdir)/template/ruby.pc.in config.status

install-all: docs pre-install-all do-install-all post-install-all
pre-install-all:: all pre-install-local pre-install-ext pre-install-doc
do-install-all: pre-install-all
	$(INSTRUBY) --make="$(MAKE)" $(INSTRUBY_ARGS) $(INSTALL_DOC_OPTS)
post-install-all:: post-install-local post-install-ext post-install-doc
	@$(NULLCMD)

install-nodoc: pre-install-nodoc do-install-nodoc post-install-nodoc
pre-install-nodoc:: pre-install-local pre-install-ext
do-install-nodoc: main pre-install-nodoc
	$(INSTRUBY) --make="$(MAKE)" $(INSTRUBY_ARGS) --exclude=doc
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
	$(INSTRUBY) -n --make="$(MAKE)" $(INSTRUBY_ARGS) --install=all $(INSTALL_DOC_OPTS)
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
	$(INSTRUBY) --make="$(MAKE)" $(INSTRUBY_ARGS) --install=rdoc $(INSTALL_DOC_OPTS)
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
	$(Q) $(RDOC) --ri --op "$(RDOCOUT)" $(RDOC_GEN_OPTS) $(RDOCFLAGS) "$(srcdir)"

html: PHONY main
	@echo Generating RDoc HTML files
	$(Q) $(RDOC) --op "$(HTMLOUT)" $(RDOC_GEN_OPTS) $(RDOCFLAGS) "$(srcdir)"

rdoc-coverage: PHONY main
	@echo Generating RDoc coverage report
	$(Q) $(RDOC) --quiet -C $(RDOCFLAGS) "$(srcdir)"

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
	$(INSTRUBY) -n --make="$(MAKE)" $(INSTRUBY_ARGS) --install=rdoc $(INSTALL_DOC_OPTS)
post-no-install-doc::
	@$(NULLCMD)

CLEAR_INSTALLED_LIST = clear-installed-list

install-prereq: $(CLEAR_INSTALLED_LIST) yes-fake sudo-precheck PHONY

clear-installed-list: PHONY
	@> $(INSTALLED_LIST) set MAKE="$(MAKE)"

clean: clean-ext clean-enc clean-golf clean-docs clean-extout clean-local clean-platform clean-spec
clean-local:: clean-runnable
	$(Q)$(RM) $(OBJS) $(MINIOBJS) $(MAINOBJ) $(LIBRUBY_A) $(LIBRUBY_SO) $(LIBRUBY) $(LIBRUBY_ALIASES)
	$(Q)$(RM) $(PROGRAM) $(WPROGRAM) miniruby$(EXEEXT) dmyext.$(OBJEXT) dmyenc.$(OBJEXT) $(ARCHFILE) .*.time
	$(Q)$(RM) y.tab.c y.output encdb.h transdb.h config.log rbconfig.rb $(ruby_pc) $(COROUTINE_H:/Context.h=/.time)
	$(Q)$(RM) probes.h probes.$(OBJEXT) probes.stamp ruby-glommed.$(OBJEXT) ruby.imp
	$(Q)$(RM) GNUmakefile.old Makefile.old $(arch)-fake.rb bisect.sh $(ENC_TRANS_D)
	-$(Q) $(RMDIR) enc/jis enc/trans enc $(COROUTINE_H:/Context.h=) coroutine 2> $(NULL) || exit 0
clean-runnable:: PHONY
	$(Q)$(CHDIR) bin 2>$(NULL) && $(RM) $(PROGRAM) $(WPROGRAM) $(GORUBY)$(EXEEXT) bin/*.$(DLEXT) 2>$(NULL) || exit 0
	$(Q)$(CHDIR) lib 2>$(NULL) && $(RM) $(LIBRUBY_A) $(LIBRUBY) $(LIBRUBY_ALIASES) $(RUBY_BASE_NAME)/$(RUBY_PROGRAM_VERSION) $(RUBY_BASE_NAME)/vendor_ruby 2>$(NULL) || exit 0
	$(Q)$(RMDIR) lib/$(RUBY_BASE_NAME) lib bin 2>$(NULL) || exit 0
clean-ext:: PHONY
clean-golf: PHONY
	$(Q)$(RM) $(GORUBY)$(EXEEXT) $(GOLFOBJS)
clean-rdoc: PHONY
clean-html: PHONY
clean-capi: PHONY
clean-platform: PHONY
clean-extout: PHONY
	-$(Q)$(RMDIR) $(EXTOUT)/$(arch) $(EXTOUT) 2> $(NULL) || exit 0
clean-docs: clean-rdoc clean-html clean-capi
clean-spec: PHONY
clean-rubyspec: clean-spec

distclean: distclean-ext distclean-enc distclean-golf distclean-docs distclean-extout distclean-local distclean-platform distclean-spec
distclean-local:: clean-local
	$(Q)$(RM) $(MKFILES) yasmdata.rb *.inc $(PRELUDES)
	$(Q)$(RM) config.cache config.status config.status.lineno
	$(Q)$(RM) *~ *.bak *.stackdump core *.core gmon.out $(PREP)
	-$(Q)$(RMALL) $(srcdir)/autom4te.cache
distclean-ext:: PHONY
distclean-golf: clean-golf
distclean-rdoc: clean-rdoc
distclean-html: clean-html
distclean-capi: clean-capi
distclean-docs: clean-docs
distclean-extout: clean-extout
distclean-platform: clean-platform
distclean-spec: clean-spec
distclean-rubyspec: distclean-spec

realclean:: realclean-ext realclean-local realclean-enc realclean-golf realclean-extout
realclean-local:: distclean-local realclean-srcs-local

clean-srcs:: clean-srcs-local clean-srcs-ext
realclean-srcs:: realclean-srcs-local realclean-srcs-ext

clean-srcs-local::
	$(Q)$(RM) parse.c parse.h lex.c enc/trans/newline.c revision.h
	$(Q)$(RM) id.c id.h probes.dmyh probes.h
	$(Q)$(RM) encdb.h transdb.h verconf.h ruby-runner.h
	$(Q)$(RM) mjit_config.h rb_mjit_header.h
	$(Q)$(RM) $(MJIT_MIN_HEADER) $(MJIT_MIN_HEADER:.h=)$(MJIT_HEADER_SUFFIX:%=*).h

realclean-srcs-local:: clean-srcs-local
	$(Q)$(CHDIR) $(srcdir) && $(exec) $(RM) parse.c parse.h lex.c enc/trans/newline.c $(PRELUDES) revision.h
	$(Q)$(CHDIR) $(srcdir) && $(exec) $(RM) id.c id.h probes.dmyh
	$(Q)$(CHDIR) $(srcdir) && $(exec) $(RM) configure aclocal.m4 tool/config.guess tool/config.sub gems/*.gem

clean-srcs-ext::
realclean-srcs-ext:: clean-srcs-ext

realclean-ext:: PHONY
realclean-golf: distclean-golf
	$(Q)$(RM) $(GOLFPRELUDES)
realclean-rdoc: distclean-rdoc
realclean-html: distclean-html
realclean-capi: distclean-capi
realclean-docs: distclean-docs
realclean-extout: distclean-extout
realclean-platform: distclean-platform
realclean-spec: distclean-spec
realclean-rubyspec: realclean-spec

clean-ext:: ext/clean gems/clean timestamp/clean
distclean-ext:: ext/distclean gems/distclean timestamp/distclean
realclean-ext:: ext/realclean gems/realclean timestamp/realclean

ext/clean.mk ext/distclean.mk ext/realclean.mk::
ext/clean:: ext/clean.mk
ext/distclean:: ext/distclean.mk
ext/realclean:: ext/realclean.mk

timestamp/clean:: ext/clean gems/clean
timestamp/distclean:: ext/distclean gems/distclean
timestamp/realclean:: ext/realclean gems/realclean

timestamp/clean timestamp/distclean timestamp/realclean::
	$(Q)$(RM) $(TIMESTAMPDIR)/.*.time $(TIMESTAMPDIR)/$(arch)/.time
	$(Q)$(RMDIRS) $(TIMESTAMPDIR)/$(arch) $(TIMESTAMPDIR) 2> $(NULL) || exit 0

clean-ext::
	-$(Q)$(RM) ext/extinit.$(OBJEXT)

distclean-ext realclean-ext::
	-$(Q)$(RM) $(EXTS_MK) ext/extinit.* ext/configure-ext.mk
	-$(Q)$(RMDIR) ext 2> $(NULL) || exit 0

clean-enc distclean-enc realclean-enc: PHONY

clean-enc: clean-enc.d

clean-enc.d: PHONY
	$(Q)$(RM) $(ENC_TRANS_D)
	-$(Q) $(RMDIR) enc/jis enc/trans enc 2> $(NULL) || exit 0

clean-rdoc distclean-rdoc realclean-rdoc:
	@echo $(@:-rdoc=ing) rdoc
	$(Q)$(RMALL) $(RDOCOUT)

clean-html distclean-html realclean-html:
	@echo $(@:-html=ing) HTML
	$(Q)$(RMALL) $(HTMLOUT)

clean-capi distclean-capi realclean-capi:
	@echo $(@:-capi=ing) capi
	$(Q)$(RMALL) $(CAPIOUT)

clean-platform:
	$(Q) $(RM) $(PLATFORM_D)
	-$(Q) $(RMDIR) $(PLATFORM_DIR) 2> $(NULL) || exit 0

RUBYSPEC_CAPIEXT = spec/ruby/optional/capi/ext
clean-spec: PHONY
	-$(Q) $(RM) $(RUBYSPEC_CAPIEXT)/*.$(OBJEXT) $(RUBYSPEC_CAPIEXT)/*.$(DLEXT)
	-$(Q) $(RMDIRS) $(RUBYSPEC_CAPIEXT) 2> $(NULL) || exit 0

check: main test test-tool test-all test-spec
	$(ECHO) check succeeded
	- $(GIT) --no-pager -C "$(srcdir)" log --format=oneline -G "^ *# *include" origin/master..HEAD
check-ruby: test test-ruby

fake: $(CROSS_COMPILING)-fake
yes-fake: $(arch)-fake.rb $(RBCONFIG) PHONY
no-fake -fake: PHONY

# really doesn't depend on .o, just ensure newer than headers which
# version.o depends on.
$(arch)-fake.rb: $(srcdir)/template/fake.rb.in $(srcdir)/tool/generic_erb.rb version.$(OBJEXT) miniruby$(EXEEXT)
	$(ECHO) generating $@
	$(Q) $(CPP) -DRUBY_EXPORT $(INCFLAGS) $(CPPFLAGS) "$(srcdir)/version.c" | \
	$(BOOTSTRAPRUBY) "$(srcdir)/tool/generic_erb.rb" -o $@ "$(srcdir)/template/fake.rb.in" \
		i=- srcdir="$(srcdir)" BASERUBY="$(BASERUBY)"

btest: $(TEST_RUNNABLE)-btest
no-btest: PHONY
yes-btest: fake miniruby$(EXEEXT) PHONY
	$(Q)$(exec) $(BOOTSTRAPRUBY) "$(srcdir)/bootstraptest/runner.rb" --ruby="$(BTESTRUBY) $(RUN_OPTS)" $(OPTS) $(TESTOPTS) $(BTESTS)

btest-ruby: $(TEST_RUNNABLE)-btest-ruby
no-btest-ruby: PHONY
yes-btest-ruby: prog PHONY
	$(Q)$(exec) $(RUNRUBY) "$(srcdir)/bootstraptest/runner.rb" --ruby="$(PROGRAM) -I$(srcdir)/lib $(RUN_OPTS)" -q $(OPTS) $(TESTOPTS) $(BTESTS)

test-basic: $(TEST_RUNNABLE)-test-basic
no-test-basic: PHONY
yes-test-basic: prog PHONY
	$(Q)$(exec) $(RUNRUBY) "$(srcdir)/basictest/runner.rb" --run-opt=$(RUN_OPTS) $(OPTS) $(TESTOPTS)

test-knownbugs: test-knownbug
test-knownbug: $(TEST_RUNNABLE)-test-knownbug
no-test-knownbug: PHONY
yes-test-knownbug: prog PHONY
	-$(exec) $(RUNRUBY) "$(srcdir)/bootstraptest/runner.rb" --ruby="$(PROGRAM) $(RUN_OPTS)" $(OPTS) $(TESTOPTS) $(srcdir)/KNOWNBUGS.rb

test-testframework: $(TEST_RUNNABLE)-test-testframework
yes-test-testframework: prog PHONY
	$(gnumake_recursive)$(Q)$(exec) $(RUNRUBY) "$(TOOL_TESTSDIR)/runner.rb" --ruby="$(RUNRUBY)" $(TESTOPTS) testunit minitest
no-test-testframework: PHONY

test-tool: $(TEST_RUNNABLE)-test-tool
yes-test-tool: prog PHONY
	$(gnumake_recursive)$(Q)$(exec) $(RUNRUBY) "$(TOOL_TESTSDIR)/runner.rb" --ruby="$(RUNRUBY)" $(TESTOPTS)
no-test-tool: PHONY

test-sample: test-basic # backward compatibility for mswin-build
test-short: btest-ruby test-knownbug test-basic
test: test-short

# $ make test-all TESTOPTS="--help" displays more detail
# for example, make test-all TESTOPTS="-j2 -v -n test-name -- test-file-name"
test-all: $(TEST_RUNNABLE)-test-all
yes-test-all: programs PHONY
	$(gnumake_recursive)$(Q)$(exec) $(RUNRUBY) "$(TESTSDIR)/runner.rb" --ruby="$(RUNRUBY)" $(TEST_EXCLUDES) $(TESTOPTS) $(TESTS)
TESTS_BUILD = mkmf
no-test-all: PHONY
	$(gnumake_recursive)$(MINIRUBY) -I"$(srcdir)/lib" "$(TESTSDIR)/runner.rb" $(TESTOPTS) $(TESTS_BUILD)

test-almost: test-all
yes-test-almost: yes-test-all
no-test-almost: no-test-all

test-ruby: $(TEST_RUNNABLE)-test-ruby
no-test-ruby: PHONY
yes-test-ruby: prog encs PHONY
	$(gnumake_recursive)$(RUNRUBY) "$(TESTSDIR)/runner.rb" $(TEST_EXCLUDES) $(TESTOPTS) -- ruby -ext-

extconf: $(PREP)
	$(Q) $(MAKEDIRS) "$(EXTCONFDIR)"
	$(RUNRUBY) -C "$(EXTCONFDIR)" $(EXTCONF) $(EXTCONFARGS)

$(RBCONFIG): $(srcdir)/tool/mkconfig.rb config.status $(srcdir)/version.h
	$(Q)$(BOOTSTRAPRUBY) -n \
	-e 'BEGIN{version=ARGV.shift;mis=ARGV.dup}' \
	-e 'END{abort "UNICODE version mismatch: #{mis}" unless mis.empty?}' \
	-e '(mis.delete(ARGF.path); ARGF.close) if /ONIG_UNICODE_VERSION_STRING +"#{Regexp.quote(version)}"/o' \
	$(UNICODE_VERSION) $(UNICODE_DATA_HEADERS)
	$(Q)$(BOOTSTRAPRUBY) $(srcdir)/tool/mkconfig.rb \
		-arch=$(arch) -version=$(RUBY_PROGRAM_VERSION) \
		-install_name=$(RUBY_INSTALL_NAME) \
		-so_name=$(RUBY_SO_NAME) \
		-unicode_version=$(UNICODE_VERSION) \
		-unicode_emoji_version=$(UNICODE_EMOJI_VERSION) \
	> rbconfig.tmp
	$(IFCHANGE) "--timestamp=$@" rbconfig.rb rbconfig.tmp

test-rubyspec: test-spec
yes-test-rubyspec: yes-test-spec

test-spec-precheck: $(arch)-fake.rb programs

test-spec: $(TEST_RUNNABLE)-test-spec
yes-test-spec: test-spec-precheck
	$(gnumake_recursive)$(Q) \
	$(RUNRUBY) -r./$(arch)-fake $(srcdir)/spec/mspec/bin/mspec run -B $(srcdir)/spec/default.mspec $(MSPECOPT) $(SPECOPTS)
no-test-spec:

RUNNABLE = $(LIBRUBY_RELATIVE:no=un)-runnable
runnable: $(RUNNABLE) prog $(srcdir)/tool/mkrunnable.rb PHONY
	$(Q) $(MINIRUBY) $(srcdir)/tool/mkrunnable.rb -v $(EXTOUT)
yes-runnable: PHONY

encs: enc trans
libencs: libenc libtrans
encs enc trans libencs libenc libtrans: $(SHOWFLAGS) $(ENC_MK) $(LIBRUBY) $(PREP) PHONY
	$(ECHO) making $@
	$(Q) $(MAKE) $(MAKE_ENC) $@


libenc enc: {$(VPATH)}encdb.h
libtrans trans: {$(VPATH)}transdb.h

# Use MINIRUBY which loads fake.rb for cross compiling
$(ENC_MK): $(srcdir)/enc/make_encmake.rb $(srcdir)/enc/Makefile.in $(srcdir)/enc/depend \
	$(srcdir)/enc/encinit.c.erb $(srcdir)/lib/mkmf.rb $(RBCONFIG) fake
	$(ECHO) generating $@
	$(Q) $(MINIRUBY) $(srcdir)/enc/make_encmake.rb --builtin-encs="$(BUILTIN_ENCOBJS)" --builtin-transes="$(BUILTIN_TRANSOBJS)" --module$(ENCSTATIC) $(ENCS) $@

.PRECIOUS: $(MKFILES)

.PHONY: PHONY all fake prereq incs srcs preludes help
.PHONY: test install install-nodoc install-doc dist
.PHONY: loadpath golf capi rdoc install-prereq clear-installed-list
.PHONY: clean clean-ext clean-local clean-enc clean-golf clean-rdoc clean-html clean-extout
.PHONY: distclean distclean-ext distclean-local distclean-enc distclean-golf distclean-extout
.PHONY: realclean realclean-ext realclean-local realclean-enc realclean-golf realclean-extout
.PHONY: exam check test test-short test-all btest btest-ruby test-basic test-knownbug
.PHONY: run runruby parse benchmark gdb gdb-ruby
.PHONY: update-mspec update-rubyspec test-rubyspec test-spec
.PHONY: touch-unicode-files

PHONY:

{$(VPATH)}parse.c: {$(VPATH)}parse.y $(srcdir)/tool/ytab.sed {$(VPATH)}id.h
{$(VPATH)}parse.h: {$(VPATH)}parse.c

{$(srcdir)}.y.c:
	$(ECHO) generating $@
	$(Q)$(BASERUBY) $(srcdir)/tool/id2token.rb --path-separator=.$(PATH_SEPARATOR)./ --vpath=$(VPATH) id.h $(SRC_FILE) > parse.tmp.y
	$(Q)$(BASERUBY) $(srcdir)/tool/pure_parser.rb parse.tmp.y $(YACC)
	$(Q)$(YACC) -d $(YFLAGS) -o y.tab.c parse.tmp.y
	$(Q)$(RM) parse.tmp.y
	$(Q)sed -f $(srcdir)/tool/ytab.sed -e "/^#/s|parse\.tmp\.[iy]|$(SRC_FILE)|" -e "/^#/s!y\.tab\.c!$@!" y.tab.c > $@.new
	$(Q)$(MV) $@.new $@
	$(Q)sed -e "/^#line.*y\.tab\.h/d;/^#line.*parse.*\.y/d" y.tab.h > $(@:.c=.h)
	$(Q)$(RM) y.tab.c y.tab.h

$(PLATFORM_D):
	$(Q) $(MAKEDIRS) $(PLATFORM_DIR) $(@D)
	@exit > $@

exe/$(PROGRAM): ruby-runner.c ruby-runner.h exe/.time miniruby$(EXEEXT) {$(VPATH)}config.h
	$(Q) $(CC) $(CFLAGS) $(INCFLAGS) $(CPPFLAGS) -DRUBY_INSTALL_NAME=$(@F) $(COUTFLAG)ruby-runner.$(OBJEXT) -c $(CSRCFLAG)$(srcdir)/ruby-runner.c
	$(Q) $(PURIFY) $(CC) $(CFLAGS) $(LDFLAGS) $(OUTFLAG)$@ ruby-runner.$(OBJEXT) $(LIBS)
	$(Q) $(POSTLINK)
	$(Q) ./miniruby$(EXEEXT) \
	    -e 'prog, dest, inst = ARGV; dest += "/ruby"' \
	    -e 'exit unless prog==inst' \
	    -e 'unless prog=="ruby"' \
	    -e '  begin File.unlink(dest); rescue Errno::ENOENT; end' \
	    -e '  File.symlink(prog, dest)' \
	    -e 'end' \
	$(@F) $(@D) $(RUBY_INSTALL_NAME)$(EXEEXT)

exe/.time:
	$(Q) $(MAKEDIRS) $(@D)
	@exit > $@

$(BUILTIN_ENCOBJS) $(BUILTIN_TRANSOBJS): $(ENC_TRANS_D)

$(ENC_TRANS_D):
	$(Q) $(MAKEDIRS) enc/trans $(@D)
	@exit > $@

$(TIMESTAMPDIR)/$(arch)/.time:
	$(Q)$(MAKEDIRS) $(@D) $(EXTOUT)/$(arch)
	@exit > $@

###
CCAN_DIR = {$(VPATH)}ccan

RUBY_H_INCLUDES    = {$(VPATH)}ruby.h {$(VPATH)}config.h {$(VPATH)}defines.h \
		     {$(VPATH)}intern.h {$(VPATH)}missing.h {$(VPATH)}st.h \
		     {$(VPATH)}assert.h {$(VPATH)}subst.h

###

acosh.$(OBJEXT): {$(VPATH)}acosh.c
alloca.$(OBJEXT): {$(VPATH)}alloca.c {$(VPATH)}config.h
crypt.$(OBJEXT): {$(VPATH)}crypt.c {$(VPATH)}crypt.h {$(VPATH)}missing/des_tables.c
dup2.$(OBJEXT): {$(VPATH)}dup2.c
erf.$(OBJEXT): {$(VPATH)}erf.c
explicit_bzero.$(OBJEXT): {$(VPATH)}explicit_bzero.c
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
nt.$(OBJEXT): {$(VPATH)}nt.c

.coroutine_obj $(COROUTINE_OBJ): \
	{$(VPATH)}$(COROUTINE_SRC) \
	$(COROUTINE_H:/Context.h=/.time)
$(COROUTINE_H:/Context.h=/.time):
	$(Q) $(MAKEDIRS) $(@D)
	@exit > $@

###

# dependencies for generated C sources.
parse.$(OBJEXT): {$(VPATH)}parse.c
miniprelude.$(OBJEXT): {$(VPATH)}miniprelude.c
prelude.$(OBJEXT): {$(VPATH)}prelude.c

# dependencies for optional sources.
compile.$(OBJEXT): {$(VPATH)}opt_sc.inc {$(VPATH)}optunifs.inc

win32/win32.$(OBJEXT): {$(VPATH)}win32/win32.c {$(VPATH)}win32/file.h \
  {$(VPATH)}dln.h {$(VPATH)}dln_find.c {$(VPATH)}encindex.h \
  {$(VPATH)}internal.h {$(VPATH)}util.h $(RUBY_H_INCLUDES) \
  {$(VPATH)}vm.h $(PLATFORM_D)
win32/file.$(OBJEXT): {$(VPATH)}win32/file.c {$(VPATH)}win32/file.h \
  $(RUBY_H_INCLUDES) $(PLATFORM_D)

$(NEWLINE_C): $(srcdir)/enc/trans/newline.trans $(srcdir)/tool/transcode-tblgen.rb
	$(Q) $(MAKEDIRS) $(@D)
	$(Q) $(BASERUBY) "$(srcdir)/tool/transcode-tblgen.rb" -vo $@ $(srcdir)/enc/trans/newline.trans
enc/trans/newline.$(OBJEXT): $(NEWLINE_C)

verconf.h: $(srcdir)/template/verconf.h.tmpl $(srcdir)/tool/generic_erb.rb
	$(ECHO) creating $@
	$(Q) $(BOOTSTRAPRUBY) "$(srcdir)/tool/generic_erb.rb" -o $@ $(srcdir)/template/verconf.h.tmpl

ruby-glommed.$(OBJEXT): $(OBJS)

$(OBJS):  {$(VPATH)}config.h {$(VPATH)}missing.h

INSNS2VMOPT = --srcdir="$(srcdir)"

srcs_vpath = {$(VPATH)}

inc_common_headers = $(srcdir)/tool/ruby_vm/views/_copyright.erb $(srcdir)/tool/ruby_vm/views/_notice.erb
$(srcs_vpath)opt_sc.inc: $(srcdir)/tool/ruby_vm/views/opt_sc.inc.erb $(inc_common_headers)
$(srcs_vpath)optinsn.inc: $(srcdir)/tool/ruby_vm/views/optinsn.inc.erb $(inc_common_headers)
$(srcs_vpath)optunifs.inc: $(srcdir)/tool/ruby_vm/views/optunifs.inc.erb $(inc_common_headers)
$(srcs_vpath)insns.inc: $(srcdir)/tool/ruby_vm/views/insns.inc.erb $(inc_common_headers)
$(srcs_vpath)insns_info.inc: $(srcdir)/tool/ruby_vm/views/insns_info.inc.erb $(inc_common_headers) \
  $(srcdir)/tool/ruby_vm/views/_insn_type_chars.erb $(srcdir)/tool/ruby_vm/views/_insn_name_info.erb \
  $(srcdir)/tool/ruby_vm/views/_insn_len_info.erb $(srcdir)/tool/ruby_vm/views/_insn_operand_info.erb \
  $(srcdir)/tool/ruby_vm/views/_attributes.erb $(srcdir)/tool/ruby_vm/views/_insn_stack_increase.erb \
  $(srcdir)/tool/ruby_vm/views/_insn_sp_pc_dependency.erb
$(srcs_vpath)vmtc.inc: $(srcdir)/tool/ruby_vm/views/vmtc.inc.erb $(inc_common_headers)
$(srcs_vpath)vm.inc: $(srcdir)/tool/ruby_vm/views/vm.inc.erb $(inc_common_headers) \
  $(srcdir)/tool/ruby_vm/views/_insn_entry.erb $(srcdir)/tool/ruby_vm/views/_trace_instruction.erb
$(srcs_vpath)mjit_compile.inc: $(srcdir)/tool/ruby_vm/views/mjit_compile.inc.erb $(inc_common_headers) \
  $(srcdir)/tool/ruby_vm/views/_mjit_compile_insn.erb $(srcdir)/tool/ruby_vm/views/_mjit_compile_send.erb \
  $(srcdir)/tool/ruby_vm/views/_mjit_compile_ivar.erb \
  $(srcdir)/tool/ruby_vm/views/_mjit_compile_insn_body.erb $(srcdir)/tool/ruby_vm/views/_mjit_compile_pc_and_sp.erb

common-srcs: $(srcs_vpath)parse.c $(srcs_vpath)lex.c $(srcs_vpath)enc/trans/newline.c $(srcs_vpath)id.c \
	     srcs-lib srcs-ext incs

missing-srcs: $(srcdir)/missing/des_tables.c

srcs: common-srcs missing-srcs srcs-enc

EXT_SRCS = $(srcdir)/ext/ripper/ripper.c \
	   $(srcdir)/ext/rbconfig/sizeof/sizes.c \
	   $(srcdir)/ext/rbconfig/sizeof/limits.c \
	   $(srcdir)/ext/socket/constdefs.c \
	   $(srcdir)/ext/etc/constdefs.h \
	   # EXT_SRCS

srcs-ext: $(EXT_SRCS)
realclean-srcs-ext::
	$(Q)$(RM) $(EXT_SRCS)

EXTRA_SRCS = $(srcdir)/ext/json/parser/parser.c \
	     $(srcdir)/ext/date/zonetab.h \
	     $(empty)

srcs-extra: $(EXTRA_SRCS)
realclean-srcs-extra::
	$(Q)$(RM) $(EXTRA_SRCS)

LIB_SRCS = $(srcdir)/lib/unicode_normalize/tables.rb

srcs-lib: $(LIB_SRCS)

srcs-enc: $(ENC_MK)
	$(ECHO) making srcs under enc
	$(Q) $(MAKE) $(MAKE_ENC) srcs

all-incs: incs {$(VPATH)}encdb.h {$(VPATH)}transdb.h
incs: $(INSNS) {$(VPATH)}node_name.inc {$(VPATH)}known_errors.inc \
      {$(VPATH)}vm_call_iseq_optimized.inc $(srcdir)/revision.h \
      $(REVISION_H) \
      $(UNICODE_DATA_HEADERS) $(srcdir)/enc/jis/props.h \
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

node_name.inc: $(srcdir)/tool/node_name.rb $(srcdir)/node.h
	$(ECHO) generating $@
	$(Q) $(BASERUBY) -n $(srcdir)/tool/node_name.rb < $(srcdir)/node.h > $@

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

vm_call_iseq_optimized.inc: $(srcdir)/tool/mk_call_iseq_optimized.rb
	$(ECHO) generating $@
	$(Q) $(BASERUBY) $(srcdir)/tool/mk_call_iseq_optimized.rb > $@

$(MINIPRELUDE_C): $(COMPILE_PRELUDE)
	$(ECHO) generating $@
	$(Q) $(BASERUBY) $(srcdir)/tool/generic_erb.rb -I$(srcdir) -o $@ \
		$(srcdir)/template/prelude.c.tmpl

$(PRELUDE_C): $(COMPILE_PRELUDE) \
	   $(PRELUDE_SCRIPTS)
	$(ECHO) generating $@
	$(Q) $(BASERUBY) $(srcdir)/tool/generic_erb.rb -I$(srcdir) -c -o $@ \
		$(srcdir)/template/prelude.c.tmpl $(PRELUDE_SCRIPTS)

$(GOLF_PRELUDE_C): $(COMPILE_PRELUDE) {$(srcdir)}golf_prelude.rb
	$(ECHO) generating $@
	$(Q) $(BASERUBY) $(srcdir)/tool/generic_erb.rb -I$(srcdir) -c -o $@ \
		$(srcdir)/template/prelude.c.tmpl golf_prelude.rb

MAINCPPFLAGS = $(ENABLE_DEBUG_ENV:yes=-DRUBY_DEBUG_ENV=1)

$(MAINOBJ): $(srcdir)/$(MAINSRC)
	$(ECHO) compiling $(srcdir)/$(MAINSRC)
	$(Q) $(CC) $(MAINCPPFLAGS) $(CFLAGS) $(XCFLAGS) $(CPPFLAGS) $(COUTFLAG)$@ -c $(CSRCFLAG)$(srcdir)/$(MAINSRC)

{$(VPATH)}probes.dmyh: {$(srcdir)}probes.d $(srcdir)/tool/gen_dummy_probes.rb

probes.dmyh:
	$(BASERUBY) $(srcdir)/tool/gen_dummy_probes.rb $(srcdir)/probes.d > $@

probes.h: {$(VPATH)}probes.$(DTRACE_EXT)

prereq: incs srcs preludes PHONY

preludes: {$(VPATH)}prelude.c
preludes: {$(VPATH)}miniprelude.c
preludes: {$(srcdir)}golf_prelude.c

$(srcdir)/revision.h:
	$(Q)$(gnumake:yes=#) $(RM) $(@F)
	$(Q)$(gnumake:yes=#) exit > $@ || exit > $(@F)

revision.tmp::
	$(Q)exit > $@
revision.$(HAVE_BASERUBY:yes=tmp):: $(srcdir)/version.h $(srcdir)/tool/file2lastrev.rb $(REVISION_FORCE)
	$(Q) $(BASERUBY) $(srcdir)/tool/file2lastrev.rb -q --revision.h --srcdir="$(srcdir)" > $@

$(REVISION_H): revision.tmp
	$(Q)$(IFCHANGE) "--timestamp=$@" "$(srcdir)/revision.h" revision.tmp

$(srcdir)/ext/ripper/ripper.c: $(srcdir)/ext/ripper/tools/preproc.rb $(srcdir)/parse.y id.h $(srcdir)/ext/ripper/depend
	$(ECHO) generating $@
	$(Q) VPATH=$${PWD-`pwd`} && $(CHDIR) $(@D) && \
	sed -e 's/{\$$([^(){}]*)[^{}]*}//g' -e /AUTOGENERATED/q depend | \
	$(exec) $(MAKE) -f - $(mflags) \
		Q=$(Q) ECHO=$(ECHO) RM="$(RM)" BISON=$(YACC) top_srcdir=../.. srcdir=. VPATH="$${VPATH}" \
		RUBY="$(BASERUBY)" PATH_SEPARATOR="$(PATH_SEPARATOR)"

$(srcdir)/ext/json/parser/parser.c: $(srcdir)/ext/json/parser/parser.rl $(srcdir)/ext/json/parser/prereq.mk
	$(ECHO) generating $@
	$(Q) $(CHDIR) $(@D) && $(exec) $(MAKE) -f prereq.mk $(mflags) \
		Q=$(Q) ECHO=$(ECHO) top_srcdir=../../.. srcdir=. VPATH=../../.. BASERUBY="$(BASERUBY)"

$(srcdir)/ext/date/zonetab.h: $(srcdir)/ext/date/zonetab.list $(srcdir)/ext/date/prereq.mk
	$(ECHO) generating $@
	$(Q) $(CHDIR) $(@D) && $(exec) $(MAKE) -f prereq.mk $(mflags) \
		Q=$(Q) ECHO=$(ECHO) top_srcdir=../.. srcdir=. VPATH=../.. BASERUBY="$(BASERUBY)"

$(srcdir)/ext/rbconfig/sizeof/sizes.c: $(srcdir)/ext/rbconfig/sizeof/depend \
		$(srcdir)/tool/generic_erb.rb $(srcdir)/template/sizes.c.tmpl $(srcdir)/configure.ac
	$(ECHO) generating $@
	$(Q) $(CHDIR) $(@D) && \
	sed '/AUTOGENERATED/q' depend | \
	$(exec) $(MAKE) -f - $(mflags) \
		Q=$(Q) ECHO=$(ECHO) top_srcdir=../../.. srcdir=. VPATH=../../.. RUBY="$(BASERUBY)" $(@F)

$(srcdir)/ext/rbconfig/sizeof/limits.c: $(srcdir)/ext/rbconfig/sizeof/depend \
		$(srcdir)/tool/generic_erb.rb $(srcdir)/template/limits.c.tmpl
	$(ECHO) generating $@
	$(Q) $(CHDIR) $(@D) && \
	sed '/AUTOGENERATED/q' depend | \
	$(exec) $(MAKE) -f - $(mflags) \
		Q=$(Q) ECHO=$(ECHO) top_srcdir=../../.. srcdir=. VPATH=../../.. RUBY="$(BASERUBY)" $(@F)

$(srcdir)/ext/socket/constdefs.c: $(srcdir)/ext/socket/depend
	$(Q) $(CHDIR) $(@D) && \
	sed '/AUTOGENERATED/q' depend | \
	$(exec) $(MAKE) -f - $(mflags) \
		Q=$(Q) ECHO=$(ECHO) top_srcdir=../.. srcdir=. VPATH=../.. RUBY="$(BASERUBY)"

$(srcdir)/ext/etc/constdefs.h: $(srcdir)/ext/etc/depend
	$(Q) $(CHDIR) $(@D) && \
	sed '/AUTOGENERATED/q' depend | \
	$(exec) $(MAKE) -f - $(mflags) \
		Q=$(Q) ECHO=$(ECHO) top_srcdir=../.. srcdir=. VPATH=../.. RUBY="$(BASERUBY)"

##

run: fake miniruby$(EXEEXT) PHONY
	$(BTESTRUBY) $(TESTRUN_SCRIPT) $(RUNOPT)

runruby: $(PROGRAM) PHONY
	$(RUNRUBY) $(TESTRUN_SCRIPT)

parse: fake miniruby$(EXEEXT) PHONY
	$(BTESTRUBY) --dump=parsetree_with_comment,insns $(TESTRUN_SCRIPT)

bisect: PHONY
	$(srcdir)/tool/bisect.sh miniruby $(srcdir)

bisect-ruby: PHONY
	$(srcdir)/tool/bisect.sh ruby $(srcdir)

COMPARE_RUBY = $(BASERUBY)
BENCH_RUBY = $(RUNRUBY)
ITEM =
ARGS = $$(find $(srcdir)/benchmark -maxdepth 1 -name '$(ITEM)' -o -name '*$(ITEM)*.yml' -o -name '*$(ITEM)*.rb' | sort)
OPTS =

# See benchmark/README.md for details.
benchmark: miniruby$(EXEEXT) update-benchmark-driver PHONY
	$(BASERUBY) -rrubygems -I$(srcdir)/benchmark/lib $(srcdir)/benchmark/benchmark-driver/exe/benchmark-driver \
	            --executables="compare-ruby::$(COMPARE_RUBY) -I$(EXTOUT)/common --disable-gem" \
	            --executables="built-ruby::$(BENCH_RUBY) --disable-gem" \
	            $(ARGS) $(OPTS)

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

LLDB_INIT = command script import -r $(srcdir)/misc/lldb_cruby.py

lldb: miniruby$(EXEEXT) PHONY
	lldb -o '$(LLDB_INIT)' miniruby$(EXEEXT) -- $(TESTRUN_SCRIPT)

lldb-ruby: $(PROGRAM) PHONY
	lldb $(enable_shared:yes=-o 'target modules add ${LIBRUBY_SO}') -o '$(LLDB_INIT)' $(PROGRAM) -- $(TESTRUN_SCRIPT)

DISTPKGS = gzip,zip,all
dist:
	$(BASERUBY) $(srcdir)/tool/make-snapshot \
	-srcdir=$(srcdir) -packages=$(DISTPKGS) \
	-unicode-version=$(UNICODE_VERSION) \
	tmp $(RELNAME)

up:: update-remote

up::
	-$(Q)$(MAKE) $(mflags) Q=$(Q) REVISION_FORCE=PHONY "$(REVISION_H)"

up::
	-$(Q)$(MAKE) $(mflags) Q=$(Q) after-update

yes::
no::

after-update:: extract-extlibs

update-remote:: update-src update-download
update-download:: $(ALWAYS_UPDATE_UNICODE:yes=update-unicode)
update-download:: update-gems
update-download:: download-extlibs

update-mspec:
update-rubyspec:

update-config_files: PHONY
	$(Q) $(BASERUBY) -C "$(srcdir)" tool/downloader.rb -d tool --cache-dir=$(CACHE_DIR) -e gnu \
	    config.guess config.sub

update-gems: PHONY
	$(ECHO) Downloading bundled gem files...
	$(Q) $(BASERUBY) -C "$(srcdir)" \
	    -I./tool -rdownloader -answ \
	    -e 'gem, ver = *$$F' \
	    -e 'old = Dir.glob("gems/#{gem}-*.gem")' \
	    -e 'gem = "#{gem}-#{ver}.gem"' \
	    -e 'Downloader::RubyGems.download(gem, "gems", nil) and' \
	    -e '(old.delete("gems/#{gem}"); !old.empty?) and' \
	    -e 'File.unlink(*old) and' \
	    -e 'FileUtils.rm_rf(old.map{'"|n|"'n.chomp(".gem")})' \
	    gems/bundled_gems

extract-gems: PHONY
	$(ECHO) Extracting bundled gem files...
	$(Q) $(RUNRUBY) -C "$(srcdir)/gems" \
	    -I../tool -rgem-unpack -answ \
	    -e 'gem, ver = *$$F' \
	    -e 'Gem.unpack("#{gem}-#{ver}.gem")' \
	    bundled_gems

update-bundled_gems: PHONY
	$(Q) $(RUNRUBY) -rrubygems \
	    -pla \
	    -e '(gem,src), = Gem::SpecFetcher.fetcher.detect(:latest) {'"|s|" \
	    -e   's.platform=="ruby"&&s.name==$$F[0]' \
	    -e '}' \
	    -e 'gem = src.fetch_spec(gem)' \
	    -e '$$_ = [gem.name, gem.version, gem.metadata["source_code_uri"]||gem.homepage].join(" ")' \
	     "$(srcdir)/gems/bundled_gems" | \
	"$(IFCHANGE)" "$(srcdir)/gems/bundled_gems" -

test-bundled-gems-precheck: $(arch)-fake.rb programs

test-bundled-gems-fetch: $(PREP)
	$(Q) $(BASERUBY) -C $(srcdir)/gems ../tool/fetch-bundled_gems.rb src bundled_gems

test-bundled-gems-prepare: test-bundled-gems-precheck test-bundled-gems-fetch
	$(XRUBY) -C "$(srcdir)" bin/gem install --no-document \
		--install-dir .bundle --conservative "bundler" "minitest:~> 5" 'test-unit' 'rake' 'hoe' 'yard' 'pry' 'packnga'

PREPARE_BUNDLED_GEMS = test-bundled-gems-prepare
test-bundled-gems: $(TEST_RUNNABLE)-test-bundled-gems
yes-test-bundled-gems: test-bundled-gems-run
no-test-bundled-gems:
test-bundled-gems-run: $(PREPARE_BUNDLED_GEMS)

test-bundler-precheck: $(arch)-fake.rb programs

yes-test-bundler-prepare: test-bundler-precheck
	$(XRUBY) -C "$(srcdir)" bin/gem install --no-document \
		--install-dir .bundle --conservative "rspec:~> 3.5" "rake:~> 12.0" "parallel_tests:~> 2.29"

RSPECOPTS =
BUNDLER_SPECS =
test-bundler: $(TEST_RUNNABLE)-test-bundler
yes-test-bundler: yes-test-bundler-prepare
	$(XRUBY) -C $(srcdir) -Ispec/bundler .bundle/bin/rspec \
		--require spec_helper $(RSPECOPTS) spec/bundler/$(BUNDLER_SPECS)
no-test-bundler:

PARALLELRSPECOPTS = --runtime-log $(srcdir)/tmp/parallel_runtime_rspec.log
test-bundler-parallel: $(TEST_RUNNABLE)-test-bundler-parallel
yes-test-bundler-parallel: yes-test-bundler-prepare
	$(XRUBY) -C $(srcdir) -Ispec/bundler .bundle/bin/parallel_rspec \
		-o "--require $(srcdir)/spec/bundler/spec_helper --require $(srcdir)/spec/bundler/support/parallel" \
		$(PARALLELRSPECOPTS) spec/bundler/$(BUNDLER_SPECS)
no-test-bundler-parallel:

GEM = up
sync-default-gems:
	$(Q) $(XRUBY) -C "$(srcdir)" tool/sync_default_gems.rb $(GEM)

UNICODE_FILES = $(UNICODE_SRC_DATA_DIR)/UnicodeData.txt \
		$(UNICODE_SRC_DATA_DIR)/CompositionExclusions.txt \
		$(UNICODE_SRC_DATA_DIR)/NormalizationTest.txt \
		$(UNICODE_SRC_DATA_DIR)/CaseFolding.txt \
		$(UNICODE_SRC_DATA_DIR)/SpecialCasing.txt \
		$(empty)

UNICODE_PROPERTY_FILES =  \
		$(UNICODE_SRC_DATA_DIR)/Blocks.txt \
		$(UNICODE_SRC_DATA_DIR)/DerivedAge.txt \
		$(UNICODE_SRC_DATA_DIR)/DerivedCoreProperties.txt \
		$(UNICODE_SRC_DATA_DIR)/PropList.txt \
		$(UNICODE_SRC_DATA_DIR)/PropertyAliases.txt \
		$(UNICODE_SRC_DATA_DIR)/PropertyValueAliases.txt \
		$(UNICODE_SRC_DATA_DIR)/Scripts.txt \
		$(empty)

UNICODE_AUXILIARY_FILES =  \
		$(UNICODE_SRC_DATA_DIR)/auxiliary/GraphemeBreakProperty.txt \
		$(UNICODE_SRC_DATA_DIR)/auxiliary/GraphemeBreakTest.txt \
		$(empty)

UNICODE_EMOJI_FILES = \
		$(UNICODE_SRC_EMOJI_DATA_DIR)/emoji-data.txt \
		$(UNICODE_SRC_EMOJI_DATA_DIR)/emoji-sequences.txt \
		$(UNICODE_SRC_EMOJI_DATA_DIR)/emoji-test.txt \
		$(UNICODE_SRC_EMOJI_DATA_DIR)/emoji-variation-sequences.txt \
		$(UNICODE_SRC_EMOJI_DATA_DIR)/emoji-zwj-sequences.txt \
		$(empty)

update-unicode: $(UNICODE_FILES) $(UNICODE_PROPERTY_FILES) \
		$(UNICODE_AUXILIARY_FILES) $(UNICODE_EMOJI_FILES)

CACHE_DIR = $(srcdir)/.downloaded-cache
UNICODE_DOWNLOAD = \
	$(BASERUBY) $(srcdir)/tool/downloader.rb \
	    --cache-dir=$(CACHE_DIR) \
	    --unicode-beta $(UNICODE_BETA) \
	    -d $(UNICODE_SRC_DATA_DIR) \
	    -p $(UNICODE_VERSION)/ucd \
	    -e $(ALWAYS_UPDATE_UNICODE:yes=-a) unicode
UNICODE_AUXILIARY_DOWNLOAD = \
	$(BASERUBY) $(srcdir)/tool/downloader.rb \
	    --cache-dir=$(CACHE_DIR) \
	    --unicode-beta $(UNICODE_BETA) \
	    -d $(UNICODE_SRC_DATA_DIR)/auxiliary \
	    -p $(UNICODE_VERSION)/ucd/auxiliary \
	    -e $(ALWAYS_UPDATE_UNICODE:yes=-a) unicode
UNICODE_EMOJI_DOWNLOAD = \
	$(BASERUBY) $(srcdir)/tool/downloader.rb \
	    --cache-dir=$(CACHE_DIR) \
	    --unicode-beta $(UNICODE_BETA) \
	    -d $(UNICODE_SRC_EMOJI_DATA_DIR) \
	    -p emoji/$(UNICODE_EMOJI_VERSION) \
	    -e $(ALWAYS_UPDATE_UNICODE:yes=-a) unicode

$(UNICODE_FILES) $(UNICODE_PROPERTY_FILES): update-unicode-files
update-unicode-files:
	$(ECHO) Downloading Unicode $(UNICODE_VERSION) data and  property files...
	$(Q) $(MAKEDIRS) "$(UNICODE_SRC_DATA_DIR)"
	$(Q) $(UNICODE_DOWNLOAD) $(UNICODE_FILES) $(UNICODE_PROPERTY_FILES)

$(UNICODE_AUXILIARY_FILES): update-unicode-auxiliary-files
update-unicode-auxiliary-files:
	$(ECHO) Downloading Unicode $(UNICODE_VERSION) auxiliary files...
	$(Q) $(MAKEDIRS) "$(UNICODE_SRC_DATA_DIR)/auxiliary"
	$(Q) $(UNICODE_AUXILIARY_DOWNLOAD) $(UNICODE_AUXILIARY_FILES)

$(UNICODE_EMOJI_FILES): update-unicode-emoji-files
update-unicode-emoji-files:
	$(ECHO) Downloading Unicode emoji $(UNICODE_EMOJI_VERSION) files...
	$(Q) $(MAKEDIRS) "$(UNICODE_SRC_EMOJI_DATA_DIR)"
	$(Q) $(UNICODE_EMOJI_DOWNLOAD) $(UNICODE_EMOJI_FILES)

$(srcdir)/lib/unicode_normalize/$(HAVE_BASERUBY:yes=tables.rb): \
	$(UNICODE_SRC_DATA_DIR)/.unicode-tables.time

$(UNICODE_SRC_DATA_DIR)/$(ALWAYS_UPDATE_UNICODE:yes=.unicode-tables.time): \
	$(UNICODE_FILES) $(UNICODE_PROPERTY_FILES) \
	$(UNICODE_AUXILIARY_FILES) $(UNICODE_EMOJI_FILES)

touch-unicode-files:
	$(MAKEDIRS) $(UNICODE_SRC_DATA_DIR)
	touch $(UNICODE_SRC_DATA_DIR)/.unicode-tables.time $(UNICODE_DATA_HEADERS)

UNICODE_TABLES_TIMESTAMP = yes
$(UNICODE_SRC_DATA_DIR)/.unicode-tables.time: $(srcdir)/tool/generic_erb.rb \
		$(srcdir)/template/unicode_norm_gen.tmpl \
		$(ALWAYS_UPDATE_UNICODE:yes=update-unicode)
	$(Q) $(MAKE) $(@D)
	$(Q) $(BASERUBY) $(srcdir)/tool/generic_erb.rb \
		-c $(UNICODE_TABLES_TIMESTAMP:yes=-t$@) \
		-o $(srcdir)/lib/unicode_normalize/tables.rb \
		-I $(srcdir) \
		$(srcdir)/template/unicode_norm_gen.tmpl \
		$(UNICODE_DATA_DIR) lib/unicode_normalize

$(UNICODE_SRC_DATA_DIR):
	$(Q) $(exec) $(MAKEDIRS) $@ || exit && echo $(MAKE)

$(UNICODE_HDR_DIR)/$(ALWAYS_UPDATE_UNICODE:yes=name2ctype.h): \
		$(srcdir)/tool/enc-unicode.rb \
		$(UNICODE_SRC_DATA_DIR)/UnicodeData.txt \
		$(UNICODE_PROPERTY_FILES)

$(UNICODE_HDR_DIR)/name2ctype.h:
	$(MAKEDIRS) $(@D)
	$(BOOTSTRAPRUBY) $(srcdir)/tool/enc-unicode.rb --header \
		$(UNICODE_SRC_DATA_DIR) $(UNICODE_SRC_EMOJI_DATA_DIR) > $@.new
	$(MV) $@.new $@

# the next non-comment line was:
# $(UNICODE_HDR_DIR)/casefold.h: $(srcdir)/enc/unicode/case-folding.rb \
# but was changed to make sure CI works on systems that don't have gperf
unicode-up: $(UNICODE_DATA_HEADERS)

$(UNICODE_HDR_DIR)/$(ALWAYS_UPDATE_UNICODE:yes=casefold.h): \
		$(srcdir)/enc/unicode/case-folding.rb \
		$(UNICODE_SRC_DATA_DIR)/UnicodeData.txt \
		$(UNICODE_SRC_DATA_DIR)/SpecialCasing.txt \
		$(UNICODE_SRC_DATA_DIR)/CaseFolding.txt

$(UNICODE_HDR_DIR)/casefold.h:
	$(MAKEDIRS) $(@D)
	$(Q) $(BASERUBY) $(srcdir)/enc/unicode/case-folding.rb \
		--output-file=$@ \
		--mapping-data-directory=$(UNICODE_SRC_DATA_DIR)

download-extlibs:
	$(Q) $(BASERUBY) -C $(srcdir) -w tool/extlibs.rb --download ext

extract-extlibs:
	$(Q) $(BASERUBY) -C $(srcdir) -w tool/extlibs.rb --all ext

clean-extlibs:
	$(Q) $(RMALL) $(srcdir)/.downloaded-cache

clean-gems:
	$(Q) $(RM) gems/*.gem

CLEAN_CACHE = clean-extlibs

info: info-program info-libruby_a info-libruby_so info-arch
info-program: PHONY
	@echo PROGRAM=$(PROGRAM)
info-libruby_a: PHONY
	@echo LIBRUBY_A=$(LIBRUBY_A)
info-libruby_so: PHONY
	@echo LIBRUBY_SO=$(LIBRUBY_SO)
info-arch: PHONY
	@echo arch=$(arch)

exam: check

love: sudo-precheck up all test exam install
	@echo love is all you need

great: exam

yes-test-all no-test-all: sudo-precheck

sudo-precheck: PHONY
	@$(SUDO) echo > $(NULL)

update-man-date: PHONY
	-$(Q) $(BASERUBY) -I"$(srcdir)/tool/lib" -rvcs -i -p \
	-e 'BEGIN{@vcs=VCS.detect(ARGV.shift)}' \
	-e '$$_.sub!(/^(\.Dd ).*/){$$1+@vcs.modified(ARGF.path).strftime("%B %d, %Y")}' \
	"$(srcdir)" "$(srcdir)"/man/*.1

HELP_EXTRA_TASKS = ""

help: PHONY
	$(MESSAGE_BEGIN) \
	"                Makefile of Ruby" \
	"" \
	"targets:" \
	"  all (default):       builds all of below" \
	"  miniruby:            builds only miniruby" \
	"  encs:                builds encodings" \
	"  exts:                builds extensions" \
	"  main:                builds encodings, extensions and ruby" \
	"  docs:                builds documents" \
	"  install-capi:        builds C API documents" \
	"  run:                 runs test.rb by miniruby" \
	"  runruby:             runs test.rb by ruby you just built" \
	"  gdb:                 runs test.rb by miniruby under gdb" \
	"  gdb-ruby:            runs test.rb by ruby under gdb" \
	"  check:               equals make test test-tool test-all test-spec" \
	"  test:                ruby core tests [BTESTS=<bootstraptest files>]" \
	"  test-all:            all ruby tests [TESTOPTS=-j4 TESTS=<test files>]" \
	"  test-spec:           run the Ruby spec suite [SPECOPTS=<specs, opts>]" \
	"  test-bundler:        run the Bundler spec" \
	"  test-bundled-gems:   run the test suite of bundled gems" \
	"  test-tool:           tests under the tool/test" \
	"  update-gems:         download files of the bundled gems" \
	"  update-bundled_gems: update the latest version of bundled gems" \
	"  sync-default-gems:   sync default gems from upstream [GEM=<gem_name>]" \
	"  up:                  update local copy and autogenerated files" \
	"  benchmark:           benchmark this ruby and COMPARE_RUBY." \
	"  gcbench:             gc benchmark [GCBENCH_ITEM=<item_name>]" \
	"  install:             install all ruby distributions" \
	"  install-nodoc:       install without rdoc" \
	"  install-cross:       install cross compiling stuff" \
	"  clean:               clean for tarball" \
	"  distclean:           clean for repository" \
	"  golf:                build goruby for golfers" \
	$(HELP_EXTRA_TASKS) \
	"see DeveloperHowto for more detail: " \
	"  https://bugs.ruby-lang.org/projects/ruby/wiki/DeveloperHowto" \
	$(MESSAGE_END)

# AUTOGENERATED DEPENDENCIES START
addr2line.$(OBJEXT): {$(VPATH)}addr2line.c
addr2line.$(OBJEXT): {$(VPATH)}addr2line.h
addr2line.$(OBJEXT): {$(VPATH)}config.h
addr2line.$(OBJEXT): {$(VPATH)}defines.h
addr2line.$(OBJEXT): {$(VPATH)}missing.h
array.$(OBJEXT): $(hdrdir)/ruby.h
array.$(OBJEXT): $(hdrdir)/ruby/ruby.h
array.$(OBJEXT): {$(VPATH)}array.c
array.$(OBJEXT): {$(VPATH)}assert.h
array.$(OBJEXT): {$(VPATH)}config.h
array.$(OBJEXT): {$(VPATH)}debug_counter.h
array.$(OBJEXT): {$(VPATH)}defines.h
array.$(OBJEXT): {$(VPATH)}encoding.h
array.$(OBJEXT): {$(VPATH)}gc.h
array.$(OBJEXT): {$(VPATH)}id.h
array.$(OBJEXT): {$(VPATH)}intern.h
array.$(OBJEXT): {$(VPATH)}internal.h
array.$(OBJEXT): {$(VPATH)}io.h
array.$(OBJEXT): {$(VPATH)}missing.h
array.$(OBJEXT): {$(VPATH)}onigmo.h
array.$(OBJEXT): {$(VPATH)}oniguruma.h
array.$(OBJEXT): {$(VPATH)}probes.dmyh
array.$(OBJEXT): {$(VPATH)}probes.h
array.$(OBJEXT): {$(VPATH)}ruby_assert.h
array.$(OBJEXT): {$(VPATH)}st.h
array.$(OBJEXT): {$(VPATH)}subst.h
array.$(OBJEXT): {$(VPATH)}transient_heap.h
array.$(OBJEXT): {$(VPATH)}util.h
ast.$(OBJEXT): $(CCAN_DIR)/check_type/check_type.h
ast.$(OBJEXT): $(CCAN_DIR)/container_of/container_of.h
ast.$(OBJEXT): $(CCAN_DIR)/list/list.h
ast.$(OBJEXT): $(CCAN_DIR)/str/str.h
ast.$(OBJEXT): $(hdrdir)/ruby.h
ast.$(OBJEXT): $(hdrdir)/ruby/ruby.h
ast.$(OBJEXT): {$(VPATH)}assert.h
ast.$(OBJEXT): {$(VPATH)}ast.c
ast.$(OBJEXT): {$(VPATH)}config.h
ast.$(OBJEXT): {$(VPATH)}defines.h
ast.$(OBJEXT): {$(VPATH)}encoding.h
ast.$(OBJEXT): {$(VPATH)}id.h
ast.$(OBJEXT): {$(VPATH)}intern.h
ast.$(OBJEXT): {$(VPATH)}internal.h
ast.$(OBJEXT): {$(VPATH)}iseq.h
ast.$(OBJEXT): {$(VPATH)}method.h
ast.$(OBJEXT): {$(VPATH)}missing.h
ast.$(OBJEXT): {$(VPATH)}node.h
ast.$(OBJEXT): {$(VPATH)}onigmo.h
ast.$(OBJEXT): {$(VPATH)}oniguruma.h
ast.$(OBJEXT): {$(VPATH)}ruby_assert.h
ast.$(OBJEXT): {$(VPATH)}ruby_atomic.h
ast.$(OBJEXT): {$(VPATH)}st.h
ast.$(OBJEXT): {$(VPATH)}subst.h
ast.$(OBJEXT): {$(VPATH)}thread_$(THREAD_MODEL).h
ast.$(OBJEXT): {$(VPATH)}thread_native.h
ast.$(OBJEXT): {$(VPATH)}util.h
ast.$(OBJEXT): {$(VPATH)}vm_core.h
ast.$(OBJEXT): {$(VPATH)}vm_opts.h
bignum.$(OBJEXT): $(hdrdir)/ruby.h
bignum.$(OBJEXT): $(hdrdir)/ruby/ruby.h
bignum.$(OBJEXT): {$(VPATH)}assert.h
bignum.$(OBJEXT): {$(VPATH)}bignum.c
bignum.$(OBJEXT): {$(VPATH)}config.h
bignum.$(OBJEXT): {$(VPATH)}defines.h
bignum.$(OBJEXT): {$(VPATH)}encoding.h
bignum.$(OBJEXT): {$(VPATH)}id.h
bignum.$(OBJEXT): {$(VPATH)}intern.h
bignum.$(OBJEXT): {$(VPATH)}internal.h
bignum.$(OBJEXT): {$(VPATH)}io.h
bignum.$(OBJEXT): {$(VPATH)}missing.h
bignum.$(OBJEXT): {$(VPATH)}onigmo.h
bignum.$(OBJEXT): {$(VPATH)}oniguruma.h
bignum.$(OBJEXT): {$(VPATH)}ruby_assert.h
bignum.$(OBJEXT): {$(VPATH)}st.h
bignum.$(OBJEXT): {$(VPATH)}subst.h
bignum.$(OBJEXT): {$(VPATH)}thread.h
bignum.$(OBJEXT): {$(VPATH)}util.h
class.$(OBJEXT): $(CCAN_DIR)/check_type/check_type.h
class.$(OBJEXT): $(CCAN_DIR)/container_of/container_of.h
class.$(OBJEXT): $(CCAN_DIR)/list/list.h
class.$(OBJEXT): $(CCAN_DIR)/str/str.h
class.$(OBJEXT): $(hdrdir)/ruby.h
class.$(OBJEXT): $(hdrdir)/ruby/ruby.h
class.$(OBJEXT): {$(VPATH)}assert.h
class.$(OBJEXT): {$(VPATH)}class.c
class.$(OBJEXT): {$(VPATH)}config.h
class.$(OBJEXT): {$(VPATH)}constant.h
class.$(OBJEXT): {$(VPATH)}defines.h
class.$(OBJEXT): {$(VPATH)}encoding.h
class.$(OBJEXT): {$(VPATH)}id.h
class.$(OBJEXT): {$(VPATH)}id_table.h
class.$(OBJEXT): {$(VPATH)}intern.h
class.$(OBJEXT): {$(VPATH)}internal.h
class.$(OBJEXT): {$(VPATH)}io.h
class.$(OBJEXT): {$(VPATH)}method.h
class.$(OBJEXT): {$(VPATH)}missing.h
class.$(OBJEXT): {$(VPATH)}node.h
class.$(OBJEXT): {$(VPATH)}onigmo.h
class.$(OBJEXT): {$(VPATH)}oniguruma.h
class.$(OBJEXT): {$(VPATH)}ruby_assert.h
class.$(OBJEXT): {$(VPATH)}ruby_atomic.h
class.$(OBJEXT): {$(VPATH)}st.h
class.$(OBJEXT): {$(VPATH)}subst.h
class.$(OBJEXT): {$(VPATH)}thread_$(THREAD_MODEL).h
class.$(OBJEXT): {$(VPATH)}thread_native.h
class.$(OBJEXT): {$(VPATH)}vm_core.h
class.$(OBJEXT): {$(VPATH)}vm_debug.h
class.$(OBJEXT): {$(VPATH)}vm_opts.h
compar.$(OBJEXT): $(hdrdir)/ruby.h
compar.$(OBJEXT): $(hdrdir)/ruby/ruby.h
compar.$(OBJEXT): {$(VPATH)}assert.h
compar.$(OBJEXT): {$(VPATH)}compar.c
compar.$(OBJEXT): {$(VPATH)}config.h
compar.$(OBJEXT): {$(VPATH)}defines.h
compar.$(OBJEXT): {$(VPATH)}id.h
compar.$(OBJEXT): {$(VPATH)}intern.h
compar.$(OBJEXT): {$(VPATH)}internal.h
compar.$(OBJEXT): {$(VPATH)}missing.h
compar.$(OBJEXT): {$(VPATH)}st.h
compar.$(OBJEXT): {$(VPATH)}subst.h
compile.$(OBJEXT): $(CCAN_DIR)/check_type/check_type.h
compile.$(OBJEXT): $(CCAN_DIR)/container_of/container_of.h
compile.$(OBJEXT): $(CCAN_DIR)/list/list.h
compile.$(OBJEXT): $(CCAN_DIR)/str/str.h
compile.$(OBJEXT): $(hdrdir)/ruby.h
compile.$(OBJEXT): $(hdrdir)/ruby/ruby.h
compile.$(OBJEXT): {$(VPATH)}assert.h
compile.$(OBJEXT): {$(VPATH)}compile.c
compile.$(OBJEXT): {$(VPATH)}config.h
compile.$(OBJEXT): {$(VPATH)}defines.h
compile.$(OBJEXT): {$(VPATH)}encindex.h
compile.$(OBJEXT): {$(VPATH)}encoding.h
compile.$(OBJEXT): {$(VPATH)}gc.h
compile.$(OBJEXT): {$(VPATH)}id.h
compile.$(OBJEXT): {$(VPATH)}id_table.h
compile.$(OBJEXT): {$(VPATH)}insns.def
compile.$(OBJEXT): {$(VPATH)}insns.inc
compile.$(OBJEXT): {$(VPATH)}insns_info.inc
compile.$(OBJEXT): {$(VPATH)}intern.h
compile.$(OBJEXT): {$(VPATH)}internal.h
compile.$(OBJEXT): {$(VPATH)}io.h
compile.$(OBJEXT): {$(VPATH)}iseq.h
compile.$(OBJEXT): {$(VPATH)}method.h
compile.$(OBJEXT): {$(VPATH)}missing.h
compile.$(OBJEXT): {$(VPATH)}node.h
compile.$(OBJEXT): {$(VPATH)}onigmo.h
compile.$(OBJEXT): {$(VPATH)}oniguruma.h
compile.$(OBJEXT): {$(VPATH)}opt_sc.inc
compile.$(OBJEXT): {$(VPATH)}optinsn.inc
compile.$(OBJEXT): {$(VPATH)}optunifs.inc
compile.$(OBJEXT): {$(VPATH)}re.h
compile.$(OBJEXT): {$(VPATH)}regex.h
compile.$(OBJEXT): {$(VPATH)}ruby_assert.h
compile.$(OBJEXT): {$(VPATH)}ruby_atomic.h
compile.$(OBJEXT): {$(VPATH)}st.h
compile.$(OBJEXT): {$(VPATH)}subst.h
compile.$(OBJEXT): {$(VPATH)}thread_$(THREAD_MODEL).h
compile.$(OBJEXT): {$(VPATH)}thread_native.h
compile.$(OBJEXT): {$(VPATH)}util.h
compile.$(OBJEXT): {$(VPATH)}vm_core.h
compile.$(OBJEXT): {$(VPATH)}vm_debug.h
compile.$(OBJEXT): {$(VPATH)}vm_opts.h
complex.$(OBJEXT): $(hdrdir)/ruby.h
complex.$(OBJEXT): $(hdrdir)/ruby/ruby.h
complex.$(OBJEXT): {$(VPATH)}assert.h
complex.$(OBJEXT): {$(VPATH)}complex.c
complex.$(OBJEXT): {$(VPATH)}config.h
complex.$(OBJEXT): {$(VPATH)}defines.h
complex.$(OBJEXT): {$(VPATH)}encoding.h
complex.$(OBJEXT): {$(VPATH)}id.h
complex.$(OBJEXT): {$(VPATH)}intern.h
complex.$(OBJEXT): {$(VPATH)}internal.h
complex.$(OBJEXT): {$(VPATH)}io.h
complex.$(OBJEXT): {$(VPATH)}missing.h
complex.$(OBJEXT): {$(VPATH)}onigmo.h
complex.$(OBJEXT): {$(VPATH)}oniguruma.h
complex.$(OBJEXT): {$(VPATH)}ruby_assert.h
complex.$(OBJEXT): {$(VPATH)}st.h
complex.$(OBJEXT): {$(VPATH)}subst.h
cont.$(OBJEXT): $(CCAN_DIR)/check_type/check_type.h
cont.$(OBJEXT): $(CCAN_DIR)/container_of/container_of.h
cont.$(OBJEXT): $(CCAN_DIR)/list/list.h
cont.$(OBJEXT): $(CCAN_DIR)/str/str.h
cont.$(OBJEXT): $(hdrdir)/ruby.h
cont.$(OBJEXT): $(hdrdir)/ruby/ruby.h
cont.$(OBJEXT): {$(VPATH)}$(COROUTINE_H)
cont.$(OBJEXT): {$(VPATH)}assert.h
cont.$(OBJEXT): {$(VPATH)}config.h
cont.$(OBJEXT): {$(VPATH)}cont.c
cont.$(OBJEXT): {$(VPATH)}debug_counter.h
cont.$(OBJEXT): {$(VPATH)}defines.h
cont.$(OBJEXT): {$(VPATH)}encoding.h
cont.$(OBJEXT): {$(VPATH)}eval_intern.h
cont.$(OBJEXT): {$(VPATH)}gc.h
cont.$(OBJEXT): {$(VPATH)}id.h
cont.$(OBJEXT): {$(VPATH)}intern.h
cont.$(OBJEXT): {$(VPATH)}internal.h
cont.$(OBJEXT): {$(VPATH)}io.h
cont.$(OBJEXT): {$(VPATH)}method.h
cont.$(OBJEXT): {$(VPATH)}missing.h
cont.$(OBJEXT): {$(VPATH)}mjit.h
cont.$(OBJEXT): {$(VPATH)}node.h
cont.$(OBJEXT): {$(VPATH)}onigmo.h
cont.$(OBJEXT): {$(VPATH)}oniguruma.h
cont.$(OBJEXT): {$(VPATH)}ruby_assert.h
cont.$(OBJEXT): {$(VPATH)}ruby_atomic.h
cont.$(OBJEXT): {$(VPATH)}st.h
cont.$(OBJEXT): {$(VPATH)}subst.h
cont.$(OBJEXT): {$(VPATH)}thread_$(THREAD_MODEL).h
cont.$(OBJEXT): {$(VPATH)}thread_native.h
cont.$(OBJEXT): {$(VPATH)}vm_core.h
cont.$(OBJEXT): {$(VPATH)}vm_debug.h
cont.$(OBJEXT): {$(VPATH)}vm_opts.h
debug.$(OBJEXT): $(CCAN_DIR)/check_type/check_type.h
debug.$(OBJEXT): $(CCAN_DIR)/container_of/container_of.h
debug.$(OBJEXT): $(CCAN_DIR)/list/list.h
debug.$(OBJEXT): $(CCAN_DIR)/str/str.h
debug.$(OBJEXT): $(hdrdir)/ruby.h
debug.$(OBJEXT): $(hdrdir)/ruby/ruby.h
debug.$(OBJEXT): {$(VPATH)}assert.h
debug.$(OBJEXT): {$(VPATH)}config.h
debug.$(OBJEXT): {$(VPATH)}debug.c
debug.$(OBJEXT): {$(VPATH)}defines.h
debug.$(OBJEXT): {$(VPATH)}encoding.h
debug.$(OBJEXT): {$(VPATH)}eval_intern.h
debug.$(OBJEXT): {$(VPATH)}gc.h
debug.$(OBJEXT): {$(VPATH)}id.h
debug.$(OBJEXT): {$(VPATH)}intern.h
debug.$(OBJEXT): {$(VPATH)}internal.h
debug.$(OBJEXT): {$(VPATH)}io.h
debug.$(OBJEXT): {$(VPATH)}method.h
debug.$(OBJEXT): {$(VPATH)}missing.h
debug.$(OBJEXT): {$(VPATH)}node.h
debug.$(OBJEXT): {$(VPATH)}onigmo.h
debug.$(OBJEXT): {$(VPATH)}oniguruma.h
debug.$(OBJEXT): {$(VPATH)}ruby_assert.h
debug.$(OBJEXT): {$(VPATH)}ruby_atomic.h
debug.$(OBJEXT): {$(VPATH)}st.h
debug.$(OBJEXT): {$(VPATH)}subst.h
debug.$(OBJEXT): {$(VPATH)}symbol.h
debug.$(OBJEXT): {$(VPATH)}thread_$(THREAD_MODEL).h
debug.$(OBJEXT): {$(VPATH)}thread_native.h
debug.$(OBJEXT): {$(VPATH)}util.h
debug.$(OBJEXT): {$(VPATH)}vm_core.h
debug.$(OBJEXT): {$(VPATH)}vm_debug.h
debug.$(OBJEXT): {$(VPATH)}vm_opts.h
debug_counter.$(OBJEXT): $(hdrdir)/ruby/ruby.h
debug_counter.$(OBJEXT): {$(VPATH)}config.h
debug_counter.$(OBJEXT): {$(VPATH)}debug_counter.c
debug_counter.$(OBJEXT): {$(VPATH)}debug_counter.h
debug_counter.$(OBJEXT): {$(VPATH)}defines.h
debug_counter.$(OBJEXT): {$(VPATH)}encoding.h
debug_counter.$(OBJEXT): {$(VPATH)}intern.h
debug_counter.$(OBJEXT): {$(VPATH)}internal.h
debug_counter.$(OBJEXT): {$(VPATH)}io.h
debug_counter.$(OBJEXT): {$(VPATH)}missing.h
debug_counter.$(OBJEXT): {$(VPATH)}onigmo.h
debug_counter.$(OBJEXT): {$(VPATH)}oniguruma.h
debug_counter.$(OBJEXT): {$(VPATH)}st.h
debug_counter.$(OBJEXT): {$(VPATH)}subst.h
dir.$(OBJEXT): $(hdrdir)/ruby.h
dir.$(OBJEXT): $(hdrdir)/ruby/ruby.h
dir.$(OBJEXT): {$(VPATH)}assert.h
dir.$(OBJEXT): {$(VPATH)}config.h
dir.$(OBJEXT): {$(VPATH)}defines.h
dir.$(OBJEXT): {$(VPATH)}dir.c
dir.$(OBJEXT): {$(VPATH)}encindex.h
dir.$(OBJEXT): {$(VPATH)}encoding.h
dir.$(OBJEXT): {$(VPATH)}id.h
dir.$(OBJEXT): {$(VPATH)}intern.h
dir.$(OBJEXT): {$(VPATH)}internal.h
dir.$(OBJEXT): {$(VPATH)}io.h
dir.$(OBJEXT): {$(VPATH)}missing.h
dir.$(OBJEXT): {$(VPATH)}onigmo.h
dir.$(OBJEXT): {$(VPATH)}oniguruma.h
dir.$(OBJEXT): {$(VPATH)}st.h
dir.$(OBJEXT): {$(VPATH)}subst.h
dir.$(OBJEXT): {$(VPATH)}thread.h
dir.$(OBJEXT): {$(VPATH)}util.h
dln.$(OBJEXT): $(hdrdir)/ruby.h
dln.$(OBJEXT): $(hdrdir)/ruby/ruby.h
dln.$(OBJEXT): {$(VPATH)}assert.h
dln.$(OBJEXT): {$(VPATH)}config.h
dln.$(OBJEXT): {$(VPATH)}defines.h
dln.$(OBJEXT): {$(VPATH)}dln.c
dln.$(OBJEXT): {$(VPATH)}dln.h
dln.$(OBJEXT): {$(VPATH)}intern.h
dln.$(OBJEXT): {$(VPATH)}internal.h
dln.$(OBJEXT): {$(VPATH)}missing.h
dln.$(OBJEXT): {$(VPATH)}st.h
dln.$(OBJEXT): {$(VPATH)}subst.h
dln_find.$(OBJEXT): $(hdrdir)/ruby/ruby.h
dln_find.$(OBJEXT): {$(VPATH)}assert.h
dln_find.$(OBJEXT): {$(VPATH)}config.h
dln_find.$(OBJEXT): {$(VPATH)}defines.h
dln_find.$(OBJEXT): {$(VPATH)}dln.h
dln_find.$(OBJEXT): {$(VPATH)}dln_find.c
dln_find.$(OBJEXT): {$(VPATH)}intern.h
dln_find.$(OBJEXT): {$(VPATH)}missing.h
dln_find.$(OBJEXT): {$(VPATH)}st.h
dln_find.$(OBJEXT): {$(VPATH)}subst.h
dmydln.$(OBJEXT): $(hdrdir)/ruby/ruby.h
dmydln.$(OBJEXT): {$(VPATH)}assert.h
dmydln.$(OBJEXT): {$(VPATH)}config.h
dmydln.$(OBJEXT): {$(VPATH)}defines.h
dmydln.$(OBJEXT): {$(VPATH)}dmydln.c
dmydln.$(OBJEXT): {$(VPATH)}intern.h
dmydln.$(OBJEXT): {$(VPATH)}missing.h
dmydln.$(OBJEXT): {$(VPATH)}st.h
dmydln.$(OBJEXT): {$(VPATH)}subst.h
dmyenc.$(OBJEXT): {$(VPATH)}dmyenc.c
dmyext.$(OBJEXT): {$(VPATH)}dmyext.c
enc/ascii.$(OBJEXT): {$(VPATH)}config.h
enc/ascii.$(OBJEXT): {$(VPATH)}defines.h
enc/ascii.$(OBJEXT): {$(VPATH)}enc/ascii.c
enc/ascii.$(OBJEXT): {$(VPATH)}encindex.h
enc/ascii.$(OBJEXT): {$(VPATH)}missing.h
enc/ascii.$(OBJEXT): {$(VPATH)}oniguruma.h
enc/ascii.$(OBJEXT): {$(VPATH)}regenc.h
enc/trans/newline.$(OBJEXT): $(hdrdir)/ruby/ruby.h
enc/trans/newline.$(OBJEXT): {$(VPATH)}config.h
enc/trans/newline.$(OBJEXT): {$(VPATH)}defines.h
enc/trans/newline.$(OBJEXT): {$(VPATH)}enc/trans/newline.c
enc/trans/newline.$(OBJEXT): {$(VPATH)}intern.h
enc/trans/newline.$(OBJEXT): {$(VPATH)}missing.h
enc/trans/newline.$(OBJEXT): {$(VPATH)}st.h
enc/trans/newline.$(OBJEXT): {$(VPATH)}subst.h
enc/trans/newline.$(OBJEXT): {$(VPATH)}transcode_data.h
enc/unicode.$(OBJEXT): $(UNICODE_HDR_DIR)/casefold.h
enc/unicode.$(OBJEXT): $(UNICODE_HDR_DIR)/name2ctype.h
enc/unicode.$(OBJEXT): $(hdrdir)/ruby/ruby.h
enc/unicode.$(OBJEXT): {$(VPATH)}config.h
enc/unicode.$(OBJEXT): {$(VPATH)}defines.h
enc/unicode.$(OBJEXT): {$(VPATH)}enc/unicode.c
enc/unicode.$(OBJEXT): {$(VPATH)}intern.h
enc/unicode.$(OBJEXT): {$(VPATH)}missing.h
enc/unicode.$(OBJEXT): {$(VPATH)}onigmo.h
enc/unicode.$(OBJEXT): {$(VPATH)}oniguruma.h
enc/unicode.$(OBJEXT): {$(VPATH)}regenc.h
enc/unicode.$(OBJEXT): {$(VPATH)}regint.h
enc/unicode.$(OBJEXT): {$(VPATH)}st.h
enc/unicode.$(OBJEXT): {$(VPATH)}subst.h
enc/us_ascii.$(OBJEXT): {$(VPATH)}config.h
enc/us_ascii.$(OBJEXT): {$(VPATH)}defines.h
enc/us_ascii.$(OBJEXT): {$(VPATH)}enc/us_ascii.c
enc/us_ascii.$(OBJEXT): {$(VPATH)}encindex.h
enc/us_ascii.$(OBJEXT): {$(VPATH)}missing.h
enc/us_ascii.$(OBJEXT): {$(VPATH)}oniguruma.h
enc/us_ascii.$(OBJEXT): {$(VPATH)}regenc.h
enc/utf_8.$(OBJEXT): {$(VPATH)}config.h
enc/utf_8.$(OBJEXT): {$(VPATH)}defines.h
enc/utf_8.$(OBJEXT): {$(VPATH)}enc/utf_8.c
enc/utf_8.$(OBJEXT): {$(VPATH)}encindex.h
enc/utf_8.$(OBJEXT): {$(VPATH)}missing.h
enc/utf_8.$(OBJEXT): {$(VPATH)}oniguruma.h
enc/utf_8.$(OBJEXT): {$(VPATH)}regenc.h
encoding.$(OBJEXT): $(hdrdir)/ruby.h
encoding.$(OBJEXT): $(hdrdir)/ruby/ruby.h
encoding.$(OBJEXT): {$(VPATH)}assert.h
encoding.$(OBJEXT): {$(VPATH)}config.h
encoding.$(OBJEXT): {$(VPATH)}defines.h
encoding.$(OBJEXT): {$(VPATH)}encindex.h
encoding.$(OBJEXT): {$(VPATH)}encoding.c
encoding.$(OBJEXT): {$(VPATH)}encoding.h
encoding.$(OBJEXT): {$(VPATH)}intern.h
encoding.$(OBJEXT): {$(VPATH)}internal.h
encoding.$(OBJEXT): {$(VPATH)}io.h
encoding.$(OBJEXT): {$(VPATH)}missing.h
encoding.$(OBJEXT): {$(VPATH)}onigmo.h
encoding.$(OBJEXT): {$(VPATH)}oniguruma.h
encoding.$(OBJEXT): {$(VPATH)}regenc.h
encoding.$(OBJEXT): {$(VPATH)}ruby_assert.h
encoding.$(OBJEXT): {$(VPATH)}st.h
encoding.$(OBJEXT): {$(VPATH)}subst.h
encoding.$(OBJEXT): {$(VPATH)}util.h
enum.$(OBJEXT): $(hdrdir)/ruby.h
enum.$(OBJEXT): $(hdrdir)/ruby/ruby.h
enum.$(OBJEXT): {$(VPATH)}assert.h
enum.$(OBJEXT): {$(VPATH)}config.h
enum.$(OBJEXT): {$(VPATH)}defines.h
enum.$(OBJEXT): {$(VPATH)}encoding.h
enum.$(OBJEXT): {$(VPATH)}enum.c
enum.$(OBJEXT): {$(VPATH)}id.h
enum.$(OBJEXT): {$(VPATH)}intern.h
enum.$(OBJEXT): {$(VPATH)}internal.h
enum.$(OBJEXT): {$(VPATH)}io.h
enum.$(OBJEXT): {$(VPATH)}missing.h
enum.$(OBJEXT): {$(VPATH)}onigmo.h
enum.$(OBJEXT): {$(VPATH)}oniguruma.h
enum.$(OBJEXT): {$(VPATH)}st.h
enum.$(OBJEXT): {$(VPATH)}subst.h
enum.$(OBJEXT): {$(VPATH)}symbol.h
enum.$(OBJEXT): {$(VPATH)}transient_heap.h
enum.$(OBJEXT): {$(VPATH)}util.h
enumerator.$(OBJEXT): $(hdrdir)/ruby.h
enumerator.$(OBJEXT): $(hdrdir)/ruby/ruby.h
enumerator.$(OBJEXT): {$(VPATH)}assert.h
enumerator.$(OBJEXT): {$(VPATH)}config.h
enumerator.$(OBJEXT): {$(VPATH)}defines.h
enumerator.$(OBJEXT): {$(VPATH)}encoding.h
enumerator.$(OBJEXT): {$(VPATH)}enumerator.c
enumerator.$(OBJEXT): {$(VPATH)}id.h
enumerator.$(OBJEXT): {$(VPATH)}intern.h
enumerator.$(OBJEXT): {$(VPATH)}internal.h
enumerator.$(OBJEXT): {$(VPATH)}io.h
enumerator.$(OBJEXT): {$(VPATH)}missing.h
enumerator.$(OBJEXT): {$(VPATH)}onigmo.h
enumerator.$(OBJEXT): {$(VPATH)}oniguruma.h
enumerator.$(OBJEXT): {$(VPATH)}st.h
enumerator.$(OBJEXT): {$(VPATH)}subst.h
error.$(OBJEXT): $(CCAN_DIR)/check_type/check_type.h
error.$(OBJEXT): $(CCAN_DIR)/container_of/container_of.h
error.$(OBJEXT): $(CCAN_DIR)/list/list.h
error.$(OBJEXT): $(CCAN_DIR)/str/str.h
error.$(OBJEXT): $(hdrdir)/ruby.h
error.$(OBJEXT): $(hdrdir)/ruby/ruby.h
error.$(OBJEXT): {$(VPATH)}assert.h
error.$(OBJEXT): {$(VPATH)}config.h
error.$(OBJEXT): {$(VPATH)}defines.h
error.$(OBJEXT): {$(VPATH)}encoding.h
error.$(OBJEXT): {$(VPATH)}error.c
error.$(OBJEXT): {$(VPATH)}id.h
error.$(OBJEXT): {$(VPATH)}intern.h
error.$(OBJEXT): {$(VPATH)}internal.h
error.$(OBJEXT): {$(VPATH)}io.h
error.$(OBJEXT): {$(VPATH)}known_errors.inc
error.$(OBJEXT): {$(VPATH)}method.h
error.$(OBJEXT): {$(VPATH)}missing.h
error.$(OBJEXT): {$(VPATH)}node.h
error.$(OBJEXT): {$(VPATH)}onigmo.h
error.$(OBJEXT): {$(VPATH)}oniguruma.h
error.$(OBJEXT): {$(VPATH)}ruby_assert.h
error.$(OBJEXT): {$(VPATH)}ruby_atomic.h
error.$(OBJEXT): {$(VPATH)}st.h
error.$(OBJEXT): {$(VPATH)}subst.h
error.$(OBJEXT): {$(VPATH)}thread_$(THREAD_MODEL).h
error.$(OBJEXT): {$(VPATH)}thread_native.h
error.$(OBJEXT): {$(VPATH)}vm_core.h
error.$(OBJEXT): {$(VPATH)}vm_debug.h
error.$(OBJEXT): {$(VPATH)}vm_opts.h
eval.$(OBJEXT): $(CCAN_DIR)/check_type/check_type.h
eval.$(OBJEXT): $(CCAN_DIR)/container_of/container_of.h
eval.$(OBJEXT): $(CCAN_DIR)/list/list.h
eval.$(OBJEXT): $(CCAN_DIR)/str/str.h
eval.$(OBJEXT): $(hdrdir)/ruby.h
eval.$(OBJEXT): $(hdrdir)/ruby/ruby.h
eval.$(OBJEXT): {$(VPATH)}assert.h
eval.$(OBJEXT): {$(VPATH)}config.h
eval.$(OBJEXT): {$(VPATH)}debug_counter.h
eval.$(OBJEXT): {$(VPATH)}defines.h
eval.$(OBJEXT): {$(VPATH)}encoding.h
eval.$(OBJEXT): {$(VPATH)}eval.c
eval.$(OBJEXT): {$(VPATH)}eval_error.c
eval.$(OBJEXT): {$(VPATH)}eval_intern.h
eval.$(OBJEXT): {$(VPATH)}eval_jump.c
eval.$(OBJEXT): {$(VPATH)}gc.h
eval.$(OBJEXT): {$(VPATH)}id.h
eval.$(OBJEXT): {$(VPATH)}intern.h
eval.$(OBJEXT): {$(VPATH)}internal.h
eval.$(OBJEXT): {$(VPATH)}io.h
eval.$(OBJEXT): {$(VPATH)}iseq.h
eval.$(OBJEXT): {$(VPATH)}method.h
eval.$(OBJEXT): {$(VPATH)}missing.h
eval.$(OBJEXT): {$(VPATH)}mjit.h
eval.$(OBJEXT): {$(VPATH)}node.h
eval.$(OBJEXT): {$(VPATH)}onigmo.h
eval.$(OBJEXT): {$(VPATH)}oniguruma.h
eval.$(OBJEXT): {$(VPATH)}probes.dmyh
eval.$(OBJEXT): {$(VPATH)}probes.h
eval.$(OBJEXT): {$(VPATH)}probes_helper.h
eval.$(OBJEXT): {$(VPATH)}ruby_assert.h
eval.$(OBJEXT): {$(VPATH)}ruby_atomic.h
eval.$(OBJEXT): {$(VPATH)}st.h
eval.$(OBJEXT): {$(VPATH)}subst.h
eval.$(OBJEXT): {$(VPATH)}thread_$(THREAD_MODEL).h
eval.$(OBJEXT): {$(VPATH)}thread_native.h
eval.$(OBJEXT): {$(VPATH)}vm.h
eval.$(OBJEXT): {$(VPATH)}vm_core.h
eval.$(OBJEXT): {$(VPATH)}vm_debug.h
eval.$(OBJEXT): {$(VPATH)}vm_opts.h
explicit_bzero.$(OBJEXT): {$(VPATH)}config.h
explicit_bzero.$(OBJEXT): {$(VPATH)}explicit_bzero.c
explicit_bzero.$(OBJEXT): {$(VPATH)}missing.h
file.$(OBJEXT): $(hdrdir)/ruby.h
file.$(OBJEXT): $(hdrdir)/ruby/ruby.h
file.$(OBJEXT): {$(VPATH)}assert.h
file.$(OBJEXT): {$(VPATH)}config.h
file.$(OBJEXT): {$(VPATH)}defines.h
file.$(OBJEXT): {$(VPATH)}dln.h
file.$(OBJEXT): {$(VPATH)}encindex.h
file.$(OBJEXT): {$(VPATH)}encoding.h
file.$(OBJEXT): {$(VPATH)}file.c
file.$(OBJEXT): {$(VPATH)}id.h
file.$(OBJEXT): {$(VPATH)}intern.h
file.$(OBJEXT): {$(VPATH)}internal.h
file.$(OBJEXT): {$(VPATH)}io.h
file.$(OBJEXT): {$(VPATH)}missing.h
file.$(OBJEXT): {$(VPATH)}onigmo.h
file.$(OBJEXT): {$(VPATH)}oniguruma.h
file.$(OBJEXT): {$(VPATH)}st.h
file.$(OBJEXT): {$(VPATH)}subst.h
file.$(OBJEXT): {$(VPATH)}thread.h
file.$(OBJEXT): {$(VPATH)}util.h
gc.$(OBJEXT): $(CCAN_DIR)/check_type/check_type.h
gc.$(OBJEXT): $(CCAN_DIR)/container_of/container_of.h
gc.$(OBJEXT): $(CCAN_DIR)/list/list.h
gc.$(OBJEXT): $(CCAN_DIR)/str/str.h
gc.$(OBJEXT): $(hdrdir)/ruby.h
gc.$(OBJEXT): $(hdrdir)/ruby/ruby.h
gc.$(OBJEXT): {$(VPATH)}assert.h
gc.$(OBJEXT): {$(VPATH)}config.h
gc.$(OBJEXT): {$(VPATH)}constant.h
gc.$(OBJEXT): {$(VPATH)}debug.h
gc.$(OBJEXT): {$(VPATH)}debug_counter.h
gc.$(OBJEXT): {$(VPATH)}defines.h
gc.$(OBJEXT): {$(VPATH)}encoding.h
gc.$(OBJEXT): {$(VPATH)}eval_intern.h
gc.$(OBJEXT): {$(VPATH)}gc.c
gc.$(OBJEXT): {$(VPATH)}gc.h
gc.$(OBJEXT): {$(VPATH)}id.h
gc.$(OBJEXT): {$(VPATH)}id_table.h
gc.$(OBJEXT): {$(VPATH)}intern.h
gc.$(OBJEXT): {$(VPATH)}internal.h
gc.$(OBJEXT): {$(VPATH)}io.h
gc.$(OBJEXT): {$(VPATH)}method.h
gc.$(OBJEXT): {$(VPATH)}missing.h
gc.$(OBJEXT): {$(VPATH)}mjit.h
gc.$(OBJEXT): {$(VPATH)}node.h
gc.$(OBJEXT): {$(VPATH)}onigmo.h
gc.$(OBJEXT): {$(VPATH)}oniguruma.h
gc.$(OBJEXT): {$(VPATH)}probes.dmyh
gc.$(OBJEXT): {$(VPATH)}probes.h
gc.$(OBJEXT): {$(VPATH)}re.h
gc.$(OBJEXT): {$(VPATH)}regenc.h
gc.$(OBJEXT): {$(VPATH)}regex.h
gc.$(OBJEXT): {$(VPATH)}regint.h
gc.$(OBJEXT): {$(VPATH)}ruby_assert.h
gc.$(OBJEXT): {$(VPATH)}ruby_atomic.h
gc.$(OBJEXT): {$(VPATH)}st.h
gc.$(OBJEXT): {$(VPATH)}subst.h
gc.$(OBJEXT): {$(VPATH)}symbol.h
gc.$(OBJEXT): {$(VPATH)}thread.h
gc.$(OBJEXT): {$(VPATH)}thread_$(THREAD_MODEL).h
gc.$(OBJEXT): {$(VPATH)}thread_native.h
gc.$(OBJEXT): {$(VPATH)}transient_heap.h
gc.$(OBJEXT): {$(VPATH)}util.h
gc.$(OBJEXT): {$(VPATH)}vm_core.h
gc.$(OBJEXT): {$(VPATH)}vm_debug.h
gc.$(OBJEXT): {$(VPATH)}vm_opts.h
golf_prelude.$(OBJEXT): $(CCAN_DIR)/check_type/check_type.h
golf_prelude.$(OBJEXT): $(CCAN_DIR)/container_of/container_of.h
golf_prelude.$(OBJEXT): $(CCAN_DIR)/list/list.h
golf_prelude.$(OBJEXT): $(CCAN_DIR)/str/str.h
golf_prelude.$(OBJEXT): $(hdrdir)/ruby.h
golf_prelude.$(OBJEXT): $(hdrdir)/ruby/ruby.h
golf_prelude.$(OBJEXT): {$(VPATH)}assert.h
golf_prelude.$(OBJEXT): {$(VPATH)}config.h
golf_prelude.$(OBJEXT): {$(VPATH)}defines.h
golf_prelude.$(OBJEXT): {$(VPATH)}encoding.h
golf_prelude.$(OBJEXT): {$(VPATH)}golf_prelude.c
golf_prelude.$(OBJEXT): {$(VPATH)}golf_prelude.rb
golf_prelude.$(OBJEXT): {$(VPATH)}id.h
golf_prelude.$(OBJEXT): {$(VPATH)}intern.h
golf_prelude.$(OBJEXT): {$(VPATH)}internal.h
golf_prelude.$(OBJEXT): {$(VPATH)}io.h
golf_prelude.$(OBJEXT): {$(VPATH)}iseq.h
golf_prelude.$(OBJEXT): {$(VPATH)}method.h
golf_prelude.$(OBJEXT): {$(VPATH)}missing.h
golf_prelude.$(OBJEXT): {$(VPATH)}node.h
golf_prelude.$(OBJEXT): {$(VPATH)}onigmo.h
golf_prelude.$(OBJEXT): {$(VPATH)}oniguruma.h
golf_prelude.$(OBJEXT): {$(VPATH)}ruby_assert.h
golf_prelude.$(OBJEXT): {$(VPATH)}ruby_atomic.h
golf_prelude.$(OBJEXT): {$(VPATH)}st.h
golf_prelude.$(OBJEXT): {$(VPATH)}subst.h
golf_prelude.$(OBJEXT): {$(VPATH)}thread_$(THREAD_MODEL).h
golf_prelude.$(OBJEXT): {$(VPATH)}thread_native.h
golf_prelude.$(OBJEXT): {$(VPATH)}vm_core.h
golf_prelude.$(OBJEXT): {$(VPATH)}vm_debug.h
golf_prelude.$(OBJEXT): {$(VPATH)}vm_opts.h
goruby.$(OBJEXT): $(hdrdir)/ruby.h
goruby.$(OBJEXT): $(hdrdir)/ruby/ruby.h
goruby.$(OBJEXT): {$(VPATH)}assert.h
goruby.$(OBJEXT): {$(VPATH)}backward.h
goruby.$(OBJEXT): {$(VPATH)}config.h
goruby.$(OBJEXT): {$(VPATH)}defines.h
goruby.$(OBJEXT): {$(VPATH)}goruby.c
goruby.$(OBJEXT): {$(VPATH)}intern.h
goruby.$(OBJEXT): {$(VPATH)}main.c
goruby.$(OBJEXT): {$(VPATH)}missing.h
goruby.$(OBJEXT): {$(VPATH)}node.h
goruby.$(OBJEXT): {$(VPATH)}st.h
goruby.$(OBJEXT): {$(VPATH)}subst.h
goruby.$(OBJEXT): {$(VPATH)}vm_debug.h
hash.$(OBJEXT): $(hdrdir)/ruby.h
hash.$(OBJEXT): $(hdrdir)/ruby/ruby.h
hash.$(OBJEXT): {$(VPATH)}assert.h
hash.$(OBJEXT): {$(VPATH)}config.h
hash.$(OBJEXT): {$(VPATH)}debug_counter.h
hash.$(OBJEXT): {$(VPATH)}defines.h
hash.$(OBJEXT): {$(VPATH)}encoding.h
hash.$(OBJEXT): {$(VPATH)}gc.h
hash.$(OBJEXT): {$(VPATH)}hash.c
hash.$(OBJEXT): {$(VPATH)}id.h
hash.$(OBJEXT): {$(VPATH)}intern.h
hash.$(OBJEXT): {$(VPATH)}internal.h
hash.$(OBJEXT): {$(VPATH)}io.h
hash.$(OBJEXT): {$(VPATH)}missing.h
hash.$(OBJEXT): {$(VPATH)}onigmo.h
hash.$(OBJEXT): {$(VPATH)}oniguruma.h
hash.$(OBJEXT): {$(VPATH)}probes.dmyh
hash.$(OBJEXT): {$(VPATH)}probes.h
hash.$(OBJEXT): {$(VPATH)}ruby_assert.h
hash.$(OBJEXT): {$(VPATH)}st.h
hash.$(OBJEXT): {$(VPATH)}subst.h
hash.$(OBJEXT): {$(VPATH)}symbol.h
hash.$(OBJEXT): {$(VPATH)}transient_heap.h
hash.$(OBJEXT): {$(VPATH)}util.h
inits.$(OBJEXT): $(hdrdir)/ruby.h
inits.$(OBJEXT): $(hdrdir)/ruby/ruby.h
inits.$(OBJEXT): {$(VPATH)}assert.h
inits.$(OBJEXT): {$(VPATH)}config.h
inits.$(OBJEXT): {$(VPATH)}defines.h
inits.$(OBJEXT): {$(VPATH)}encoding.h
inits.$(OBJEXT): {$(VPATH)}inits.c
inits.$(OBJEXT): {$(VPATH)}intern.h
inits.$(OBJEXT): {$(VPATH)}internal.h
inits.$(OBJEXT): {$(VPATH)}io.h
inits.$(OBJEXT): {$(VPATH)}missing.h
inits.$(OBJEXT): {$(VPATH)}onigmo.h
inits.$(OBJEXT): {$(VPATH)}oniguruma.h
inits.$(OBJEXT): {$(VPATH)}st.h
inits.$(OBJEXT): {$(VPATH)}subst.h
io.$(OBJEXT): $(CCAN_DIR)/check_type/check_type.h
io.$(OBJEXT): $(CCAN_DIR)/container_of/container_of.h
io.$(OBJEXT): $(CCAN_DIR)/list/list.h
io.$(OBJEXT): $(CCAN_DIR)/str/str.h
io.$(OBJEXT): $(hdrdir)/ruby.h
io.$(OBJEXT): $(hdrdir)/ruby/ruby.h
io.$(OBJEXT): {$(VPATH)}assert.h
io.$(OBJEXT): {$(VPATH)}config.h
io.$(OBJEXT): {$(VPATH)}defines.h
io.$(OBJEXT): {$(VPATH)}dln.h
io.$(OBJEXT): {$(VPATH)}encindex.h
io.$(OBJEXT): {$(VPATH)}encoding.h
io.$(OBJEXT): {$(VPATH)}id.h
io.$(OBJEXT): {$(VPATH)}intern.h
io.$(OBJEXT): {$(VPATH)}internal.h
io.$(OBJEXT): {$(VPATH)}io.c
io.$(OBJEXT): {$(VPATH)}io.h
io.$(OBJEXT): {$(VPATH)}method.h
io.$(OBJEXT): {$(VPATH)}missing.h
io.$(OBJEXT): {$(VPATH)}node.h
io.$(OBJEXT): {$(VPATH)}onigmo.h
io.$(OBJEXT): {$(VPATH)}oniguruma.h
io.$(OBJEXT): {$(VPATH)}ruby_assert.h
io.$(OBJEXT): {$(VPATH)}ruby_atomic.h
io.$(OBJEXT): {$(VPATH)}st.h
io.$(OBJEXT): {$(VPATH)}subst.h
io.$(OBJEXT): {$(VPATH)}thread.h
io.$(OBJEXT): {$(VPATH)}thread_$(THREAD_MODEL).h
io.$(OBJEXT): {$(VPATH)}thread_native.h
io.$(OBJEXT): {$(VPATH)}util.h
io.$(OBJEXT): {$(VPATH)}vm_core.h
io.$(OBJEXT): {$(VPATH)}vm_opts.h
iseq.$(OBJEXT): $(CCAN_DIR)/check_type/check_type.h
iseq.$(OBJEXT): $(CCAN_DIR)/container_of/container_of.h
iseq.$(OBJEXT): $(CCAN_DIR)/list/list.h
iseq.$(OBJEXT): $(CCAN_DIR)/str/str.h
iseq.$(OBJEXT): $(hdrdir)/ruby.h
iseq.$(OBJEXT): $(hdrdir)/ruby/ruby.h
iseq.$(OBJEXT): {$(VPATH)}assert.h
iseq.$(OBJEXT): {$(VPATH)}config.h
iseq.$(OBJEXT): {$(VPATH)}debug_counter.h
iseq.$(OBJEXT): {$(VPATH)}defines.h
iseq.$(OBJEXT): {$(VPATH)}encoding.h
iseq.$(OBJEXT): {$(VPATH)}eval_intern.h
iseq.$(OBJEXT): {$(VPATH)}gc.h
iseq.$(OBJEXT): {$(VPATH)}id.h
iseq.$(OBJEXT): {$(VPATH)}id_table.h
iseq.$(OBJEXT): {$(VPATH)}insns.def
iseq.$(OBJEXT): {$(VPATH)}insns.inc
iseq.$(OBJEXT): {$(VPATH)}insns_info.inc
iseq.$(OBJEXT): {$(VPATH)}intern.h
iseq.$(OBJEXT): {$(VPATH)}internal.h
iseq.$(OBJEXT): {$(VPATH)}io.h
iseq.$(OBJEXT): {$(VPATH)}iseq.c
iseq.$(OBJEXT): {$(VPATH)}iseq.h
iseq.$(OBJEXT): {$(VPATH)}method.h
iseq.$(OBJEXT): {$(VPATH)}missing.h
iseq.$(OBJEXT): {$(VPATH)}mjit.h
iseq.$(OBJEXT): {$(VPATH)}node.h
iseq.$(OBJEXT): {$(VPATH)}node_name.inc
iseq.$(OBJEXT): {$(VPATH)}onigmo.h
iseq.$(OBJEXT): {$(VPATH)}oniguruma.h
iseq.$(OBJEXT): {$(VPATH)}ruby_assert.h
iseq.$(OBJEXT): {$(VPATH)}ruby_atomic.h
iseq.$(OBJEXT): {$(VPATH)}st.h
iseq.$(OBJEXT): {$(VPATH)}subst.h
iseq.$(OBJEXT): {$(VPATH)}thread_$(THREAD_MODEL).h
iseq.$(OBJEXT): {$(VPATH)}thread_native.h
iseq.$(OBJEXT): {$(VPATH)}util.h
iseq.$(OBJEXT): {$(VPATH)}vm_core.h
iseq.$(OBJEXT): {$(VPATH)}vm_debug.h
iseq.$(OBJEXT): {$(VPATH)}vm_opts.h
load.$(OBJEXT): $(CCAN_DIR)/check_type/check_type.h
load.$(OBJEXT): $(CCAN_DIR)/container_of/container_of.h
load.$(OBJEXT): $(CCAN_DIR)/list/list.h
load.$(OBJEXT): $(CCAN_DIR)/str/str.h
load.$(OBJEXT): $(hdrdir)/ruby.h
load.$(OBJEXT): $(hdrdir)/ruby/ruby.h
load.$(OBJEXT): {$(VPATH)}assert.h
load.$(OBJEXT): {$(VPATH)}config.h
load.$(OBJEXT): {$(VPATH)}defines.h
load.$(OBJEXT): {$(VPATH)}dln.h
load.$(OBJEXT): {$(VPATH)}encoding.h
load.$(OBJEXT): {$(VPATH)}eval_intern.h
load.$(OBJEXT): {$(VPATH)}id.h
load.$(OBJEXT): {$(VPATH)}intern.h
load.$(OBJEXT): {$(VPATH)}internal.h
load.$(OBJEXT): {$(VPATH)}io.h
load.$(OBJEXT): {$(VPATH)}iseq.h
load.$(OBJEXT): {$(VPATH)}load.c
load.$(OBJEXT): {$(VPATH)}method.h
load.$(OBJEXT): {$(VPATH)}missing.h
load.$(OBJEXT): {$(VPATH)}node.h
load.$(OBJEXT): {$(VPATH)}onigmo.h
load.$(OBJEXT): {$(VPATH)}oniguruma.h
load.$(OBJEXT): {$(VPATH)}probes.dmyh
load.$(OBJEXT): {$(VPATH)}probes.h
load.$(OBJEXT): {$(VPATH)}ruby_assert.h
load.$(OBJEXT): {$(VPATH)}ruby_atomic.h
load.$(OBJEXT): {$(VPATH)}st.h
load.$(OBJEXT): {$(VPATH)}subst.h
load.$(OBJEXT): {$(VPATH)}thread_$(THREAD_MODEL).h
load.$(OBJEXT): {$(VPATH)}thread_native.h
load.$(OBJEXT): {$(VPATH)}util.h
load.$(OBJEXT): {$(VPATH)}vm_core.h
load.$(OBJEXT): {$(VPATH)}vm_debug.h
load.$(OBJEXT): {$(VPATH)}vm_opts.h
loadpath.$(OBJEXT): $(hdrdir)/ruby/ruby.h
loadpath.$(OBJEXT): $(hdrdir)/ruby/version.h
loadpath.$(OBJEXT): $(top_srcdir)/version.h
loadpath.$(OBJEXT): {$(VPATH)}assert.h
loadpath.$(OBJEXT): {$(VPATH)}config.h
loadpath.$(OBJEXT): {$(VPATH)}defines.h
loadpath.$(OBJEXT): {$(VPATH)}intern.h
loadpath.$(OBJEXT): {$(VPATH)}loadpath.c
loadpath.$(OBJEXT): {$(VPATH)}missing.h
loadpath.$(OBJEXT): {$(VPATH)}st.h
loadpath.$(OBJEXT): {$(VPATH)}subst.h
loadpath.$(OBJEXT): {$(VPATH)}verconf.h
localeinit.$(OBJEXT): $(hdrdir)/ruby.h
localeinit.$(OBJEXT): $(hdrdir)/ruby/ruby.h
localeinit.$(OBJEXT): {$(VPATH)}assert.h
localeinit.$(OBJEXT): {$(VPATH)}config.h
localeinit.$(OBJEXT): {$(VPATH)}defines.h
localeinit.$(OBJEXT): {$(VPATH)}encindex.h
localeinit.$(OBJEXT): {$(VPATH)}encoding.h
localeinit.$(OBJEXT): {$(VPATH)}intern.h
localeinit.$(OBJEXT): {$(VPATH)}internal.h
localeinit.$(OBJEXT): {$(VPATH)}io.h
localeinit.$(OBJEXT): {$(VPATH)}localeinit.c
localeinit.$(OBJEXT): {$(VPATH)}missing.h
localeinit.$(OBJEXT): {$(VPATH)}onigmo.h
localeinit.$(OBJEXT): {$(VPATH)}oniguruma.h
localeinit.$(OBJEXT): {$(VPATH)}st.h
localeinit.$(OBJEXT): {$(VPATH)}subst.h
main.$(OBJEXT): $(hdrdir)/ruby.h
main.$(OBJEXT): $(hdrdir)/ruby/ruby.h
main.$(OBJEXT): {$(VPATH)}assert.h
main.$(OBJEXT): {$(VPATH)}backward.h
main.$(OBJEXT): {$(VPATH)}config.h
main.$(OBJEXT): {$(VPATH)}defines.h
main.$(OBJEXT): {$(VPATH)}intern.h
main.$(OBJEXT): {$(VPATH)}main.c
main.$(OBJEXT): {$(VPATH)}missing.h
main.$(OBJEXT): {$(VPATH)}node.h
main.$(OBJEXT): {$(VPATH)}st.h
main.$(OBJEXT): {$(VPATH)}subst.h
main.$(OBJEXT): {$(VPATH)}vm_debug.h
marshal.$(OBJEXT): $(hdrdir)/ruby.h
marshal.$(OBJEXT): $(hdrdir)/ruby/ruby.h
marshal.$(OBJEXT): {$(VPATH)}assert.h
marshal.$(OBJEXT): {$(VPATH)}config.h
marshal.$(OBJEXT): {$(VPATH)}defines.h
marshal.$(OBJEXT): {$(VPATH)}encindex.h
marshal.$(OBJEXT): {$(VPATH)}encoding.h
marshal.$(OBJEXT): {$(VPATH)}id_table.h
marshal.$(OBJEXT): {$(VPATH)}intern.h
marshal.$(OBJEXT): {$(VPATH)}internal.h
marshal.$(OBJEXT): {$(VPATH)}io.h
marshal.$(OBJEXT): {$(VPATH)}marshal.c
marshal.$(OBJEXT): {$(VPATH)}missing.h
marshal.$(OBJEXT): {$(VPATH)}onigmo.h
marshal.$(OBJEXT): {$(VPATH)}oniguruma.h
marshal.$(OBJEXT): {$(VPATH)}st.h
marshal.$(OBJEXT): {$(VPATH)}subst.h
marshal.$(OBJEXT): {$(VPATH)}util.h
math.$(OBJEXT): $(hdrdir)/ruby.h
math.$(OBJEXT): $(hdrdir)/ruby/ruby.h
math.$(OBJEXT): {$(VPATH)}assert.h
math.$(OBJEXT): {$(VPATH)}config.h
math.$(OBJEXT): {$(VPATH)}defines.h
math.$(OBJEXT): {$(VPATH)}encoding.h
math.$(OBJEXT): {$(VPATH)}intern.h
math.$(OBJEXT): {$(VPATH)}internal.h
math.$(OBJEXT): {$(VPATH)}io.h
math.$(OBJEXT): {$(VPATH)}math.c
math.$(OBJEXT): {$(VPATH)}missing.h
math.$(OBJEXT): {$(VPATH)}onigmo.h
math.$(OBJEXT): {$(VPATH)}oniguruma.h
math.$(OBJEXT): {$(VPATH)}st.h
math.$(OBJEXT): {$(VPATH)}subst.h
miniinit.$(OBJEXT): $(hdrdir)/ruby/ruby.h
miniinit.$(OBJEXT): {$(VPATH)}assert.h
miniinit.$(OBJEXT): {$(VPATH)}config.h
miniinit.$(OBJEXT): {$(VPATH)}defines.h
miniinit.$(OBJEXT): {$(VPATH)}encoding.h
miniinit.$(OBJEXT): {$(VPATH)}intern.h
miniinit.$(OBJEXT): {$(VPATH)}miniinit.c
miniinit.$(OBJEXT): {$(VPATH)}missing.h
miniinit.$(OBJEXT): {$(VPATH)}onigmo.h
miniinit.$(OBJEXT): {$(VPATH)}oniguruma.h
miniinit.$(OBJEXT): {$(VPATH)}st.h
miniinit.$(OBJEXT): {$(VPATH)}subst.h
miniprelude.$(OBJEXT): {$(VPATH)}iseq.h
miniprelude.$(OBJEXT): {$(VPATH)}miniprelude.c
mjit.$(OBJEXT): $(CCAN_DIR)/check_type/check_type.h
mjit.$(OBJEXT): $(CCAN_DIR)/container_of/container_of.h
mjit.$(OBJEXT): $(CCAN_DIR)/list/list.h
mjit.$(OBJEXT): $(CCAN_DIR)/str/str.h
mjit.$(OBJEXT): $(hdrdir)/ruby.h
mjit.$(OBJEXT): $(hdrdir)/ruby/ruby.h
mjit.$(OBJEXT): {$(VPATH)}assert.h
mjit.$(OBJEXT): {$(VPATH)}config.h
mjit.$(OBJEXT): {$(VPATH)}constant.h
mjit.$(OBJEXT): {$(VPATH)}debug.h
mjit.$(OBJEXT): {$(VPATH)}debug_counter.h
mjit.$(OBJEXT): {$(VPATH)}defines.h
mjit.$(OBJEXT): {$(VPATH)}dln.h
mjit.$(OBJEXT): {$(VPATH)}gc.h
mjit.$(OBJEXT): {$(VPATH)}id.h
mjit.$(OBJEXT): {$(VPATH)}id_table.h
mjit.$(OBJEXT): {$(VPATH)}intern.h
mjit.$(OBJEXT): {$(VPATH)}internal.h
mjit.$(OBJEXT): {$(VPATH)}method.h
mjit.$(OBJEXT): {$(VPATH)}missing.h
mjit.$(OBJEXT): {$(VPATH)}mjit.c
mjit.$(OBJEXT): {$(VPATH)}mjit.h
mjit.$(OBJEXT): {$(VPATH)}mjit_config.h
mjit.$(OBJEXT): {$(VPATH)}mjit_worker.c
mjit.$(OBJEXT): {$(VPATH)}node.h
mjit.$(OBJEXT): {$(VPATH)}ruby_assert.h
mjit.$(OBJEXT): {$(VPATH)}ruby_atomic.h
mjit.$(OBJEXT): {$(VPATH)}st.h
mjit.$(OBJEXT): {$(VPATH)}subst.h
mjit.$(OBJEXT): {$(VPATH)}thread.h
mjit.$(OBJEXT): {$(VPATH)}thread_$(THREAD_MODEL).h
mjit.$(OBJEXT): {$(VPATH)}thread_native.h
mjit.$(OBJEXT): {$(VPATH)}util.h
mjit.$(OBJEXT): {$(VPATH)}vm_core.h
mjit.$(OBJEXT): {$(VPATH)}vm_opts.h
mjit_compile.$(OBJEXT): $(CCAN_DIR)/check_type/check_type.h
mjit_compile.$(OBJEXT): $(CCAN_DIR)/container_of/container_of.h
mjit_compile.$(OBJEXT): $(CCAN_DIR)/list/list.h
mjit_compile.$(OBJEXT): $(CCAN_DIR)/str/str.h
mjit_compile.$(OBJEXT): $(hdrdir)/ruby.h
mjit_compile.$(OBJEXT): $(hdrdir)/ruby/ruby.h
mjit_compile.$(OBJEXT): {$(VPATH)}assert.h
mjit_compile.$(OBJEXT): {$(VPATH)}config.h
mjit_compile.$(OBJEXT): {$(VPATH)}debug_counter.h
mjit_compile.$(OBJEXT): {$(VPATH)}defines.h
mjit_compile.$(OBJEXT): {$(VPATH)}id.h
mjit_compile.$(OBJEXT): {$(VPATH)}insns.def
mjit_compile.$(OBJEXT): {$(VPATH)}insns.inc
mjit_compile.$(OBJEXT): {$(VPATH)}insns_info.inc
mjit_compile.$(OBJEXT): {$(VPATH)}intern.h
mjit_compile.$(OBJEXT): {$(VPATH)}internal.h
mjit_compile.$(OBJEXT): {$(VPATH)}iseq.h
mjit_compile.$(OBJEXT): {$(VPATH)}method.h
mjit_compile.$(OBJEXT): {$(VPATH)}missing.h
mjit_compile.$(OBJEXT): {$(VPATH)}mjit.h
mjit_compile.$(OBJEXT): {$(VPATH)}mjit_compile.c
mjit_compile.$(OBJEXT): {$(VPATH)}mjit_compile.inc
mjit_compile.$(OBJEXT): {$(VPATH)}node.h
mjit_compile.$(OBJEXT): {$(VPATH)}ruby_assert.h
mjit_compile.$(OBJEXT): {$(VPATH)}ruby_atomic.h
mjit_compile.$(OBJEXT): {$(VPATH)}st.h
mjit_compile.$(OBJEXT): {$(VPATH)}subst.h
mjit_compile.$(OBJEXT): {$(VPATH)}thread_$(THREAD_MODEL).h
mjit_compile.$(OBJEXT): {$(VPATH)}thread_native.h
mjit_compile.$(OBJEXT): {$(VPATH)}vm_core.h
mjit_compile.$(OBJEXT): {$(VPATH)}vm_exec.h
mjit_compile.$(OBJEXT): {$(VPATH)}vm_insnhelper.h
mjit_compile.$(OBJEXT): {$(VPATH)}vm_opts.h
node.$(OBJEXT): $(CCAN_DIR)/check_type/check_type.h
node.$(OBJEXT): $(CCAN_DIR)/container_of/container_of.h
node.$(OBJEXT): $(CCAN_DIR)/list/list.h
node.$(OBJEXT): $(CCAN_DIR)/str/str.h
node.$(OBJEXT): $(hdrdir)/ruby.h
node.$(OBJEXT): $(hdrdir)/ruby/ruby.h
node.$(OBJEXT): {$(VPATH)}assert.h
node.$(OBJEXT): {$(VPATH)}config.h
node.$(OBJEXT): {$(VPATH)}defines.h
node.$(OBJEXT): {$(VPATH)}encoding.h
node.$(OBJEXT): {$(VPATH)}id.h
node.$(OBJEXT): {$(VPATH)}intern.h
node.$(OBJEXT): {$(VPATH)}internal.h
node.$(OBJEXT): {$(VPATH)}io.h
node.$(OBJEXT): {$(VPATH)}method.h
node.$(OBJEXT): {$(VPATH)}missing.h
node.$(OBJEXT): {$(VPATH)}node.c
node.$(OBJEXT): {$(VPATH)}node.h
node.$(OBJEXT): {$(VPATH)}onigmo.h
node.$(OBJEXT): {$(VPATH)}oniguruma.h
node.$(OBJEXT): {$(VPATH)}ruby_assert.h
node.$(OBJEXT): {$(VPATH)}ruby_atomic.h
node.$(OBJEXT): {$(VPATH)}st.h
node.$(OBJEXT): {$(VPATH)}subst.h
node.$(OBJEXT): {$(VPATH)}thread_$(THREAD_MODEL).h
node.$(OBJEXT): {$(VPATH)}thread_native.h
node.$(OBJEXT): {$(VPATH)}vm_core.h
node.$(OBJEXT): {$(VPATH)}vm_debug.h
node.$(OBJEXT): {$(VPATH)}vm_opts.h
numeric.$(OBJEXT): $(hdrdir)/ruby.h
numeric.$(OBJEXT): $(hdrdir)/ruby/ruby.h
numeric.$(OBJEXT): {$(VPATH)}assert.h
numeric.$(OBJEXT): {$(VPATH)}config.h
numeric.$(OBJEXT): {$(VPATH)}defines.h
numeric.$(OBJEXT): {$(VPATH)}encoding.h
numeric.$(OBJEXT): {$(VPATH)}id.h
numeric.$(OBJEXT): {$(VPATH)}intern.h
numeric.$(OBJEXT): {$(VPATH)}internal.h
numeric.$(OBJEXT): {$(VPATH)}io.h
numeric.$(OBJEXT): {$(VPATH)}missing.h
numeric.$(OBJEXT): {$(VPATH)}numeric.c
numeric.$(OBJEXT): {$(VPATH)}onigmo.h
numeric.$(OBJEXT): {$(VPATH)}oniguruma.h
numeric.$(OBJEXT): {$(VPATH)}st.h
numeric.$(OBJEXT): {$(VPATH)}subst.h
numeric.$(OBJEXT): {$(VPATH)}util.h
object.$(OBJEXT): $(hdrdir)/ruby.h
object.$(OBJEXT): $(hdrdir)/ruby/ruby.h
object.$(OBJEXT): {$(VPATH)}assert.h
object.$(OBJEXT): {$(VPATH)}config.h
object.$(OBJEXT): {$(VPATH)}constant.h
object.$(OBJEXT): {$(VPATH)}defines.h
object.$(OBJEXT): {$(VPATH)}encoding.h
object.$(OBJEXT): {$(VPATH)}id.h
object.$(OBJEXT): {$(VPATH)}intern.h
object.$(OBJEXT): {$(VPATH)}internal.h
object.$(OBJEXT): {$(VPATH)}io.h
object.$(OBJEXT): {$(VPATH)}missing.h
object.$(OBJEXT): {$(VPATH)}object.c
object.$(OBJEXT): {$(VPATH)}onigmo.h
object.$(OBJEXT): {$(VPATH)}oniguruma.h
object.$(OBJEXT): {$(VPATH)}probes.dmyh
object.$(OBJEXT): {$(VPATH)}probes.h
object.$(OBJEXT): {$(VPATH)}st.h
object.$(OBJEXT): {$(VPATH)}subst.h
object.$(OBJEXT): {$(VPATH)}util.h
pack.$(OBJEXT): $(hdrdir)/ruby.h
pack.$(OBJEXT): $(hdrdir)/ruby/ruby.h
pack.$(OBJEXT): {$(VPATH)}assert.h
pack.$(OBJEXT): {$(VPATH)}config.h
pack.$(OBJEXT): {$(VPATH)}defines.h
pack.$(OBJEXT): {$(VPATH)}encoding.h
pack.$(OBJEXT): {$(VPATH)}intern.h
pack.$(OBJEXT): {$(VPATH)}internal.h
pack.$(OBJEXT): {$(VPATH)}io.h
pack.$(OBJEXT): {$(VPATH)}missing.h
pack.$(OBJEXT): {$(VPATH)}onigmo.h
pack.$(OBJEXT): {$(VPATH)}oniguruma.h
pack.$(OBJEXT): {$(VPATH)}pack.c
pack.$(OBJEXT): {$(VPATH)}st.h
pack.$(OBJEXT): {$(VPATH)}subst.h
parse.$(OBJEXT): $(hdrdir)/ruby.h
parse.$(OBJEXT): $(hdrdir)/ruby/ruby.h
parse.$(OBJEXT): {$(VPATH)}assert.h
parse.$(OBJEXT): {$(VPATH)}config.h
parse.$(OBJEXT): {$(VPATH)}defines.h
parse.$(OBJEXT): {$(VPATH)}defs/keywords
parse.$(OBJEXT): {$(VPATH)}encoding.h
parse.$(OBJEXT): {$(VPATH)}id.h
parse.$(OBJEXT): {$(VPATH)}intern.h
parse.$(OBJEXT): {$(VPATH)}internal.h
parse.$(OBJEXT): {$(VPATH)}io.h
parse.$(OBJEXT): {$(VPATH)}lex.c
parse.$(OBJEXT): {$(VPATH)}missing.h
parse.$(OBJEXT): {$(VPATH)}node.h
parse.$(OBJEXT): {$(VPATH)}onigmo.h
parse.$(OBJEXT): {$(VPATH)}oniguruma.h
parse.$(OBJEXT): {$(VPATH)}parse.c
parse.$(OBJEXT): {$(VPATH)}parse.h
parse.$(OBJEXT): {$(VPATH)}parse.y
parse.$(OBJEXT): {$(VPATH)}probes.dmyh
parse.$(OBJEXT): {$(VPATH)}probes.h
parse.$(OBJEXT): {$(VPATH)}regenc.h
parse.$(OBJEXT): {$(VPATH)}regex.h
parse.$(OBJEXT): {$(VPATH)}st.h
parse.$(OBJEXT): {$(VPATH)}subst.h
parse.$(OBJEXT): {$(VPATH)}symbol.h
parse.$(OBJEXT): {$(VPATH)}util.h
prelude.$(OBJEXT): $(CCAN_DIR)/check_type/check_type.h
prelude.$(OBJEXT): $(CCAN_DIR)/container_of/container_of.h
prelude.$(OBJEXT): $(CCAN_DIR)/list/list.h
prelude.$(OBJEXT): $(CCAN_DIR)/str/str.h
prelude.$(OBJEXT): $(hdrdir)/ruby.h
prelude.$(OBJEXT): $(hdrdir)/ruby/ruby.h
prelude.$(OBJEXT): {$(VPATH)}assert.h
prelude.$(OBJEXT): {$(VPATH)}config.h
prelude.$(OBJEXT): {$(VPATH)}defines.h
prelude.$(OBJEXT): {$(VPATH)}encoding.h
prelude.$(OBJEXT): {$(VPATH)}gem_prelude.rb
prelude.$(OBJEXT): {$(VPATH)}id.h
prelude.$(OBJEXT): {$(VPATH)}intern.h
prelude.$(OBJEXT): {$(VPATH)}internal.h
prelude.$(OBJEXT): {$(VPATH)}io.h
prelude.$(OBJEXT): {$(VPATH)}iseq.h
prelude.$(OBJEXT): {$(VPATH)}method.h
prelude.$(OBJEXT): {$(VPATH)}missing.h
prelude.$(OBJEXT): {$(VPATH)}node.h
prelude.$(OBJEXT): {$(VPATH)}onigmo.h
prelude.$(OBJEXT): {$(VPATH)}oniguruma.h
prelude.$(OBJEXT): {$(VPATH)}prelude.c
prelude.$(OBJEXT): {$(VPATH)}prelude.rb
prelude.$(OBJEXT): {$(VPATH)}ruby_assert.h
prelude.$(OBJEXT): {$(VPATH)}ruby_atomic.h
prelude.$(OBJEXT): {$(VPATH)}st.h
prelude.$(OBJEXT): {$(VPATH)}subst.h
prelude.$(OBJEXT): {$(VPATH)}thread_$(THREAD_MODEL).h
prelude.$(OBJEXT): {$(VPATH)}thread_native.h
prelude.$(OBJEXT): {$(VPATH)}vm_core.h
prelude.$(OBJEXT): {$(VPATH)}vm_debug.h
prelude.$(OBJEXT): {$(VPATH)}vm_opts.h
proc.$(OBJEXT): $(CCAN_DIR)/check_type/check_type.h
proc.$(OBJEXT): $(CCAN_DIR)/container_of/container_of.h
proc.$(OBJEXT): $(CCAN_DIR)/list/list.h
proc.$(OBJEXT): $(CCAN_DIR)/str/str.h
proc.$(OBJEXT): $(hdrdir)/ruby.h
proc.$(OBJEXT): $(hdrdir)/ruby/ruby.h
proc.$(OBJEXT): {$(VPATH)}assert.h
proc.$(OBJEXT): {$(VPATH)}config.h
proc.$(OBJEXT): {$(VPATH)}defines.h
proc.$(OBJEXT): {$(VPATH)}encoding.h
proc.$(OBJEXT): {$(VPATH)}eval_intern.h
proc.$(OBJEXT): {$(VPATH)}gc.h
proc.$(OBJEXT): {$(VPATH)}id.h
proc.$(OBJEXT): {$(VPATH)}intern.h
proc.$(OBJEXT): {$(VPATH)}internal.h
proc.$(OBJEXT): {$(VPATH)}io.h
proc.$(OBJEXT): {$(VPATH)}iseq.h
proc.$(OBJEXT): {$(VPATH)}method.h
proc.$(OBJEXT): {$(VPATH)}missing.h
proc.$(OBJEXT): {$(VPATH)}node.h
proc.$(OBJEXT): {$(VPATH)}onigmo.h
proc.$(OBJEXT): {$(VPATH)}oniguruma.h
proc.$(OBJEXT): {$(VPATH)}proc.c
proc.$(OBJEXT): {$(VPATH)}ruby_assert.h
proc.$(OBJEXT): {$(VPATH)}ruby_atomic.h
proc.$(OBJEXT): {$(VPATH)}st.h
proc.$(OBJEXT): {$(VPATH)}subst.h
proc.$(OBJEXT): {$(VPATH)}thread_$(THREAD_MODEL).h
proc.$(OBJEXT): {$(VPATH)}thread_native.h
proc.$(OBJEXT): {$(VPATH)}vm_core.h
proc.$(OBJEXT): {$(VPATH)}vm_debug.h
proc.$(OBJEXT): {$(VPATH)}vm_opts.h
process.$(OBJEXT): $(CCAN_DIR)/check_type/check_type.h
process.$(OBJEXT): $(CCAN_DIR)/container_of/container_of.h
process.$(OBJEXT): $(CCAN_DIR)/list/list.h
process.$(OBJEXT): $(CCAN_DIR)/str/str.h
process.$(OBJEXT): $(hdrdir)/ruby.h
process.$(OBJEXT): $(hdrdir)/ruby/ruby.h
process.$(OBJEXT): {$(VPATH)}assert.h
process.$(OBJEXT): {$(VPATH)}config.h
process.$(OBJEXT): {$(VPATH)}defines.h
process.$(OBJEXT): {$(VPATH)}dln.h
process.$(OBJEXT): {$(VPATH)}encoding.h
process.$(OBJEXT): {$(VPATH)}hrtime.h
process.$(OBJEXT): {$(VPATH)}id.h
process.$(OBJEXT): {$(VPATH)}intern.h
process.$(OBJEXT): {$(VPATH)}internal.h
process.$(OBJEXT): {$(VPATH)}io.h
process.$(OBJEXT): {$(VPATH)}method.h
process.$(OBJEXT): {$(VPATH)}missing.h
process.$(OBJEXT): {$(VPATH)}node.h
process.$(OBJEXT): {$(VPATH)}onigmo.h
process.$(OBJEXT): {$(VPATH)}oniguruma.h
process.$(OBJEXT): {$(VPATH)}process.c
process.$(OBJEXT): {$(VPATH)}ruby_assert.h
process.$(OBJEXT): {$(VPATH)}ruby_atomic.h
process.$(OBJEXT): {$(VPATH)}st.h
process.$(OBJEXT): {$(VPATH)}subst.h
process.$(OBJEXT): {$(VPATH)}thread.h
process.$(OBJEXT): {$(VPATH)}thread_$(THREAD_MODEL).h
process.$(OBJEXT): {$(VPATH)}thread_native.h
process.$(OBJEXT): {$(VPATH)}util.h
process.$(OBJEXT): {$(VPATH)}vm_core.h
process.$(OBJEXT): {$(VPATH)}vm_debug.h
process.$(OBJEXT): {$(VPATH)}vm_opts.h
random.$(OBJEXT): $(hdrdir)/ruby.h
random.$(OBJEXT): $(hdrdir)/ruby/ruby.h
random.$(OBJEXT): {$(VPATH)}assert.h
random.$(OBJEXT): {$(VPATH)}config.h
random.$(OBJEXT): {$(VPATH)}defines.h
random.$(OBJEXT): {$(VPATH)}encoding.h
random.$(OBJEXT): {$(VPATH)}intern.h
random.$(OBJEXT): {$(VPATH)}internal.h
random.$(OBJEXT): {$(VPATH)}io.h
random.$(OBJEXT): {$(VPATH)}missing.h
random.$(OBJEXT): {$(VPATH)}mt19937.c
random.$(OBJEXT): {$(VPATH)}onigmo.h
random.$(OBJEXT): {$(VPATH)}oniguruma.h
random.$(OBJEXT): {$(VPATH)}random.c
random.$(OBJEXT): {$(VPATH)}ruby_atomic.h
random.$(OBJEXT): {$(VPATH)}siphash.c
random.$(OBJEXT): {$(VPATH)}siphash.h
random.$(OBJEXT): {$(VPATH)}st.h
random.$(OBJEXT): {$(VPATH)}subst.h
range.$(OBJEXT): $(hdrdir)/ruby.h
range.$(OBJEXT): $(hdrdir)/ruby/ruby.h
range.$(OBJEXT): {$(VPATH)}assert.h
range.$(OBJEXT): {$(VPATH)}config.h
range.$(OBJEXT): {$(VPATH)}defines.h
range.$(OBJEXT): {$(VPATH)}encoding.h
range.$(OBJEXT): {$(VPATH)}id.h
range.$(OBJEXT): {$(VPATH)}intern.h
range.$(OBJEXT): {$(VPATH)}internal.h
range.$(OBJEXT): {$(VPATH)}io.h
range.$(OBJEXT): {$(VPATH)}missing.h
range.$(OBJEXT): {$(VPATH)}onigmo.h
range.$(OBJEXT): {$(VPATH)}oniguruma.h
range.$(OBJEXT): {$(VPATH)}range.c
range.$(OBJEXT): {$(VPATH)}st.h
range.$(OBJEXT): {$(VPATH)}subst.h
rational.$(OBJEXT): $(hdrdir)/ruby.h
rational.$(OBJEXT): $(hdrdir)/ruby/ruby.h
rational.$(OBJEXT): {$(VPATH)}assert.h
rational.$(OBJEXT): {$(VPATH)}config.h
rational.$(OBJEXT): {$(VPATH)}defines.h
rational.$(OBJEXT): {$(VPATH)}encoding.h
rational.$(OBJEXT): {$(VPATH)}id.h
rational.$(OBJEXT): {$(VPATH)}intern.h
rational.$(OBJEXT): {$(VPATH)}internal.h
rational.$(OBJEXT): {$(VPATH)}io.h
rational.$(OBJEXT): {$(VPATH)}missing.h
rational.$(OBJEXT): {$(VPATH)}onigmo.h
rational.$(OBJEXT): {$(VPATH)}oniguruma.h
rational.$(OBJEXT): {$(VPATH)}rational.c
rational.$(OBJEXT): {$(VPATH)}ruby_assert.h
rational.$(OBJEXT): {$(VPATH)}st.h
rational.$(OBJEXT): {$(VPATH)}subst.h
re.$(OBJEXT): $(hdrdir)/ruby.h
re.$(OBJEXT): $(hdrdir)/ruby/ruby.h
re.$(OBJEXT): {$(VPATH)}assert.h
re.$(OBJEXT): {$(VPATH)}config.h
re.$(OBJEXT): {$(VPATH)}defines.h
re.$(OBJEXT): {$(VPATH)}encindex.h
re.$(OBJEXT): {$(VPATH)}encoding.h
re.$(OBJEXT): {$(VPATH)}intern.h
re.$(OBJEXT): {$(VPATH)}internal.h
re.$(OBJEXT): {$(VPATH)}io.h
re.$(OBJEXT): {$(VPATH)}missing.h
re.$(OBJEXT): {$(VPATH)}onigmo.h
re.$(OBJEXT): {$(VPATH)}oniguruma.h
re.$(OBJEXT): {$(VPATH)}re.c
re.$(OBJEXT): {$(VPATH)}re.h
re.$(OBJEXT): {$(VPATH)}regenc.h
re.$(OBJEXT): {$(VPATH)}regex.h
re.$(OBJEXT): {$(VPATH)}regint.h
re.$(OBJEXT): {$(VPATH)}st.h
re.$(OBJEXT): {$(VPATH)}subst.h
re.$(OBJEXT): {$(VPATH)}util.h
regcomp.$(OBJEXT): $(hdrdir)/ruby/ruby.h
regcomp.$(OBJEXT): {$(VPATH)}assert.h
regcomp.$(OBJEXT): {$(VPATH)}config.h
regcomp.$(OBJEXT): {$(VPATH)}defines.h
regcomp.$(OBJEXT): {$(VPATH)}intern.h
regcomp.$(OBJEXT): {$(VPATH)}missing.h
regcomp.$(OBJEXT): {$(VPATH)}onigmo.h
regcomp.$(OBJEXT): {$(VPATH)}oniguruma.h
regcomp.$(OBJEXT): {$(VPATH)}regcomp.c
regcomp.$(OBJEXT): {$(VPATH)}regenc.h
regcomp.$(OBJEXT): {$(VPATH)}regint.h
regcomp.$(OBJEXT): {$(VPATH)}regparse.h
regcomp.$(OBJEXT): {$(VPATH)}st.h
regcomp.$(OBJEXT): {$(VPATH)}subst.h
regenc.$(OBJEXT): $(hdrdir)/ruby/ruby.h
regenc.$(OBJEXT): {$(VPATH)}assert.h
regenc.$(OBJEXT): {$(VPATH)}config.h
regenc.$(OBJEXT): {$(VPATH)}defines.h
regenc.$(OBJEXT): {$(VPATH)}intern.h
regenc.$(OBJEXT): {$(VPATH)}missing.h
regenc.$(OBJEXT): {$(VPATH)}onigmo.h
regenc.$(OBJEXT): {$(VPATH)}oniguruma.h
regenc.$(OBJEXT): {$(VPATH)}regenc.c
regenc.$(OBJEXT): {$(VPATH)}regenc.h
regenc.$(OBJEXT): {$(VPATH)}regint.h
regenc.$(OBJEXT): {$(VPATH)}st.h
regenc.$(OBJEXT): {$(VPATH)}subst.h
regerror.$(OBJEXT): $(hdrdir)/ruby/ruby.h
regerror.$(OBJEXT): {$(VPATH)}assert.h
regerror.$(OBJEXT): {$(VPATH)}config.h
regerror.$(OBJEXT): {$(VPATH)}defines.h
regerror.$(OBJEXT): {$(VPATH)}intern.h
regerror.$(OBJEXT): {$(VPATH)}missing.h
regerror.$(OBJEXT): {$(VPATH)}onigmo.h
regerror.$(OBJEXT): {$(VPATH)}oniguruma.h
regerror.$(OBJEXT): {$(VPATH)}regenc.h
regerror.$(OBJEXT): {$(VPATH)}regerror.c
regerror.$(OBJEXT): {$(VPATH)}regint.h
regerror.$(OBJEXT): {$(VPATH)}st.h
regerror.$(OBJEXT): {$(VPATH)}subst.h
regexec.$(OBJEXT): $(hdrdir)/ruby/ruby.h
regexec.$(OBJEXT): {$(VPATH)}assert.h
regexec.$(OBJEXT): {$(VPATH)}config.h
regexec.$(OBJEXT): {$(VPATH)}defines.h
regexec.$(OBJEXT): {$(VPATH)}intern.h
regexec.$(OBJEXT): {$(VPATH)}missing.h
regexec.$(OBJEXT): {$(VPATH)}onigmo.h
regexec.$(OBJEXT): {$(VPATH)}oniguruma.h
regexec.$(OBJEXT): {$(VPATH)}regenc.h
regexec.$(OBJEXT): {$(VPATH)}regexec.c
regexec.$(OBJEXT): {$(VPATH)}regint.h
regexec.$(OBJEXT): {$(VPATH)}st.h
regexec.$(OBJEXT): {$(VPATH)}subst.h
regparse.$(OBJEXT): $(hdrdir)/ruby/ruby.h
regparse.$(OBJEXT): {$(VPATH)}assert.h
regparse.$(OBJEXT): {$(VPATH)}config.h
regparse.$(OBJEXT): {$(VPATH)}defines.h
regparse.$(OBJEXT): {$(VPATH)}intern.h
regparse.$(OBJEXT): {$(VPATH)}missing.h
regparse.$(OBJEXT): {$(VPATH)}onigmo.h
regparse.$(OBJEXT): {$(VPATH)}oniguruma.h
regparse.$(OBJEXT): {$(VPATH)}regenc.h
regparse.$(OBJEXT): {$(VPATH)}regint.h
regparse.$(OBJEXT): {$(VPATH)}regparse.c
regparse.$(OBJEXT): {$(VPATH)}regparse.h
regparse.$(OBJEXT): {$(VPATH)}st.h
regparse.$(OBJEXT): {$(VPATH)}subst.h
regsyntax.$(OBJEXT): $(hdrdir)/ruby/ruby.h
regsyntax.$(OBJEXT): {$(VPATH)}assert.h
regsyntax.$(OBJEXT): {$(VPATH)}config.h
regsyntax.$(OBJEXT): {$(VPATH)}defines.h
regsyntax.$(OBJEXT): {$(VPATH)}intern.h
regsyntax.$(OBJEXT): {$(VPATH)}missing.h
regsyntax.$(OBJEXT): {$(VPATH)}onigmo.h
regsyntax.$(OBJEXT): {$(VPATH)}oniguruma.h
regsyntax.$(OBJEXT): {$(VPATH)}regenc.h
regsyntax.$(OBJEXT): {$(VPATH)}regint.h
regsyntax.$(OBJEXT): {$(VPATH)}regsyntax.c
regsyntax.$(OBJEXT): {$(VPATH)}st.h
regsyntax.$(OBJEXT): {$(VPATH)}subst.h
ruby-runner.$(OBJEXT): {$(VPATH)}config.h
ruby-runner.$(OBJEXT): {$(VPATH)}ruby-runner.c
ruby-runner.$(OBJEXT): {$(VPATH)}ruby-runner.h
ruby.$(OBJEXT): $(CCAN_DIR)/check_type/check_type.h
ruby.$(OBJEXT): $(CCAN_DIR)/container_of/container_of.h
ruby.$(OBJEXT): $(CCAN_DIR)/list/list.h
ruby.$(OBJEXT): $(CCAN_DIR)/str/str.h
ruby.$(OBJEXT): $(hdrdir)/ruby.h
ruby.$(OBJEXT): $(hdrdir)/ruby/ruby.h
ruby.$(OBJEXT): $(hdrdir)/ruby/version.h
ruby.$(OBJEXT): {$(VPATH)}assert.h
ruby.$(OBJEXT): {$(VPATH)}config.h
ruby.$(OBJEXT): {$(VPATH)}debug_counter.h
ruby.$(OBJEXT): {$(VPATH)}defines.h
ruby.$(OBJEXT): {$(VPATH)}dln.h
ruby.$(OBJEXT): {$(VPATH)}encoding.h
ruby.$(OBJEXT): {$(VPATH)}eval_intern.h
ruby.$(OBJEXT): {$(VPATH)}id.h
ruby.$(OBJEXT): {$(VPATH)}intern.h
ruby.$(OBJEXT): {$(VPATH)}internal.h
ruby.$(OBJEXT): {$(VPATH)}io.h
ruby.$(OBJEXT): {$(VPATH)}method.h
ruby.$(OBJEXT): {$(VPATH)}missing.h
ruby.$(OBJEXT): {$(VPATH)}mjit.h
ruby.$(OBJEXT): {$(VPATH)}node.h
ruby.$(OBJEXT): {$(VPATH)}onigmo.h
ruby.$(OBJEXT): {$(VPATH)}oniguruma.h
ruby.$(OBJEXT): {$(VPATH)}ruby.c
ruby.$(OBJEXT): {$(VPATH)}ruby_assert.h
ruby.$(OBJEXT): {$(VPATH)}ruby_atomic.h
ruby.$(OBJEXT): {$(VPATH)}st.h
ruby.$(OBJEXT): {$(VPATH)}subst.h
ruby.$(OBJEXT): {$(VPATH)}thread.h
ruby.$(OBJEXT): {$(VPATH)}thread_$(THREAD_MODEL).h
ruby.$(OBJEXT): {$(VPATH)}thread_native.h
ruby.$(OBJEXT): {$(VPATH)}util.h
ruby.$(OBJEXT): {$(VPATH)}vm_core.h
ruby.$(OBJEXT): {$(VPATH)}vm_debug.h
ruby.$(OBJEXT): {$(VPATH)}vm_opts.h
safe.$(OBJEXT): $(CCAN_DIR)/check_type/check_type.h
safe.$(OBJEXT): $(CCAN_DIR)/container_of/container_of.h
safe.$(OBJEXT): $(CCAN_DIR)/list/list.h
safe.$(OBJEXT): $(CCAN_DIR)/str/str.h
safe.$(OBJEXT): $(hdrdir)/ruby.h
safe.$(OBJEXT): $(hdrdir)/ruby/ruby.h
safe.$(OBJEXT): {$(VPATH)}assert.h
safe.$(OBJEXT): {$(VPATH)}config.h
safe.$(OBJEXT): {$(VPATH)}defines.h
safe.$(OBJEXT): {$(VPATH)}encoding.h
safe.$(OBJEXT): {$(VPATH)}id.h
safe.$(OBJEXT): {$(VPATH)}intern.h
safe.$(OBJEXT): {$(VPATH)}internal.h
safe.$(OBJEXT): {$(VPATH)}io.h
safe.$(OBJEXT): {$(VPATH)}method.h
safe.$(OBJEXT): {$(VPATH)}missing.h
safe.$(OBJEXT): {$(VPATH)}node.h
safe.$(OBJEXT): {$(VPATH)}onigmo.h
safe.$(OBJEXT): {$(VPATH)}oniguruma.h
safe.$(OBJEXT): {$(VPATH)}ruby_assert.h
safe.$(OBJEXT): {$(VPATH)}ruby_atomic.h
safe.$(OBJEXT): {$(VPATH)}safe.c
safe.$(OBJEXT): {$(VPATH)}st.h
safe.$(OBJEXT): {$(VPATH)}subst.h
safe.$(OBJEXT): {$(VPATH)}thread_$(THREAD_MODEL).h
safe.$(OBJEXT): {$(VPATH)}thread_native.h
safe.$(OBJEXT): {$(VPATH)}vm_core.h
safe.$(OBJEXT): {$(VPATH)}vm_debug.h
safe.$(OBJEXT): {$(VPATH)}vm_opts.h
setproctitle.$(OBJEXT): $(hdrdir)/ruby.h
setproctitle.$(OBJEXT): $(hdrdir)/ruby/ruby.h
setproctitle.$(OBJEXT): {$(VPATH)}assert.h
setproctitle.$(OBJEXT): {$(VPATH)}config.h
setproctitle.$(OBJEXT): {$(VPATH)}defines.h
setproctitle.$(OBJEXT): {$(VPATH)}intern.h
setproctitle.$(OBJEXT): {$(VPATH)}missing.h
setproctitle.$(OBJEXT): {$(VPATH)}setproctitle.c
setproctitle.$(OBJEXT): {$(VPATH)}st.h
setproctitle.$(OBJEXT): {$(VPATH)}subst.h
setproctitle.$(OBJEXT): {$(VPATH)}util.h
signal.$(OBJEXT): $(CCAN_DIR)/check_type/check_type.h
signal.$(OBJEXT): $(CCAN_DIR)/container_of/container_of.h
signal.$(OBJEXT): $(CCAN_DIR)/list/list.h
signal.$(OBJEXT): $(CCAN_DIR)/str/str.h
signal.$(OBJEXT): $(hdrdir)/ruby.h
signal.$(OBJEXT): $(hdrdir)/ruby/ruby.h
signal.$(OBJEXT): {$(VPATH)}assert.h
signal.$(OBJEXT): {$(VPATH)}config.h
signal.$(OBJEXT): {$(VPATH)}debug_counter.h
signal.$(OBJEXT): {$(VPATH)}defines.h
signal.$(OBJEXT): {$(VPATH)}encoding.h
signal.$(OBJEXT): {$(VPATH)}eval_intern.h
signal.$(OBJEXT): {$(VPATH)}id.h
signal.$(OBJEXT): {$(VPATH)}intern.h
signal.$(OBJEXT): {$(VPATH)}internal.h
signal.$(OBJEXT): {$(VPATH)}io.h
signal.$(OBJEXT): {$(VPATH)}method.h
signal.$(OBJEXT): {$(VPATH)}missing.h
signal.$(OBJEXT): {$(VPATH)}node.h
signal.$(OBJEXT): {$(VPATH)}onigmo.h
signal.$(OBJEXT): {$(VPATH)}oniguruma.h
signal.$(OBJEXT): {$(VPATH)}ruby_assert.h
signal.$(OBJEXT): {$(VPATH)}ruby_atomic.h
signal.$(OBJEXT): {$(VPATH)}signal.c
signal.$(OBJEXT): {$(VPATH)}st.h
signal.$(OBJEXT): {$(VPATH)}subst.h
signal.$(OBJEXT): {$(VPATH)}thread_$(THREAD_MODEL).h
signal.$(OBJEXT): {$(VPATH)}thread_native.h
signal.$(OBJEXT): {$(VPATH)}vm_core.h
signal.$(OBJEXT): {$(VPATH)}vm_debug.h
signal.$(OBJEXT): {$(VPATH)}vm_opts.h
sprintf.$(OBJEXT): $(hdrdir)/ruby.h
sprintf.$(OBJEXT): $(hdrdir)/ruby/ruby.h
sprintf.$(OBJEXT): {$(VPATH)}assert.h
sprintf.$(OBJEXT): {$(VPATH)}config.h
sprintf.$(OBJEXT): {$(VPATH)}defines.h
sprintf.$(OBJEXT): {$(VPATH)}encoding.h
sprintf.$(OBJEXT): {$(VPATH)}id.h
sprintf.$(OBJEXT): {$(VPATH)}intern.h
sprintf.$(OBJEXT): {$(VPATH)}internal.h
sprintf.$(OBJEXT): {$(VPATH)}io.h
sprintf.$(OBJEXT): {$(VPATH)}missing.h
sprintf.$(OBJEXT): {$(VPATH)}onigmo.h
sprintf.$(OBJEXT): {$(VPATH)}oniguruma.h
sprintf.$(OBJEXT): {$(VPATH)}re.h
sprintf.$(OBJEXT): {$(VPATH)}regex.h
sprintf.$(OBJEXT): {$(VPATH)}sprintf.c
sprintf.$(OBJEXT): {$(VPATH)}st.h
sprintf.$(OBJEXT): {$(VPATH)}subst.h
sprintf.$(OBJEXT): {$(VPATH)}vsnprintf.c
st.$(OBJEXT): $(CCAN_DIR)/check_type/check_type.h
st.$(OBJEXT): $(CCAN_DIR)/container_of/container_of.h
st.$(OBJEXT): $(CCAN_DIR)/list/list.h
st.$(OBJEXT): $(CCAN_DIR)/str/str.h
st.$(OBJEXT): $(hdrdir)/ruby.h
st.$(OBJEXT): $(hdrdir)/ruby/ruby.h
st.$(OBJEXT): {$(VPATH)}assert.h
st.$(OBJEXT): {$(VPATH)}config.h
st.$(OBJEXT): {$(VPATH)}defines.h
st.$(OBJEXT): {$(VPATH)}encoding.h
st.$(OBJEXT): {$(VPATH)}intern.h
st.$(OBJEXT): {$(VPATH)}internal.h
st.$(OBJEXT): {$(VPATH)}io.h
st.$(OBJEXT): {$(VPATH)}missing.h
st.$(OBJEXT): {$(VPATH)}onigmo.h
st.$(OBJEXT): {$(VPATH)}oniguruma.h
st.$(OBJEXT): {$(VPATH)}st.c
st.$(OBJEXT): {$(VPATH)}st.h
st.$(OBJEXT): {$(VPATH)}subst.h
strftime.$(OBJEXT): $(hdrdir)/ruby.h
strftime.$(OBJEXT): $(hdrdir)/ruby/ruby.h
strftime.$(OBJEXT): {$(VPATH)}assert.h
strftime.$(OBJEXT): {$(VPATH)}config.h
strftime.$(OBJEXT): {$(VPATH)}defines.h
strftime.$(OBJEXT): {$(VPATH)}encoding.h
strftime.$(OBJEXT): {$(VPATH)}intern.h
strftime.$(OBJEXT): {$(VPATH)}internal.h
strftime.$(OBJEXT): {$(VPATH)}io.h
strftime.$(OBJEXT): {$(VPATH)}missing.h
strftime.$(OBJEXT): {$(VPATH)}onigmo.h
strftime.$(OBJEXT): {$(VPATH)}oniguruma.h
strftime.$(OBJEXT): {$(VPATH)}st.h
strftime.$(OBJEXT): {$(VPATH)}strftime.c
strftime.$(OBJEXT): {$(VPATH)}subst.h
strftime.$(OBJEXT): {$(VPATH)}timev.h
string.$(OBJEXT): $(hdrdir)/ruby.h
string.$(OBJEXT): $(hdrdir)/ruby/ruby.h
string.$(OBJEXT): {$(VPATH)}assert.h
string.$(OBJEXT): {$(VPATH)}config.h
string.$(OBJEXT): {$(VPATH)}crypt.h
string.$(OBJEXT): {$(VPATH)}debug_counter.h
string.$(OBJEXT): {$(VPATH)}defines.h
string.$(OBJEXT): {$(VPATH)}encindex.h
string.$(OBJEXT): {$(VPATH)}encoding.h
string.$(OBJEXT): {$(VPATH)}gc.h
string.$(OBJEXT): {$(VPATH)}id.h
string.$(OBJEXT): {$(VPATH)}intern.h
string.$(OBJEXT): {$(VPATH)}internal.h
string.$(OBJEXT): {$(VPATH)}io.h
string.$(OBJEXT): {$(VPATH)}missing.h
string.$(OBJEXT): {$(VPATH)}onigmo.h
string.$(OBJEXT): {$(VPATH)}oniguruma.h
string.$(OBJEXT): {$(VPATH)}probes.dmyh
string.$(OBJEXT): {$(VPATH)}probes.h
string.$(OBJEXT): {$(VPATH)}re.h
string.$(OBJEXT): {$(VPATH)}regex.h
string.$(OBJEXT): {$(VPATH)}ruby_assert.h
string.$(OBJEXT): {$(VPATH)}st.h
string.$(OBJEXT): {$(VPATH)}string.c
string.$(OBJEXT): {$(VPATH)}subst.h
string.$(OBJEXT): {$(VPATH)}util.h
strlcat.$(OBJEXT): {$(VPATH)}config.h
strlcat.$(OBJEXT): {$(VPATH)}missing.h
strlcat.$(OBJEXT): {$(VPATH)}strlcat.c
strlcpy.$(OBJEXT): {$(VPATH)}config.h
strlcpy.$(OBJEXT): {$(VPATH)}missing.h
strlcpy.$(OBJEXT): {$(VPATH)}strlcpy.c
struct.$(OBJEXT): $(CCAN_DIR)/check_type/check_type.h
struct.$(OBJEXT): $(CCAN_DIR)/container_of/container_of.h
struct.$(OBJEXT): $(CCAN_DIR)/list/list.h
struct.$(OBJEXT): $(CCAN_DIR)/str/str.h
struct.$(OBJEXT): $(hdrdir)/ruby.h
struct.$(OBJEXT): $(hdrdir)/ruby/ruby.h
struct.$(OBJEXT): {$(VPATH)}assert.h
struct.$(OBJEXT): {$(VPATH)}config.h
struct.$(OBJEXT): {$(VPATH)}defines.h
struct.$(OBJEXT): {$(VPATH)}encoding.h
struct.$(OBJEXT): {$(VPATH)}id.h
struct.$(OBJEXT): {$(VPATH)}intern.h
struct.$(OBJEXT): {$(VPATH)}internal.h
struct.$(OBJEXT): {$(VPATH)}io.h
struct.$(OBJEXT): {$(VPATH)}method.h
struct.$(OBJEXT): {$(VPATH)}missing.h
struct.$(OBJEXT): {$(VPATH)}node.h
struct.$(OBJEXT): {$(VPATH)}onigmo.h
struct.$(OBJEXT): {$(VPATH)}oniguruma.h
struct.$(OBJEXT): {$(VPATH)}ruby_assert.h
struct.$(OBJEXT): {$(VPATH)}ruby_atomic.h
struct.$(OBJEXT): {$(VPATH)}st.h
struct.$(OBJEXT): {$(VPATH)}struct.c
struct.$(OBJEXT): {$(VPATH)}subst.h
struct.$(OBJEXT): {$(VPATH)}thread_$(THREAD_MODEL).h
struct.$(OBJEXT): {$(VPATH)}thread_native.h
struct.$(OBJEXT): {$(VPATH)}transient_heap.h
struct.$(OBJEXT): {$(VPATH)}vm_core.h
struct.$(OBJEXT): {$(VPATH)}vm_debug.h
struct.$(OBJEXT): {$(VPATH)}vm_opts.h
symbol.$(OBJEXT): $(hdrdir)/ruby.h
symbol.$(OBJEXT): $(hdrdir)/ruby/ruby.h
symbol.$(OBJEXT): {$(VPATH)}assert.h
symbol.$(OBJEXT): {$(VPATH)}config.h
symbol.$(OBJEXT): {$(VPATH)}defines.h
symbol.$(OBJEXT): {$(VPATH)}encoding.h
symbol.$(OBJEXT): {$(VPATH)}gc.h
symbol.$(OBJEXT): {$(VPATH)}id.c
symbol.$(OBJEXT): {$(VPATH)}id.h
symbol.$(OBJEXT): {$(VPATH)}id_table.c
symbol.$(OBJEXT): {$(VPATH)}id_table.h
symbol.$(OBJEXT): {$(VPATH)}intern.h
symbol.$(OBJEXT): {$(VPATH)}internal.h
symbol.$(OBJEXT): {$(VPATH)}io.h
symbol.$(OBJEXT): {$(VPATH)}missing.h
symbol.$(OBJEXT): {$(VPATH)}onigmo.h
symbol.$(OBJEXT): {$(VPATH)}oniguruma.h
symbol.$(OBJEXT): {$(VPATH)}probes.dmyh
symbol.$(OBJEXT): {$(VPATH)}probes.h
symbol.$(OBJEXT): {$(VPATH)}ruby_assert.h
symbol.$(OBJEXT): {$(VPATH)}st.h
symbol.$(OBJEXT): {$(VPATH)}subst.h
symbol.$(OBJEXT): {$(VPATH)}symbol.c
symbol.$(OBJEXT): {$(VPATH)}symbol.h
thread.$(OBJEXT): $(CCAN_DIR)/check_type/check_type.h
thread.$(OBJEXT): $(CCAN_DIR)/container_of/container_of.h
thread.$(OBJEXT): $(CCAN_DIR)/list/list.h
thread.$(OBJEXT): $(CCAN_DIR)/str/str.h
thread.$(OBJEXT): $(hdrdir)/ruby.h
thread.$(OBJEXT): $(hdrdir)/ruby/ruby.h
thread.$(OBJEXT): {$(VPATH)}assert.h
thread.$(OBJEXT): {$(VPATH)}config.h
thread.$(OBJEXT): {$(VPATH)}debug.h
thread.$(OBJEXT): {$(VPATH)}debug_counter.h
thread.$(OBJEXT): {$(VPATH)}defines.h
thread.$(OBJEXT): {$(VPATH)}encoding.h
thread.$(OBJEXT): {$(VPATH)}eval_intern.h
thread.$(OBJEXT): {$(VPATH)}gc.h
thread.$(OBJEXT): {$(VPATH)}hrtime.h
thread.$(OBJEXT): {$(VPATH)}id.h
thread.$(OBJEXT): {$(VPATH)}intern.h
thread.$(OBJEXT): {$(VPATH)}internal.h
thread.$(OBJEXT): {$(VPATH)}io.h
thread.$(OBJEXT): {$(VPATH)}iseq.h
thread.$(OBJEXT): {$(VPATH)}method.h
thread.$(OBJEXT): {$(VPATH)}missing.h
thread.$(OBJEXT): {$(VPATH)}mjit.h
thread.$(OBJEXT): {$(VPATH)}node.h
thread.$(OBJEXT): {$(VPATH)}onigmo.h
thread.$(OBJEXT): {$(VPATH)}oniguruma.h
thread.$(OBJEXT): {$(VPATH)}ruby_assert.h
thread.$(OBJEXT): {$(VPATH)}ruby_atomic.h
thread.$(OBJEXT): {$(VPATH)}st.h
thread.$(OBJEXT): {$(VPATH)}subst.h
thread.$(OBJEXT): {$(VPATH)}thread.c
thread.$(OBJEXT): {$(VPATH)}thread.h
thread.$(OBJEXT): {$(VPATH)}thread_$(THREAD_MODEL).c
thread.$(OBJEXT): {$(VPATH)}thread_$(THREAD_MODEL).h
thread.$(OBJEXT): {$(VPATH)}thread_native.h
thread.$(OBJEXT): {$(VPATH)}thread_sync.c
thread.$(OBJEXT): {$(VPATH)}timev.h
thread.$(OBJEXT): {$(VPATH)}vm_core.h
thread.$(OBJEXT): {$(VPATH)}vm_debug.h
thread.$(OBJEXT): {$(VPATH)}vm_opts.h
time.$(OBJEXT): $(hdrdir)/ruby.h
time.$(OBJEXT): $(hdrdir)/ruby/ruby.h
time.$(OBJEXT): {$(VPATH)}assert.h
time.$(OBJEXT): {$(VPATH)}config.h
time.$(OBJEXT): {$(VPATH)}defines.h
time.$(OBJEXT): {$(VPATH)}encoding.h
time.$(OBJEXT): {$(VPATH)}id.h
time.$(OBJEXT): {$(VPATH)}intern.h
time.$(OBJEXT): {$(VPATH)}internal.h
time.$(OBJEXT): {$(VPATH)}io.h
time.$(OBJEXT): {$(VPATH)}missing.h
time.$(OBJEXT): {$(VPATH)}onigmo.h
time.$(OBJEXT): {$(VPATH)}oniguruma.h
time.$(OBJEXT): {$(VPATH)}st.h
time.$(OBJEXT): {$(VPATH)}subst.h
time.$(OBJEXT): {$(VPATH)}time.c
time.$(OBJEXT): {$(VPATH)}timev.h
transcode.$(OBJEXT): $(hdrdir)/ruby.h
transcode.$(OBJEXT): $(hdrdir)/ruby/ruby.h
transcode.$(OBJEXT): {$(VPATH)}assert.h
transcode.$(OBJEXT): {$(VPATH)}config.h
transcode.$(OBJEXT): {$(VPATH)}defines.h
transcode.$(OBJEXT): {$(VPATH)}encoding.h
transcode.$(OBJEXT): {$(VPATH)}intern.h
transcode.$(OBJEXT): {$(VPATH)}internal.h
transcode.$(OBJEXT): {$(VPATH)}io.h
transcode.$(OBJEXT): {$(VPATH)}missing.h
transcode.$(OBJEXT): {$(VPATH)}onigmo.h
transcode.$(OBJEXT): {$(VPATH)}oniguruma.h
transcode.$(OBJEXT): {$(VPATH)}st.h
transcode.$(OBJEXT): {$(VPATH)}subst.h
transcode.$(OBJEXT): {$(VPATH)}transcode.c
transcode.$(OBJEXT): {$(VPATH)}transcode_data.h
transient_heap.$(OBJEXT): $(hdrdir)/ruby.h
transient_heap.$(OBJEXT): $(hdrdir)/ruby/ruby.h
transient_heap.$(OBJEXT): {$(VPATH)}assert.h
transient_heap.$(OBJEXT): {$(VPATH)}config.h
transient_heap.$(OBJEXT): {$(VPATH)}debug.h
transient_heap.$(OBJEXT): {$(VPATH)}debug_counter.h
transient_heap.$(OBJEXT): {$(VPATH)}defines.h
transient_heap.$(OBJEXT): {$(VPATH)}gc.h
transient_heap.$(OBJEXT): {$(VPATH)}intern.h
transient_heap.$(OBJEXT): {$(VPATH)}internal.h
transient_heap.$(OBJEXT): {$(VPATH)}missing.h
transient_heap.$(OBJEXT): {$(VPATH)}node.h
transient_heap.$(OBJEXT): {$(VPATH)}ruby_assert.h
transient_heap.$(OBJEXT): {$(VPATH)}st.h
transient_heap.$(OBJEXT): {$(VPATH)}subst.h
transient_heap.$(OBJEXT): {$(VPATH)}transient_heap.c
transient_heap.$(OBJEXT): {$(VPATH)}transient_heap.h
transient_heap.$(OBJEXT): {$(VPATH)}vm_debug.h
util.$(OBJEXT): $(hdrdir)/ruby.h
util.$(OBJEXT): $(hdrdir)/ruby/ruby.h
util.$(OBJEXT): {$(VPATH)}assert.h
util.$(OBJEXT): {$(VPATH)}config.h
util.$(OBJEXT): {$(VPATH)}defines.h
util.$(OBJEXT): {$(VPATH)}dtoa.c
util.$(OBJEXT): {$(VPATH)}encoding.h
util.$(OBJEXT): {$(VPATH)}intern.h
util.$(OBJEXT): {$(VPATH)}internal.h
util.$(OBJEXT): {$(VPATH)}io.h
util.$(OBJEXT): {$(VPATH)}missing.h
util.$(OBJEXT): {$(VPATH)}onigmo.h
util.$(OBJEXT): {$(VPATH)}oniguruma.h
util.$(OBJEXT): {$(VPATH)}st.h
util.$(OBJEXT): {$(VPATH)}subst.h
util.$(OBJEXT): {$(VPATH)}util.c
util.$(OBJEXT): {$(VPATH)}util.h
variable.$(OBJEXT): $(CCAN_DIR)/check_type/check_type.h
variable.$(OBJEXT): $(CCAN_DIR)/container_of/container_of.h
variable.$(OBJEXT): $(CCAN_DIR)/list/list.h
variable.$(OBJEXT): $(CCAN_DIR)/str/str.h
variable.$(OBJEXT): $(hdrdir)/ruby.h
variable.$(OBJEXT): $(hdrdir)/ruby/ruby.h
variable.$(OBJEXT): {$(VPATH)}assert.h
variable.$(OBJEXT): {$(VPATH)}config.h
variable.$(OBJEXT): {$(VPATH)}constant.h
variable.$(OBJEXT): {$(VPATH)}debug_counter.h
variable.$(OBJEXT): {$(VPATH)}defines.h
variable.$(OBJEXT): {$(VPATH)}encoding.h
variable.$(OBJEXT): {$(VPATH)}id.h
variable.$(OBJEXT): {$(VPATH)}id_table.h
variable.$(OBJEXT): {$(VPATH)}intern.h
variable.$(OBJEXT): {$(VPATH)}internal.h
variable.$(OBJEXT): {$(VPATH)}io.h
variable.$(OBJEXT): {$(VPATH)}method.h
variable.$(OBJEXT): {$(VPATH)}missing.h
variable.$(OBJEXT): {$(VPATH)}node.h
variable.$(OBJEXT): {$(VPATH)}onigmo.h
variable.$(OBJEXT): {$(VPATH)}oniguruma.h
variable.$(OBJEXT): {$(VPATH)}ruby_assert.h
variable.$(OBJEXT): {$(VPATH)}ruby_atomic.h
variable.$(OBJEXT): {$(VPATH)}st.h
variable.$(OBJEXT): {$(VPATH)}subst.h
variable.$(OBJEXT): {$(VPATH)}thread_$(THREAD_MODEL).h
variable.$(OBJEXT): {$(VPATH)}thread_native.h
variable.$(OBJEXT): {$(VPATH)}transient_heap.h
variable.$(OBJEXT): {$(VPATH)}util.h
variable.$(OBJEXT): {$(VPATH)}variable.c
variable.$(OBJEXT): {$(VPATH)}vm_core.h
variable.$(OBJEXT): {$(VPATH)}vm_opts.h
version.$(OBJEXT): $(CCAN_DIR)/check_type/check_type.h
version.$(OBJEXT): $(CCAN_DIR)/container_of/container_of.h
version.$(OBJEXT): $(CCAN_DIR)/list/list.h
version.$(OBJEXT): $(CCAN_DIR)/str/str.h
version.$(OBJEXT): $(hdrdir)/ruby.h
version.$(OBJEXT): $(hdrdir)/ruby/ruby.h
version.$(OBJEXT): $(hdrdir)/ruby/version.h
version.$(OBJEXT): $(top_srcdir)/revision.h
version.$(OBJEXT): $(top_srcdir)/version.h
version.$(OBJEXT): {$(VPATH)}assert.h
version.$(OBJEXT): {$(VPATH)}config.h
version.$(OBJEXT): {$(VPATH)}debug_counter.h
version.$(OBJEXT): {$(VPATH)}defines.h
version.$(OBJEXT): {$(VPATH)}id.h
version.$(OBJEXT): {$(VPATH)}intern.h
version.$(OBJEXT): {$(VPATH)}internal.h
version.$(OBJEXT): {$(VPATH)}method.h
version.$(OBJEXT): {$(VPATH)}missing.h
version.$(OBJEXT): {$(VPATH)}mjit.h
version.$(OBJEXT): {$(VPATH)}node.h
version.$(OBJEXT): {$(VPATH)}ruby_assert.h
version.$(OBJEXT): {$(VPATH)}ruby_atomic.h
version.$(OBJEXT): {$(VPATH)}st.h
version.$(OBJEXT): {$(VPATH)}subst.h
version.$(OBJEXT): {$(VPATH)}thread_$(THREAD_MODEL).h
version.$(OBJEXT): {$(VPATH)}thread_native.h
version.$(OBJEXT): {$(VPATH)}version.c
version.$(OBJEXT): {$(VPATH)}vm_core.h
version.$(OBJEXT): {$(VPATH)}vm_opts.h
vm.$(OBJEXT): $(CCAN_DIR)/check_type/check_type.h
vm.$(OBJEXT): $(CCAN_DIR)/container_of/container_of.h
vm.$(OBJEXT): $(CCAN_DIR)/list/list.h
vm.$(OBJEXT): $(CCAN_DIR)/str/str.h
vm.$(OBJEXT): $(hdrdir)/ruby.h
vm.$(OBJEXT): $(hdrdir)/ruby/ruby.h
vm.$(OBJEXT): {$(VPATH)}assert.h
vm.$(OBJEXT): {$(VPATH)}config.h
vm.$(OBJEXT): {$(VPATH)}constant.h
vm.$(OBJEXT): {$(VPATH)}debug_counter.h
vm.$(OBJEXT): {$(VPATH)}defines.h
vm.$(OBJEXT): {$(VPATH)}defs/opt_operand.def
vm.$(OBJEXT): {$(VPATH)}encoding.h
vm.$(OBJEXT): {$(VPATH)}eval_intern.h
vm.$(OBJEXT): {$(VPATH)}gc.h
vm.$(OBJEXT): {$(VPATH)}id.h
vm.$(OBJEXT): {$(VPATH)}id_table.h
vm.$(OBJEXT): {$(VPATH)}insns.def
vm.$(OBJEXT): {$(VPATH)}insns.inc
vm.$(OBJEXT): {$(VPATH)}insns_info.inc
vm.$(OBJEXT): {$(VPATH)}intern.h
vm.$(OBJEXT): {$(VPATH)}internal.h
vm.$(OBJEXT): {$(VPATH)}io.h
vm.$(OBJEXT): {$(VPATH)}iseq.h
vm.$(OBJEXT): {$(VPATH)}method.h
vm.$(OBJEXT): {$(VPATH)}missing.h
vm.$(OBJEXT): {$(VPATH)}mjit.h
vm.$(OBJEXT): {$(VPATH)}node.h
vm.$(OBJEXT): {$(VPATH)}onigmo.h
vm.$(OBJEXT): {$(VPATH)}oniguruma.h
vm.$(OBJEXT): {$(VPATH)}probes.dmyh
vm.$(OBJEXT): {$(VPATH)}probes.h
vm.$(OBJEXT): {$(VPATH)}probes_helper.h
vm.$(OBJEXT): {$(VPATH)}ruby_assert.h
vm.$(OBJEXT): {$(VPATH)}ruby_atomic.h
vm.$(OBJEXT): {$(VPATH)}st.h
vm.$(OBJEXT): {$(VPATH)}subst.h
vm.$(OBJEXT): {$(VPATH)}thread_$(THREAD_MODEL).h
vm.$(OBJEXT): {$(VPATH)}thread_native.h
vm.$(OBJEXT): {$(VPATH)}vm.c
vm.$(OBJEXT): {$(VPATH)}vm.h
vm.$(OBJEXT): {$(VPATH)}vm.inc
vm.$(OBJEXT): {$(VPATH)}vm_args.c
vm.$(OBJEXT): {$(VPATH)}vm_call_iseq_optimized.inc
vm.$(OBJEXT): {$(VPATH)}vm_core.h
vm.$(OBJEXT): {$(VPATH)}vm_debug.h
vm.$(OBJEXT): {$(VPATH)}vm_eval.c
vm.$(OBJEXT): {$(VPATH)}vm_exec.c
vm.$(OBJEXT): {$(VPATH)}vm_exec.h
vm.$(OBJEXT): {$(VPATH)}vm_insnhelper.c
vm.$(OBJEXT): {$(VPATH)}vm_insnhelper.h
vm.$(OBJEXT): {$(VPATH)}vm_method.c
vm.$(OBJEXT): {$(VPATH)}vm_opts.h
vm.$(OBJEXT): {$(VPATH)}vmtc.inc
vm_backtrace.$(OBJEXT): $(CCAN_DIR)/check_type/check_type.h
vm_backtrace.$(OBJEXT): $(CCAN_DIR)/container_of/container_of.h
vm_backtrace.$(OBJEXT): $(CCAN_DIR)/list/list.h
vm_backtrace.$(OBJEXT): $(CCAN_DIR)/str/str.h
vm_backtrace.$(OBJEXT): $(hdrdir)/ruby.h
vm_backtrace.$(OBJEXT): $(hdrdir)/ruby/ruby.h
vm_backtrace.$(OBJEXT): {$(VPATH)}assert.h
vm_backtrace.$(OBJEXT): {$(VPATH)}config.h
vm_backtrace.$(OBJEXT): {$(VPATH)}debug.h
vm_backtrace.$(OBJEXT): {$(VPATH)}defines.h
vm_backtrace.$(OBJEXT): {$(VPATH)}encoding.h
vm_backtrace.$(OBJEXT): {$(VPATH)}eval_intern.h
vm_backtrace.$(OBJEXT): {$(VPATH)}id.h
vm_backtrace.$(OBJEXT): {$(VPATH)}intern.h
vm_backtrace.$(OBJEXT): {$(VPATH)}internal.h
vm_backtrace.$(OBJEXT): {$(VPATH)}io.h
vm_backtrace.$(OBJEXT): {$(VPATH)}iseq.h
vm_backtrace.$(OBJEXT): {$(VPATH)}method.h
vm_backtrace.$(OBJEXT): {$(VPATH)}missing.h
vm_backtrace.$(OBJEXT): {$(VPATH)}node.h
vm_backtrace.$(OBJEXT): {$(VPATH)}onigmo.h
vm_backtrace.$(OBJEXT): {$(VPATH)}oniguruma.h
vm_backtrace.$(OBJEXT): {$(VPATH)}ruby_assert.h
vm_backtrace.$(OBJEXT): {$(VPATH)}ruby_atomic.h
vm_backtrace.$(OBJEXT): {$(VPATH)}st.h
vm_backtrace.$(OBJEXT): {$(VPATH)}subst.h
vm_backtrace.$(OBJEXT): {$(VPATH)}thread_$(THREAD_MODEL).h
vm_backtrace.$(OBJEXT): {$(VPATH)}thread_native.h
vm_backtrace.$(OBJEXT): {$(VPATH)}vm_backtrace.c
vm_backtrace.$(OBJEXT): {$(VPATH)}vm_core.h
vm_backtrace.$(OBJEXT): {$(VPATH)}vm_debug.h
vm_backtrace.$(OBJEXT): {$(VPATH)}vm_opts.h
vm_dump.$(OBJEXT): $(CCAN_DIR)/check_type/check_type.h
vm_dump.$(OBJEXT): $(CCAN_DIR)/container_of/container_of.h
vm_dump.$(OBJEXT): $(CCAN_DIR)/list/list.h
vm_dump.$(OBJEXT): $(CCAN_DIR)/str/str.h
vm_dump.$(OBJEXT): $(hdrdir)/ruby.h
vm_dump.$(OBJEXT): $(hdrdir)/ruby/ruby.h
vm_dump.$(OBJEXT): {$(VPATH)}addr2line.h
vm_dump.$(OBJEXT): {$(VPATH)}assert.h
vm_dump.$(OBJEXT): {$(VPATH)}config.h
vm_dump.$(OBJEXT): {$(VPATH)}defines.h
vm_dump.$(OBJEXT): {$(VPATH)}encoding.h
vm_dump.$(OBJEXT): {$(VPATH)}id.h
vm_dump.$(OBJEXT): {$(VPATH)}intern.h
vm_dump.$(OBJEXT): {$(VPATH)}internal.h
vm_dump.$(OBJEXT): {$(VPATH)}io.h
vm_dump.$(OBJEXT): {$(VPATH)}iseq.h
vm_dump.$(OBJEXT): {$(VPATH)}method.h
vm_dump.$(OBJEXT): {$(VPATH)}missing.h
vm_dump.$(OBJEXT): {$(VPATH)}node.h
vm_dump.$(OBJEXT): {$(VPATH)}onigmo.h
vm_dump.$(OBJEXT): {$(VPATH)}oniguruma.h
vm_dump.$(OBJEXT): {$(VPATH)}procstat_vm.c
vm_dump.$(OBJEXT): {$(VPATH)}ruby_assert.h
vm_dump.$(OBJEXT): {$(VPATH)}ruby_atomic.h
vm_dump.$(OBJEXT): {$(VPATH)}st.h
vm_dump.$(OBJEXT): {$(VPATH)}subst.h
vm_dump.$(OBJEXT): {$(VPATH)}thread_$(THREAD_MODEL).h
vm_dump.$(OBJEXT): {$(VPATH)}thread_native.h
vm_dump.$(OBJEXT): {$(VPATH)}vm_core.h
vm_dump.$(OBJEXT): {$(VPATH)}vm_debug.h
vm_dump.$(OBJEXT): {$(VPATH)}vm_dump.c
vm_dump.$(OBJEXT): {$(VPATH)}vm_opts.h
vm_trace.$(OBJEXT): $(CCAN_DIR)/check_type/check_type.h
vm_trace.$(OBJEXT): $(CCAN_DIR)/container_of/container_of.h
vm_trace.$(OBJEXT): $(CCAN_DIR)/list/list.h
vm_trace.$(OBJEXT): $(CCAN_DIR)/str/str.h
vm_trace.$(OBJEXT): $(hdrdir)/ruby.h
vm_trace.$(OBJEXT): $(hdrdir)/ruby/ruby.h
vm_trace.$(OBJEXT): {$(VPATH)}assert.h
vm_trace.$(OBJEXT): {$(VPATH)}config.h
vm_trace.$(OBJEXT): {$(VPATH)}debug.h
vm_trace.$(OBJEXT): {$(VPATH)}debug_counter.h
vm_trace.$(OBJEXT): {$(VPATH)}defines.h
vm_trace.$(OBJEXT): {$(VPATH)}encoding.h
vm_trace.$(OBJEXT): {$(VPATH)}eval_intern.h
vm_trace.$(OBJEXT): {$(VPATH)}id.h
vm_trace.$(OBJEXT): {$(VPATH)}intern.h
vm_trace.$(OBJEXT): {$(VPATH)}internal.h
vm_trace.$(OBJEXT): {$(VPATH)}io.h
vm_trace.$(OBJEXT): {$(VPATH)}iseq.h
vm_trace.$(OBJEXT): {$(VPATH)}method.h
vm_trace.$(OBJEXT): {$(VPATH)}missing.h
vm_trace.$(OBJEXT): {$(VPATH)}mjit.h
vm_trace.$(OBJEXT): {$(VPATH)}node.h
vm_trace.$(OBJEXT): {$(VPATH)}onigmo.h
vm_trace.$(OBJEXT): {$(VPATH)}oniguruma.h
vm_trace.$(OBJEXT): {$(VPATH)}ruby_assert.h
vm_trace.$(OBJEXT): {$(VPATH)}ruby_atomic.h
vm_trace.$(OBJEXT): {$(VPATH)}st.h
vm_trace.$(OBJEXT): {$(VPATH)}subst.h
vm_trace.$(OBJEXT): {$(VPATH)}thread_$(THREAD_MODEL).h
vm_trace.$(OBJEXT): {$(VPATH)}thread_native.h
vm_trace.$(OBJEXT): {$(VPATH)}vm_core.h
vm_trace.$(OBJEXT): {$(VPATH)}vm_debug.h
vm_trace.$(OBJEXT): {$(VPATH)}vm_opts.h
vm_trace.$(OBJEXT): {$(VPATH)}vm_trace.c
# AUTOGENERATED DEPENDENCIES END
