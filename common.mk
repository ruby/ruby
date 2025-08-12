# -*- mode: makefile-gmake; indent-tabs-mode: t -*-
# This fragment can be used with nmake.exe and with bsdmake.
# Avoid features specific to GNU Make.

bin: $(PROGRAM) $(WPROGRAM)
lib: $(LIBRUBY)
dll: $(LIBRUBY_SO)

.SUFFIXES: .rbinc .rbbin .rb .inc .h .c .y .i .$(ASMEXT) .$(DTRACE_EXT)

# V=0 quiet, V=1 verbose.  other values don't work.
V = 0
V0 = $(V:0=)
Q1 = $(V:1=)
Q = $(Q1:0=@)
ECHO0 = $(ECHO1:0=echo)
ECHO = @$(ECHO0)

mflags = $(MFLAGS)
gnumake_recursive =
sequential = $(gnumake:yes=-sequential)
enable_shared = $(ENABLE_SHARED:no=)

UNICODE_VERSION = 16.0.0
UNICODE_EMOJI_VERSION_0 = $(UNICODE_VERSION)///
UNICODE_EMOJI_VERSION_1 = $(UNICODE_EMOJI_VERSION_0:.0///=)
UNICODE_EMOJI_VERSION = $(UNICODE_EMOJI_VERSION_1:///=)
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

# GITPULLOPTIONS = --no-tags

PRISM_SRCDIR = $(srcdir)/prism
INCFLAGS = -I. -I$(arch_hdrdir) -I$(ext_hdrdir) -I$(hdrdir) -I$(srcdir) -I$(PRISM_SRCDIR) -I$(UNICODE_HDR_DIR) $(incflags)

GEM_HOME =
GEM_PATH =
GEM_VENDOR =

BENCHMARK_DRIVER_GIT_URL = https://github.com/benchmark-driver/benchmark-driver
BENCHMARK_DRIVER_GIT_REF = v0.16.3

STATIC_RUBY   = static-ruby

TIMESTAMPDIR  = $(EXTOUT)/.timestamp
RUBYCOMMONDIR = $(EXTOUT)/common
EXTCONF       = extconf.rb
LIBRUBY_EXTS  = ./.libruby-with-ext.time
REVISION_H    = ./.revision.time
PLATFORM_D    = $(TIMESTAMPDIR)/.$(PLATFORM_DIR).time
ENC_TRANS_D   = $(TIMESTAMPDIR)/.enc-trans.time
RDOC          = $(XRUBY) "$(tooldir)/rdoc-srcdir"
RDOCOUT       = $(EXTOUT)/rdoc
HTMLOUT       = $(EXTOUT)/html
CAPIOUT       = doc/capi
INSTALL_DOC_OPTS = --rdoc-output="$(RDOCOUT)" --html-output="$(HTMLOUT)"
RDOC_GEN_OPTS = --no-force-update \
	$(empty)

INITOBJS      = dmyext.$(OBJEXT) dmyenc.$(OBJEXT)
NORMALMAINOBJ = main.$(OBJEXT)
MAINOBJ       = $(NORMALMAINOBJ)
DLDOBJS	      = $(INITOBJS)
EXTSOLIBS     =
MINIOBJS      = $(ARCHMINIOBJS) miniinit.$(OBJEXT)
ENC_MK        = enc.mk
MAKE_ENC      = -f $(ENC_MK) V="$(V)" UNICODE_HDR_DIR="$(UNICODE_HDR_DIR)" \
		RUBY="$(BOOTSTRAPRUBY)" MINIRUBY="$(BOOTSTRAPRUBY)" $(mflags)

PRISM_BUILD_DIR = prism

PRISM_FILES = prism/api_node.$(OBJEXT) \
		prism/api_pack.$(OBJEXT) \
		prism/diagnostic.$(OBJEXT) \
		prism/encoding.$(OBJEXT) \
		prism/extension.$(OBJEXT) \
		prism/node.$(OBJEXT) \
		prism/options.$(OBJEXT) \
		prism/pack.$(OBJEXT) \
		prism/prettyprint.$(OBJEXT) \
		prism/regexp.$(OBJEXT) \
		prism/serialize.$(OBJEXT) \
		prism/static_literals.$(OBJEXT) \
		prism/token_type.$(OBJEXT) \
		prism/util/pm_buffer.$(OBJEXT) \
		prism/util/pm_char.$(OBJEXT) \
		prism/util/pm_constant_pool.$(OBJEXT) \
		prism/util/pm_integer.$(OBJEXT) \
		prism/util/pm_list.$(OBJEXT) \
		prism/util/pm_memchr.$(OBJEXT) \
		prism/util/pm_newline_list.$(OBJEXT) \
		prism/util/pm_string.$(OBJEXT) \
		prism/util/pm_strncasecmp.$(OBJEXT) \
		prism/util/pm_strpbrk.$(OBJEXT) \
		prism/prism.$(OBJEXT) \
		prism_init.$(OBJEXT)

COMMONOBJS    = \
		array.$(OBJEXT) \
		ast.$(OBJEXT) \
		bignum.$(OBJEXT) \
		class.$(OBJEXT) \
		compar.$(OBJEXT) \
		compile.$(OBJEXT) \
		complex.$(OBJEXT) \
		concurrent_set.$(OBJEXT) \
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
		imemo.$(OBJEXT) \
		inits.$(OBJEXT) \
		io.$(OBJEXT) \
		io_buffer.$(OBJEXT) \
		iseq.$(OBJEXT) \
		load.$(OBJEXT) \
		marshal.$(OBJEXT) \
		math.$(OBJEXT) \
		memory_view.$(OBJEXT) \
		namespace.$(OBJEXT) \
		node.$(OBJEXT) \
		node_dump.$(OBJEXT) \
		numeric.$(OBJEXT) \
		object.$(OBJEXT) \
		pack.$(OBJEXT) \
		pathname.$(OBJEXT) \
		parse.$(OBJEXT) \
		parser_st.$(OBJEXT) \
		proc.$(OBJEXT) \
		process.$(OBJEXT) \
		ractor.$(OBJEXT) \
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
		ruby_parser.$(OBJEXT) \
		scheduler.$(OBJEXT) \
		set.$(OBJEXT) \
		shape.$(OBJEXT) \
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
		util.$(OBJEXT) \
		variable.$(OBJEXT) \
		version.$(OBJEXT) \
		vm.$(OBJEXT) \
		vm_backtrace.$(OBJEXT) \
		vm_dump.$(OBJEXT) \
		vm_sync.$(OBJEXT) \
		vm_trace.$(OBJEXT) \
		weakmap.$(OBJEXT) \
		$(PRISM_FILES) \
		$(YJIT_OBJ) \
		$(ZJIT_OBJ) \
		$(JIT_OBJ) \
		$(RUST_LIBOBJ) \
		$(COROUTINE_OBJ) \
		$(DTRACE_OBJ) \
		$(BUILTIN_ENCOBJS) \
		$(BUILTIN_TRANSOBJS) \
		$(MISSING)

$(PRISM_FILES): $(PRISM_BUILD_DIR)/.time $(PRISM_BUILD_DIR)/util/.time

$(PRISM_BUILD_DIR)/.time $(PRISM_BUILD_DIR)/util/.time:
	$(Q) $(MAKEDIRS) $(@D)
	@$(NULLCMD) > $@

main: $(srcdir)/lib/prism/compiler.rb
srcs: $(srcdir)/lib/prism/compiler.rb
$(srcdir)/lib/prism/compiler.rb: $(PRISM_SRCDIR)/config.yml $(PRISM_SRCDIR)/templates/template.rb $(PRISM_SRCDIR)/templates/lib/prism/compiler.rb.erb
	$(Q) $(BASERUBY) $(PRISM_SRCDIR)/templates/template.rb lib/prism/compiler.rb $(srcdir)/lib/prism/compiler.rb

main: $(srcdir)/lib/prism/dispatcher.rb
srcs: $(srcdir)/lib/prism/dispatcher.rb
$(srcdir)/lib/prism/dispatcher.rb: $(PRISM_SRCDIR)/config.yml $(PRISM_SRCDIR)/templates/template.rb $(PRISM_SRCDIR)/templates/lib/prism/dispatcher.rb.erb
	$(Q) $(BASERUBY) $(PRISM_SRCDIR)/templates/template.rb lib/prism/dispatcher.rb $(srcdir)/lib/prism/dispatcher.rb

main: $(srcdir)/lib/prism/dsl.rb
srcs: $(srcdir)/lib/prism/dsl.rb
$(srcdir)/lib/prism/dsl.rb: $(PRISM_SRCDIR)/config.yml $(PRISM_SRCDIR)/templates/template.rb $(PRISM_SRCDIR)/templates/lib/prism/dsl.rb.erb
	$(Q) $(BASERUBY) $(PRISM_SRCDIR)/templates/template.rb lib/prism/dsl.rb $(srcdir)/lib/prism/dsl.rb

main: $(srcdir)/lib/prism/inspect_visitor.rb
srcs: $(srcdir)/lib/prism/inspect_visitor.rb
$(srcdir)/lib/prism/inspect_visitor.rb: $(PRISM_SRCDIR)/config.yml $(PRISM_SRCDIR)/templates/template.rb $(PRISM_SRCDIR)/templates/lib/prism/inspect_visitor.rb.erb
	$(Q) $(BASERUBY) $(PRISM_SRCDIR)/templates/template.rb lib/prism/inspect_visitor.rb $(srcdir)/lib/prism/inspect_visitor.rb

main: $(srcdir)/lib/prism/mutation_compiler.rb
srcs: $(srcdir)/lib/prism/mutation_compiler.rb
$(srcdir)/lib/prism/mutation_compiler.rb: $(PRISM_SRCDIR)/config.yml $(PRISM_SRCDIR)/templates/template.rb $(PRISM_SRCDIR)/templates/lib/prism/mutation_compiler.rb.erb
	$(Q) $(BASERUBY) $(PRISM_SRCDIR)/templates/template.rb lib/prism/mutation_compiler.rb $(srcdir)/lib/prism/mutation_compiler.rb

main: $(srcdir)/lib/prism/node.rb
srcs: $(srcdir)/lib/prism/node.rb
$(srcdir)/lib/prism/node.rb: $(PRISM_SRCDIR)/config.yml $(PRISM_SRCDIR)/templates/template.rb $(PRISM_SRCDIR)/templates/lib/prism/node.rb.erb
	$(Q) $(BASERUBY) $(PRISM_SRCDIR)/templates/template.rb lib/prism/node.rb $(srcdir)/lib/prism/node.rb

main: $(srcdir)/lib/prism/reflection.rb
srcs: $(srcdir)/lib/prism/reflection.rb
$(srcdir)/lib/prism/reflection.rb: $(PRISM_SRCDIR)/config.yml $(PRISM_SRCDIR)/templates/template.rb $(PRISM_SRCDIR)/templates/lib/prism/reflection.rb.erb
	$(Q) $(BASERUBY) $(PRISM_SRCDIR)/templates/template.rb lib/prism/reflection.rb $(srcdir)/lib/prism/reflection.rb

main: $(srcdir)/lib/prism/serialize.rb
srcs: $(srcdir)/lib/prism/serialize.rb
$(srcdir)/lib/prism/serialize.rb: $(PRISM_SRCDIR)/config.yml $(PRISM_SRCDIR)/templates/template.rb $(PRISM_SRCDIR)/templates/lib/prism/serialize.rb.erb
	$(Q) $(BASERUBY) $(PRISM_SRCDIR)/templates/template.rb lib/prism/serialize.rb $(srcdir)/lib/prism/serialize.rb

main: $(srcdir)/lib/prism/visitor.rb
srcs: $(srcdir)/lib/prism/visitor.rb
$(srcdir)/lib/prism/visitor.rb: $(PRISM_SRCDIR)/config.yml $(PRISM_SRCDIR)/templates/template.rb $(PRISM_SRCDIR)/templates/lib/prism/visitor.rb.erb
	$(Q) $(BASERUBY) $(PRISM_SRCDIR)/templates/template.rb lib/prism/visitor.rb $(srcdir)/lib/prism/visitor.rb

srcs: prism/api_node.c
prism/api_node.c: $(PRISM_SRCDIR)/config.yml $(PRISM_SRCDIR)/templates/template.rb $(PRISM_SRCDIR)/templates/ext/prism/api_node.c.erb
	$(Q) $(BASERUBY) $(PRISM_SRCDIR)/templates/template.rb ext/prism/api_node.c $@

srcs: prism/ast.h
prism/ast.h: $(PRISM_SRCDIR)/config.yml $(PRISM_SRCDIR)/templates/template.rb $(PRISM_SRCDIR)/templates/include/prism/ast.h.erb
	$(Q) $(BASERUBY) $(PRISM_SRCDIR)/templates/template.rb include/prism/ast.h $@

srcs: prism/diagnostic.c
prism/diagnostic.c: $(PRISM_SRCDIR)/config.yml $(PRISM_SRCDIR)/templates/template.rb $(PRISM_SRCDIR)/templates/src/diagnostic.c.erb
	$(Q) $(BASERUBY) $(PRISM_SRCDIR)/templates/template.rb src/diagnostic.c $@

srcs: prism/diagnostic.h
prism/diagnostic.h: $(PRISM_SRCDIR)/config.yml $(PRISM_SRCDIR)/templates/template.rb $(PRISM_SRCDIR)/templates/include/prism/diagnostic.h.erb
	$(Q) $(BASERUBY) $(PRISM_SRCDIR)/templates/template.rb include/prism/diagnostic.h $@

srcs: prism/node.c
prism/node.c: $(PRISM_SRCDIR)/config.yml $(PRISM_SRCDIR)/templates/template.rb $(PRISM_SRCDIR)/templates/src/node.c.erb
	$(Q) $(BASERUBY) $(PRISM_SRCDIR)/templates/template.rb src/node.c $@

srcs: prism/prettyprint.c
prism/prettyprint.c: $(PRISM_SRCDIR)/config.yml $(PRISM_SRCDIR)/templates/template.rb $(PRISM_SRCDIR)/templates/src/prettyprint.c.erb
	$(Q) $(BASERUBY) $(PRISM_SRCDIR)/templates/template.rb src/prettyprint.c $@

srcs: prism/serialize.c
prism/serialize.c: $(PRISM_SRCDIR)/config.yml $(PRISM_SRCDIR)/templates/template.rb $(PRISM_SRCDIR)/templates/src/serialize.c.erb
	$(Q) $(BASERUBY) $(PRISM_SRCDIR)/templates/template.rb src/serialize.c $@

srcs: prism/token_type.c
prism/token_type.c: $(PRISM_SRCDIR)/config.yml $(PRISM_SRCDIR)/templates/template.rb $(PRISM_SRCDIR)/templates/src/token_type.c.erb
	$(Q) $(BASERUBY) $(PRISM_SRCDIR)/templates/template.rb src/token_type.c $@

EXPORTOBJS    = $(DLNOBJ) \
		localeinit.$(OBJEXT) \
		loadpath.$(OBJEXT) \
		$(COMMONOBJS)

OBJS          = $(EXPORTOBJS) builtin.$(OBJEXT)
ALLOBJS       = $(OBJS) $(MINIOBJS) $(INITOBJS) $(MAINOBJ)

GOLFOBJS      = goruby.$(OBJEXT)

DEFAULT_PRELUDES = $(GEM_PRELUDE)
PRELUDE_SCRIPTS = $(DEFAULT_PRELUDES)
GEM_PRELUDE   =
PRELUDES      = {$(srcdir)}miniprelude.c
GOLFPRELUDES  = golf_prelude.rbbin

SCRIPT_ARGS   =	--dest-dir="$(DESTDIR)" \
		--extout="$(EXTOUT)" \
		--ext-build-dir="./ext" \
		--mflags="$(MFLAGS)" \
		--make-flags="$(MAKEFLAGS)"
EXTMK_ARGS    =	$(SCRIPT_ARGS) --extension $(EXTS) --extstatic $(EXTSTATIC) \
		--make-flags="V=$(V) MINIRUBY='$(MINIRUBY)'" \
		--gnumake=$(gnumake) --extflags="$(EXTLDFLAGS)" \
		--
INSTRUBY      =	$(SUDO) $(INSTRUBY_ENV) $(RUNRUBY) -r./$(arch)-fake $(tooldir)/rbinstall.rb
INSTRUBY_ARGS =	$(SCRIPT_ARGS) \
		--data-mode=$(INSTALL_DATA_MODE) \
		--prog-mode=$(INSTALL_PROG_MODE) \
		--installed-list $(INSTALLED_LIST) \
		--mantype="$(MANTYPE)" \
		$(INSTRUBY_OPTS)
INSTALL_PROG_MODE = 0755
INSTALL_DATA_MODE = 0644

BOOTSTRAPRUBY_COMMAND = $(BOOTSTRAPRUBY) $(BOOTSTRAPRUBY_OPT)
TESTSDIR      = $(srcdir)/test
TOOL_TESTSDIR = $(tooldir)/test
TEST_EXCLUDES = --excludes-dir=$(TESTSDIR)/.excludes --name=!/memory_leak/
TESTWORKDIR   = testwork
TESTOPTS      = $(RUBY_TESTOPTS)

TESTRUN_SCRIPT = $(srcdir)/test.rb

COMPILE_PRELUDE = $(tooldir)/generic_erb.rb $(srcdir)/template/prelude.c.tmpl \
	$(tooldir)/ruby_vm/helpers/c_escape.rb

SHOWFLAGS = $(no_silence:no=showflags)

MAKE_LINK = $(MINIRUBY) -rfileutils -e "include FileUtils::Verbose" \
	  -e "src, dest = ARGV" \
	  -e "exit if File.identical?(src, dest) or cmp(src, dest) rescue nil" \
	  -e "def noraise; yield; rescue; rescue NotImplementedError; end" \
	  -e "noraise {ln_sf('../'*dest.count('/')+src, dest)} or" \
	  -e "noraise {ln(src, dest)} or" \
	  -e "cp(src, dest)"

# For release builds
YJIT_RUSTC_ARGS = --crate-name=yjit \
	--crate-type=staticlib \
	--edition=2021 \
	-g \
	-C lto=thin \
	-C opt-level=3 \
	-C overflow-checks=on \
	'--out-dir=$(CARGO_TARGET_DIR)/release/' \
	'$(top_srcdir)/yjit/src/lib.rs'

ZJIT_RUSTC_ARGS = --crate-name=zjit \
	--crate-type=staticlib \
	--edition=2024 \
	-g \
	-C lto=thin \
	-C opt-level=3 \
	-C overflow-checks=on \
	'--out-dir=$(CARGO_TARGET_DIR)/release/' \
	'$(top_srcdir)/zjit/src/lib.rs'

all: $(SHOWFLAGS) main

main: $(SHOWFLAGS) exts $(ENCSTATIC:static=lib)encs
	@$(NULLCMD)

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
	"	RUSTC = $(RUSTC)" \
	"	YJIT_RUSTC_ARGS = $(YJIT_RUSTC_ARGS)" \
	"	ZJIT_RUSTC_ARGS = $(ZJIT_RUSTC_ARGS)" \
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
$(EXTS_MK): ext/configure-ext.mk $(srcdir)/template/exts.mk.tmpl \
	    $(TIMESTAMPDIR)/$(arch)/.time $(TIMESTAMPDIR)/.RUBYCOMMONDIR.time
	$(Q)$(MAKE) -f ext/configure-ext.mk $(mflags) V=$(V) EXTSTATIC=$(EXTSTATIC) \
		gnumake=$(gnumake) MINIRUBY="$(MINIRUBY)" \
		EXTLDFLAGS="$(EXTLDFLAGS)" srcdir="$(srcdir)"
	$(ECHO) generating makefile $@
	$(Q)$(MINIRUBY) $(tooldir)/generic_erb.rb -o $@ -c \
	    $(srcdir)/template/exts.mk.tmpl --gnumake=$(gnumake) --configure-exts=ext/configure-ext.mk

ext/configure-ext.mk: $(PREP) all-incs $(MKFILES) $(RBCONFIG) $(LIBRUBY) \
		$(srcdir)/template/configure-ext.mk.tmpl
	$(ECHO) generating makefiles $@
	$(Q)$(MAKEDIRS) $(@D)
	$(Q)$(MINIRUBY) $(tooldir)/generic_erb.rb -o $@ -c \
	    $(srcdir)/template/$(@F).tmpl --srcdir="$(srcdir)" \
	    --miniruby="$(MINIRUBY)" --script-args='$(SCRIPT_ARGS)'

configure-ext: $(EXTS_MK)

build-ext: $(EXTS_MK)
	$(Q)$(MAKE) -f $(EXTS_MK) $(mflags) libdir="$(libdir)" LIBRUBY_EXTS=$(LIBRUBY_EXTS) \
	    EXTENCS="$(ENCOBJS)" BASERUBY="$(BASERUBY)" MINIRUBY="$(MINIRUBY)" \
	    $(EXTSTATIC)
	$(Q)$(MAKE) $(EXTS_NOTE)

exts-note: $(EXTS_MK)
	$(Q)$(MAKE) $(EXTS_NOTE)

ext/extinit.c: $(srcdir)/template/extinit.c.tmpl $(PREP)
	$(MAKEDIRS) $(@D)
	$(Q)$(MINIRUBY) $(tooldir)/generic_erb.rb -o $@ -c \
	    $(srcdir)/template/extinit.c.tmpl $(EXTINITS)

prog: program wprogram
programs: $(PROGRAM) $(WPROGRAM) $(arch)-fake.rb

$(PREP): $(MKFILES)

miniruby$(EXEEXT): config.status $(NORMALMAINOBJ) $(MINIOBJS) $(COMMONOBJS) $(ARCHFILE)

objs: $(ALLOBJS)

GORUBY = go$(RUBY_INSTALL_NAME)
GOLF = $(GORUBY)
golf: $(GOLF)
$(GOLF): $(LIBRUBY) $(GOLFOBJS) PHONY
	$(Q) $(MAKE) $(mflags) \
		GOLF=_dummy_golf_target_to_avoid_conflict_just_in_case_ \
		MAINOBJ=goruby.$(OBJEXT) \
		PROGRAM=$(GORUBY)$(EXEEXT) \
		V=$(V) \
	program
capi: $(CAPIOUT)/.timestamp PHONY

$(CAPIOUT)/.timestamp: Doxyfile $(PREP)
	$(Q) $(MAKEDIRS) "$(@D)"
	$(ECHO) generating capi
	-$(Q) $(DOXYGEN) -b
	$(Q) $(MINIRUBY) -e 'File.open(ARGV[0], "w"){'"|f|"' f.puts(Time.now)}' "$@"

Doxyfile: $(srcdir)/template/Doxyfile.tmpl $(PREP) $(tooldir)/generic_erb.rb $(RBCONFIG)
	$(ECHO) generating $@
	$(Q) $(MINIRUBY) $(tooldir)/generic_erb.rb -o $@ $(srcdir)/template/Doxyfile.tmpl \
	--srcdir="$(srcdir)" --miniruby="$(MINIRUBY)"

program: $(SHOWFLAGS) $(DOT_WAIT) $(PROGRAM)
wprogram: $(SHOWFLAGS) $(DOT_WAIT) $(WPROGRAM)
mini: PHONY miniruby$(EXEEXT)

$(PROGRAM) $(WPROGRAM): $(LIBRUBY) $(MAINOBJ) $(OBJS) $(EXTOBJS) $(SETUP) $(PREP)

$(LIBRUBY_A):	$(LIBRUBY_A_OBJS) $(MAINOBJ) $(INITOBJS) $(ARCHFILE)

$(LIBRUBY_SO):	$(OBJS) $(DLDOBJS) $(LIBRUBY_A) $(PREP) $(BUILTIN_ENCOBJS)

$(LIBRUBY_EXTS):
	@$(NULLCMD) > $@

$(STATIC_RUBY)$(EXEEXT): $(MAINOBJ) $(DLDOBJS) $(EXTOBJS) $(LIBRUBY_A)
	$(Q)$(RM) $@
	$(PURIFY) $(CC) $(MAINOBJ) $(DLDOBJS) $(LIBRUBY_A) $(MAINLIBS) $(EXTLIBS) $(LIBS) $(OUTFLAG)$@ $(LDFLAGS) $(XLDFLAGS)

ruby.imp: $(COMMONOBJS)
	$(Q){ \
	$(NM) -Pgp $(COMMONOBJS) | \
	awk 'BEGIN{print "#!"}; $$2~/^[A-TV-Z]$$/&&$$1!~/^$(SYMBOL_PREFIX)(Init_|InitVM_|ruby_static_id_|.*_threadptr_|rb_ec_)|^\./{print $$1}'; \
	} | \
	sort -u -o $@

install: install-$(INSTALLDOC)
docs: srcs-doc $(DOCTARGETS)
pkgconfig-data: $(ruby_pc)
$(ruby_pc): $(srcdir)/template/ruby.pc.in config.status

INSTALL_ALL = all

install-all: pre-install-all do-install-all post-install-all
pre-install-all:: all pre-install-local pre-install-ext pre-install-gem pre-install-doc
do-install-all: pre-install-all $(DOT_WAIT) docs
	$(INSTRUBY) --make="$(MAKE)" $(INSTRUBY_ARGS) --install=$(INSTALL_ALL) $(INSTALL_DOC_OPTS)
post-install-all:: post-install-local post-install-ext post-install-gem post-install-doc
	@$(NULLCMD)

install-nodoc: pre-install-nodoc do-install-nodoc post-install-nodoc
pre-install-nodoc:: pre-install-local pre-install-ext pre-install-gem
do-install-nodoc: main pre-install-nodoc
	$(INSTRUBY) --make="$(MAKE)" $(INSTRUBY_ARGS) --install=$(INSTALL_ALL) --exclude=doc
post-install-nodoc:: post-install-local post-install-ext post-install-gem

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
	$(INSTRUBY) -n --make="$(MAKE)" $(INSTRUBY_ARGS) --install=$(INSTALL_ALL) $(INSTALL_DOC_OPTS)
post-no-install-all:: post-no-install-local post-no-install-ext post-no-install-doc
	@$(NULLCMD)

uninstall: $(INSTALLED_LIST) sudo-precheck
	$(Q)$(SUDO) $(MINIRUBY) $(tooldir)/rbuninstall.rb --destdir=$(DESTDIR) $(INSTALLED_LIST)

reinstall: all uninstall install

what-where-nodoc: no-install-nodoc
no-install-nodoc: pre-no-install-nodoc dont-install-nodoc post-no-install-nodoc
pre-no-install-nodoc:: pre-no-install-local pre-no-install-ext
dont-install-nodoc:  $(PREP)
	$(INSTRUBY) -n --make="$(MAKE)" $(INSTRUBY_ARGS) --exclude=doc
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
pre-install-gem:: prepare-gems pre-install-bin pre-install-lib pre-install-man
do-install-gem: $(PROGRAM) pre-install-gem
	$(INSTRUBY) --make="$(MAKE)" $(INSTRUBY_ARGS) --install=gem
post-install-gem::
	@$(NULLCMD)

install-dbg: pre-install-dbg do-install-dbg post-install-dbg
pre-install-dbg::
do-install-dbg: $(PROGRAM) pre-install-dbg
	$(INSTRUBY) --make="$(MAKE)" $(INSTRUBY_ARGS) --install=dbg
post-install-dbg::
	@$(NULLCMD)

srcs-doc: prepare-gems

rdoc: PHONY main srcs-doc
	@echo Generating RDoc documentation
	$(Q) $(RDOC) --ri --op "$(RDOCOUT)" $(RDOC_GEN_OPTS) $(RDOCFLAGS) .

html: PHONY main srcs-doc
	@echo Generating RDoc HTML files
	$(Q) $(RDOC) --op "$(HTMLOUT)" $(RDOC_GEN_OPTS) $(RDOCFLAGS) .

rdoc-coverage: PHONY main srcs-doc
	@echo Generating RDoc coverage report
	$(Q) $(RDOC) --quiet -C $(RDOCFLAGS) .

undocumented: PHONY main srcs-doc
	$(Q) $(RDOC) --quiet -C $(RDOCFLAGS) . | \
	sed -n \
	-e '/^ *# in file /{' -e 's///;N;s/\n/: /p' -e '}' \
	-e 's/^ *\(.*[^ ]\) *# in file \(.*\)/\2: \1/p' | sort

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

clean: clean-ext clean-enc clean-golf clean-docs clean-extout clean-modular-gc clean-local clean-platform clean-spec
clean-local:: clean-runnable
	$(Q)$(RM) $(ALLOBJS) $(LIBRUBY_A) $(LIBRUBY_SO) $(LIBRUBY) $(LIBRUBY_ALIASES)
	$(Q)$(RM) $(PROGRAM) $(WPROGRAM) miniruby$(EXEEXT) dmyext.$(OBJEXT) dmyenc.$(OBJEXT) $(ARCHFILE) .*.time
	$(Q)$(RM) y.tab.c y.output encdb.h transdb.h config.log rbconfig.rb $(ruby_pc) $(COROUTINE_H:/Context.h=/.time)
	$(Q)$(RM) probes.h probes.$(OBJEXT) probes.stamp ruby-glommed.$(OBJEXT) ruby.imp ChangeLog $(STATIC_RUBY)$(EXEEXT)
	$(Q)$(RM) GNUmakefile.old Makefile.old $(arch)-fake.rb bisect.sh $(ENC_TRANS_D) builtin_binary.rbbin
	$(Q)$(RM) $(PRISM_BUILD_DIR)/.time $(PRISM_BUILD_DIR)/*/.time yjit_exit_locations.dump
	-$(Q)$(RMALL) target
	-$(Q) $(RMDIR) enc/jis enc/trans enc $(COROUTINE_H:/Context.h=) coroutine target \
	  $(PRISM_BUILD_DIR)/*/ $(PRISM_BUILD_DIR) tmp \
	2> $(NULL) || $(NULLCMD)

bin/clean-runnable:: PHONY
	$(Q)$(CHDIR) bin 2>$(NULL) && $(RM) $(PROGRAM) $(WPROGRAM) $(GORUBY)$(EXEEXT) bin/*.$(DLEXT) 2>$(NULL) || $(NULLCMD)
lib/clean-runnable:: PHONY
	$(Q)$(CHDIR) lib 2>$(NULL) && $(RM) $(LIBRUBY_A) $(LIBRUBY) $(LIBRUBY_ALIASES) $(RUBY_BASE_NAME)/$(ruby_version) $(RUBY_BASE_NAME)/vendor_ruby 2>$(NULL) || $(NULLCMD)
clean-runnable:: bin/clean-runnable lib/clean-runnable PHONY
	$(Q)$(RMDIR) lib/$(RUBY_BASE_NAME) lib bin 2>$(NULL) || $(NULLCMD)
	-$(Q)$(RM) $(EXTOUT)/$(arch)/rbconfig.rb $(EXTOUT)/common/$(arch)
	-$(Q)$(RMALL) exe/
clean-ext:: PHONY
clean-golf: PHONY
	$(Q)$(RM) $(GORUBY)$(EXEEXT) $(GOLFOBJS)
clean-rdoc: PHONY
clean-html: PHONY
clean-capi: PHONY
clean-platform: PHONY
clean-extout: PHONY
	-$(Q)$(RMDIR) $(EXTOUT)/$(arch) $(RUBYCOMMONDIR) $(EXTOUT) 2> $(NULL) || $(NULLCMD)
clean-docs: clean-rdoc clean-html clean-capi
clean-spec: PHONY
clean-rubyspec: clean-spec

distclean: distclean-ext distclean-enc distclean-golf distclean-docs distclean-extout distclean-modular-gc distclean-local distclean-platform distclean-spec
distclean-local:: clean-local
	$(Q)$(RM) $(MKFILES) *.inc $(PRELUDES) *.rbinc *.rbbin
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

realclean-srcs-local:: clean-srcs-local
	$(Q)$(CHDIR) $(srcdir) && $(RM) \
	  parse.c parse.h lex.c enc/trans/newline.c $(PRELUDES) revision.h \
	  id.c id.h probes.dmyh configure aclocal.m4 tool/config.guess tool/config.sub gems/*.gem \
	|| $(NULLCMD)

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

clean-ext:: ext/clean .bundle/clean timestamp/clean
distclean-ext:: ext/distclean .bundle/distclean timestamp/distclean
realclean-ext:: ext/realclean .bundle/realclean timestamp/realclean

ext/clean.mk ext/distclean.mk ext/realclean.mk::
ext/clean:: ext/clean.mk
ext/distclean:: ext/distclean.mk
ext/realclean:: ext/realclean.mk

timestamp/clean:: ext/clean .bundle/clean
timestamp/distclean:: ext/distclean .bundle/distclean
timestamp/realclean:: ext/realclean .bundle/realclean

timestamp/clean timestamp/distclean timestamp/realclean::
	$(Q)$(RM) $(TIMESTAMPDIR)/.*.time $(TIMESTAMPDIR)/$(arch)/.time
	$(Q)$(RMDIRS) $(TIMESTAMPDIR)/$(arch) $(TIMESTAMPDIR) 2> $(NULL) || $(NULLCMD)

clean-ext::
	-$(Q)$(RM) ext/extinit.$(OBJEXT)

distclean-ext realclean-ext::
	-$(Q)$(RM) $(EXTS_MK) ext/extinit.* ext/configure-ext.mk
	-$(Q)$(RMDIR) ext 2> $(NULL) || $(NULLCMD)

clean-enc distclean-enc realclean-enc: PHONY

clean-enc: clean-enc.d

clean-enc.d: PHONY
	$(Q)$(RM) $(ENC_TRANS_D)
	-$(Q) $(RMDIR) enc/jis enc/trans enc 2> $(NULL) || $(NULLCMD)

clean-rdoc distclean-rdoc realclean-rdoc:
	@echo $(@:-rdoc=ing) rdoc
	$(Q)$(RMALL) $(RDOCOUT)

clean-html distclean-html realclean-html:
	@echo $(@:-html=ing) HTML
	$(Q)$(RMALL) $(HTMLOUT)

clean-capi distclean-capi realclean-capi:
	@echo $(@:-capi=ing) capi
	$(Q)$(RMALL) $(CAPIOUT)

clean-platform distclean-platform realclean-platform:
	$(Q) $(RM) $(PLATFORM_D)
	-$(Q) $(RMDIR) $(PLATFORM_DIR) 2> $(NULL) || $(NULLCMD)

RUBYSPEC_CAPIEXT = spec/ruby/optional/capi/ext
RUBYSPEC_CAPIEXT_SRCDIR = $(srcdir)/$(RUBYSPEC_CAPIEXT)
RUBYSPEC_CAPIEXT_DEPS = $(RUBYSPEC_CAPIEXT_SRCDIR)/rubyspec.h $(RUBY_H_INCLUDES) $(LIBRUBY)

rubyspec-capiext: build-ext $(DOT_WAIT)
# make-dependent rules should be included after this and built after build-ext.

clean-spec: PHONY
	-$(Q) $(RM) $(RUBYSPEC_CAPIEXT)/*.$(OBJEXT) $(RUBYSPEC_CAPIEXT)/*.$(DLEXT)
	-$(Q) $(RMDIRS) $(RUBYSPEC_CAPIEXT) 2> $(NULL) || $(NULLCMD)
	-$(Q) $(RMALL) rubyspec_temp

check: main $(DOT_WAIT) test $(DOT_WAIT) test-tool $(DOT_WAIT) test-all
	$(ECHO) check succeeded
	-$(Q) : : "run only on sh"; \
	if [ x"$(GIT)" != x ] && $(CHDIR) "$(srcdir)" && \
	    b=`$(GIT) symbolic-ref --short HEAD 2>&1` && \
	    u=`$(GIT) branch --list --format='%(upstream:short)' $$b`; then \
	  set -x; $(GIT) --no-pager log --format=oneline -G '^ *# *include *("|<ruby)' $$u..HEAD --; \
	fi
check-ruby: test test-ruby

fake: $(CROSS_COMPILING)-fake
yes-fake: $(arch)-fake.rb $(RBCONFIG) PHONY
no-fake -fake: PHONY

$(HAVE_BASERUBY:no=)$(arch)-fake.rb: miniruby$(EXEEXT)

# actually depending on other headers more.
$(arch:noarch=ignore)-fake.rb: $(top_srcdir)/revision.h $(top_srcdir)/version.h $(srcdir)/version.c
$(arch:noarch=ignore)-fake.rb: {$(VPATH)}id.h {$(VPATH)}vm_opts.h $(REVISION_H)

$(arch:noarch=ignore)-fake.rb: $(srcdir)/template/fake.rb.in $(tooldir)/generic_erb.rb
	$(ECHO) generating $@
	$(Q) $(CPP) -DRUBY_EXPORT $(INCFLAGS) $(CPPFLAGS) "$(srcdir)/version.c" | \
	$(BOOTSTRAPRUBY) "$(tooldir)/generic_erb.rb" -o $@ "$(srcdir)/template/fake.rb.in" \
	    i=- srcdir="$(srcdir)" BASERUBY="$(BASERUBY)" \
	    LIBPATHENV="$(LIBPATHENV)" PRELOADENV="$(PRELOADENV)" LIBRUBY_SO="$(LIBRUBY_SO)"

noarch-fake.rb: # prerequisite of yes-fake
	$(Q) exit > $@

# runner: BASERUBY, target: miniruby
btest: $(TEST_RUNNABLE)-btest
no-btest: PHONY
yes-btest: yes-fake miniruby$(EXEEXT) PHONY
	$(ACTIONS_GROUP)
	$(Q)$(gnumake_recursive)$(exec) $(BOOTSTRAPRUBY) "$(srcdir)/bootstraptest/runner.rb" --ruby="$(BTESTRUBY) $(RUN_OPTS)" $(OPTS) $(TESTOPTS) $(BTESTS)
	$(ACTIONS_ENDGROUP)

# runner: ruby, target: ruby
btest-ruby: $(TEST_RUNNABLE)-btest-ruby
no-btest-ruby: PHONY
yes-btest-ruby: prog PHONY
	$(ACTIONS_GROUP)
	$(Q)$(gnumake_recursive)$(exec) $(RUNRUBY) "$(srcdir)/bootstraptest/runner.rb" --ruby="$(PROGRAM) -I$(srcdir)/lib $(RUN_OPTS)" $(OPTS) $(TESTOPTS) $(BTESTS)
	$(ACTIONS_ENDGROUP)

# runner: BASERUBY, target: ruby
btest-bruby: prog PHONY
	$(ACTIONS_GROUP)
	$(Q)$(gnumake_recursive)$(exec) $(BOOTSTRAPRUBY) "$(srcdir)/bootstraptest/runner.rb" --ruby="$(PROGRAM) -I$(srcdir)/lib $(RUN_OPTS)" $(OPTS) $(TESTOPTS) $(BTESTS)
	$(ACTIONS_ENDGROUP)

rtest: yes-fake miniruby$(EXEEXT) PHONY
	$(ACTIONS_GROUP)
	$(Q)$(exec) $(BOOTSTRAPRUBY) "$(srcdir)/bootstraptest/runner.rb" --ruby="$(BTESTRUBY) $(RUN_OPTS)" --sets=ractor -v
	$(ACTIONS_ENDGROUP)

test-basic: $(TEST_RUNNABLE)-test-basic
no-test-basic: PHONY
yes-test-basic: prog PHONY
	$(ACTIONS_GROUP)
	$(Q)$(exec) $(RUNRUBY) "$(srcdir)/basictest/runner.rb" --run-opt=$(RUN_OPTS) $(OPTS) $(TESTOPTS)
	$(ACTIONS_ENDGROUP)

test-knownbugs: test-knownbug
test-knownbug: $(TEST_RUNNABLE)-test-knownbug
no-test-knownbug: PHONY
yes-test-knownbug: prog PHONY
	$(ACTIONS_GROUP)
	-$(exec) $(RUNRUBY) "$(srcdir)/bootstraptest/runner.rb" --ruby="$(PROGRAM) $(RUN_OPTS)" $(OPTS) $(TESTOPTS) $(srcdir)/KNOWNBUGS.rb
	$(ACTIONS_ENDGROUP)

test-testframework: $(TEST_RUNNABLE)-test-testframework
yes-test-testframework: prog PHONY
	$(ACTIONS_GROUP)
	$(gnumake_recursive)$(Q)$(exec) $(RUNRUBY) "$(TOOL_TESTSDIR)/runner.rb" --ruby="$(RUNRUBY)" $(TESTOPTS) testunit
	$(ACTIONS_ENDGROUP)
no-test-testframework: PHONY

test-tool: $(TEST_RUNNABLE)-test-tool
yes-test-tool: prog PHONY
	$(ACTIONS_GROUP)
	$(gnumake_recursive)$(Q)$(exec) $(RUNRUBY) "$(TOOL_TESTSDIR)/runner.rb" --ruby="$(RUNRUBY)" $(TESTOPTS)
	$(ACTIONS_ENDGROUP)
no-test-tool: PHONY

test-sample: test-basic # backward compatibility for mswin-build
test-short: btest-ruby $(DOT_WAIT) test-knownbug $(DOT_WAIT) test-basic
test: test-short

# Separate to skip updating encs and exts by `make -o test-precheck`
# for GNU make.
test-precheck: $(ENCSTATIC:static=lib)encs exts PHONY $(DOT_WAIT)
yes-test-all-precheck: programs $(DOT_WAIT) test-precheck

PRECHECK_TEST_ALL = yes-test-all-precheck

# $ make test-all TESTOPTS="--help" displays more detail
# for example, make test-all TESTOPTS="-j2 -v -n test-name -- test-file-name"
test-all: $(TEST_RUNNABLE)-test-all
yes-test-all: $(PRECHECK_TEST_ALL)
	$(ACTIONS_GROUP)
	$(gnumake_recursive)$(Q)$(exec) $(RUNRUBY) -r$(tooldir)/lib/_tmpdir \
	"$(TESTSDIR)/runner.rb" --ruby="$(RUNRUBY)" \
	$(TEST_EXCLUDES) $(TESTOPTS) $(TESTS)
	$(ACTIONS_ENDGROUP)
TESTS_BUILD = mkmf
no-test-all: PHONY
	$(ACTIONS_GROUP)
	$(gnumake_recursive)$(MINIRUBY) -I"$(srcdir)/lib" -r$(tooldir)/lib/_tmpdir \
	"$(TESTSDIR)/runner.rb" $(TESTOPTS) $(TESTS_BUILD)
	$(ACTIONS_ENDGROUP)

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

rbconfig.rb: $(RBCONFIG)

$(HAVE_BASERUBY:no=)$(RBCONFIG)$(HAVE_BASERUBY:no=): $(PREP)
$(RBCONFIG): $(tooldir)/mkconfig.rb config.status $(srcdir)/version.h $(srcdir)/common.mk
	$(Q)$(BOOTSTRAPRUBY) -n \
	-e 'BEGIN{version=ARGV.shift;mis=ARGV.dup}' \
	-e 'END{abort "UNICODE version mismatch: #{mis}" unless mis.empty?}' \
	-e '(mis.delete(ARGF.path); ARGF.close) if /ONIG_UNICODE_VERSION_STRING +"#{Regexp.quote(version)}"/o' \
	$(UNICODE_VERSION) $(UNICODE_DATA_HEADERS)
	$(Q)$(BOOTSTRAPRUBY) $(tooldir)/mkconfig.rb \
		-arch=$(arch) -version=$(RUBY_PROGRAM_VERSION) \
		-install_name=$(RUBY_INSTALL_NAME) \
		-so_name=$(RUBY_SO_NAME) \
		-unicode_version=$(UNICODE_VERSION) \
		-unicode_emoji_version=$(UNICODE_EMOJI_VERSION) \
	> rbconfig.tmp
	$(IFCHANGE) "--timestamp=$@" rbconfig.rb rbconfig.tmp

test-rubyspec: test-spec
yes-test-rubyspec: yes-test-spec

yes-test-spec-precheck: yes-test-all-precheck yes-fake

test-spec: $(TEST_RUNNABLE)-test-spec
yes-test-spec: yes-test-spec-precheck
	$(ACTIONS_GROUP)
	$(gnumake_recursive)$(Q) \
	$(RUNRUBY) -r./$(arch)-fake -r$(tooldir)/lib/_tmpdir \
		$(srcdir)/spec/mspec/bin/mspec run -B $(srcdir)/spec/default.mspec $(MSPECOPT) $(SPECOPTS)
	$(ACTIONS_ENDGROUP)
no-test-spec:

check: $(DOT_WAIT) test-spec

RUNNABLE = $(LIBRUBY_RELATIVE:no=un)-runnable
runnable: $(RUNNABLE)
runnable-golf: golf
runnable $(enable_shared:yes=runnable-golf): prog $(tooldir)/mkrunnable.rb PHONY
	$(Q) $(MINIRUBY) $(tooldir)/mkrunnable.rb -v $(EXTOUT)
yes-runnable: PHONY

hello: $(TEST_RUNNABLE)-hello
yes-hello: runnable-golf
	./$(enable_shared:yes=bin/)$(GORUBY) -veh
no-hello: runnable-golf
	$(ECHO) Run ./$(enable_shared:yes=bin/)$(GORUBY) -veh

encs: enc trans
libencs: libenc libtrans
encs enc trans libencs libenc libtrans: $(SHOWFLAGS) $(ENC_MK) $(LIBRUBY) $(PREP) PHONY
	$(ECHO) making $@
	$(Q) $(MAKE) $(MAKE_ENC) $@


libenc enc: {$(VPATH)}encdb.h
libtrans trans: {$(VPATH)}transdb.h

ENC_HEADERS = $(srcdir)/enc/jis/props.h
# Use MINIRUBY which loads fake.rb for cross compiling
$(ENC_MK): $(srcdir)/enc/make_encmake.rb $(srcdir)/enc/Makefile.in $(srcdir)/enc/depend \
	   $(srcdir)/enc/encinit.c.erb $(ENC_HEADERS) $(srcdir)/lib/mkmf.rb $(RBCONFIG) $(HAVE_BASERUBY)-fake
	$(ECHO) generating $@
	$(Q) $(BOOTSTRAPRUBY_COMMAND) $(srcdir)/enc/make_encmake.rb \
	  --builtin-encs="$(BUILTIN_ENCOBJS)" --builtin-transes="$(BUILTIN_TRANSOBJS)" --module$(ENCSTATIC) $(ENCS) $@

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

{$(VPATH)}parse.c: {$(VPATH)}parse.y {$(VPATH)}id.h
{$(VPATH)}parse.h: {$(VPATH)}parse.c

{$(srcdir)}.y.c:
	$(ECHO) generating $@
	$(Q)$(BASERUBY) $(tooldir)/id2token.rb $(SRC_FILE) | \
	$(LRAMA) $(YFLAGS) -o$@ -H$*.h - parse.y

$(PLATFORM_D):
	$(Q) $(MAKEDIRS) $(PLATFORM_DIR) $(@D)
	@$(NULLCMD) > $@

exe/$(PROGRAM): $(TIMESTAMPDIR)/$(arch)/.time
exe/$(PROGRAM): ruby-runner.c ruby-runner.h exe/.time $(PREP) {$(VPATH)}config.h
	$(Q) $(CC) $(CFLAGS) $(INCFLAGS) $(CPPFLAGS) -DRUBY_INSTALL_NAME=$(@F) $(COUTFLAG)ruby-runner.$(OBJEXT) -c $(CSRCFLAG)$(srcdir)/ruby-runner.c
	$(Q) $(PURIFY) $(CC) $(CFLAGS) $(LDFLAGS) $(OUTFLAG)$@ ruby-runner.$(OBJEXT) $(LIBS)
	$(Q) $(POSTLINK)
	$(Q) $(BOOTSTRAPRUBY) \
	    -e 'prog, dest, inst = ARGV; dest += "/ruby"' \
	    -e 'exit unless prog==inst' \
	    -e 'unless prog=="ruby"' \
	    -e '  begin File.unlink(dest); rescue Errno::ENOENT; end' \
	    -e '  File.symlink(prog, dest)' \
	    -e 'end' \
	$(@F) $(@D) $(RUBY_INSTALL_NAME)$(EXEEXT)
	$(Q) $(BOOTSTRAPRUBY) -r$(srcdir)/lib/fileutils \
	    -e 'FileUtils::Verbose.ln_sr(*ARGV, force: true)' rbconfig.rb $(EXTOUT)/$(arch)

exe/.time:
	$(Q) $(MAKEDIRS) $(@D)
	@$(NULLCMD) > $@

$(BUILTIN_ENCOBJS) $(BUILTIN_TRANSOBJS): $(ENC_TRANS_D)

$(ENC_TRANS_D):
	$(Q) $(MAKEDIRS) enc/trans $(@D)
	@$(NULLCMD) > $@

$(TIMESTAMPDIR)/$(arch)/.time:
	$(Q)$(MAKEDIRS) $(@D) $(EXTOUT)/$(arch)
	@$(NULLCMD) > $@

$(TIMESTAMPDIR)/.RUBYCOMMONDIR.time:
	$(Q)$(MAKEDIRS) $(@D) $(RUBYCOMMONDIR)
	@$(NULLCMD) > $@

###
CCAN_DIR = {$(VPATH)}ccan

RUBY_H_INCLUDES    = {$(VPATH)}ruby.h {$(VPATH)}config.h {$(VPATH)}defines.h \
		     {$(VPATH)}intern.h {$(VPATH)}missing.h {$(VPATH)}st.h \
		     {$(VPATH)}assert.h {$(VPATH)}subst.h

###

acosh.$(OBJEXT): {$(VPATH)}acosh.c
alloca.$(OBJEXT): {$(VPATH)}alloca.c {$(VPATH)}config.h
cbrt.$(OBJEXT): {$(VPATH)}cbrt.c
close.$(OBJEXT): {$(VPATH)}close.c
crypt.$(OBJEXT): {$(VPATH)}crypt.c {$(VPATH)}crypt.h {$(VPATH)}missing/des_tables.c
erf.$(OBJEXT): {$(VPATH)}erf.c
explicit_bzero.$(OBJEXT): {$(VPATH)}explicit_bzero.c
ffs.$(OBJEXT): {$(VPATH)}ffs.c
flock.$(OBJEXT): {$(VPATH)}flock.c
hypot.$(OBJEXT): {$(VPATH)}hypot.c
langinfo.$(OBJEXT): {$(VPATH)}langinfo.c
lgamma_r.$(OBJEXT): {$(VPATH)}lgamma_r.c
memcmp.$(OBJEXT): {$(VPATH)}memcmp.c
memmove.$(OBJEXT): {$(VPATH)}memmove.c
nan.$(OBJEXT): {$(VPATH)}nan.c
nextafter.$(OBJEXT): {$(VPATH)}nextafter.c
procstat_vm.$(OBJEXT): {$(VPATH)}procstat_vm.c
setproctitle.$(OBJEXT): {$(VPATH)}setproctitle.c
strchr.$(OBJEXT): {$(VPATH)}strchr.c
strerror.$(OBJEXT): {$(VPATH)}strerror.c
strlcat.$(OBJEXT): {$(VPATH)}strlcat.c
strlcpy.$(OBJEXT): {$(VPATH)}strlcpy.c
strstr.$(OBJEXT): {$(VPATH)}strstr.c
tgamma.$(OBJEXT): {$(VPATH)}tgamma.c

.coroutine_obj $(COROUTINE_OBJ): \
	{$(VPATH)}$(COROUTINE_SRC) \
	$(COROUTINE_H:/Context.h=/.time)
$(COROUTINE_H:/Context.h=/.time):
	$(Q) $(MAKEDIRS) $(@D)
	@$(NULLCMD) > $@

###

# dependencies for generated C sources.
parse.$(OBJEXT): {$(VPATH)}parse.c
miniprelude.$(OBJEXT): {$(VPATH)}miniprelude.c

# dependencies for optional sources.
compile.$(OBJEXT): {$(VPATH)}optunifs.inc

win32/win32.$(OBJEXT): {$(VPATH)}win32/win32.c {$(VPATH)}win32/file.h \
  {$(VPATH)}dln.h {$(VPATH)}dln_find.c {$(VPATH)}encindex.h \
  {$(VPATH)}internal.h {$(VPATH)}util.h $(RUBY_H_INCLUDES) \
  {$(VPATH)}vm.h $(PLATFORM_D)
win32/file.$(OBJEXT): {$(VPATH)}win32/file.c {$(VPATH)}win32/file.h \
  $(RUBY_H_INCLUDES) $(PLATFORM_D)

$(NEWLINE_C): $(srcdir)/enc/trans/newline.trans $(tooldir)/transcode-tblgen.rb
	$(Q) $(MAKEDIRS) $(@D)
	$(Q) $(BASERUBY) "$(tooldir)/transcode-tblgen.rb" -vo $@ $(srcdir)/enc/trans/newline.trans
enc/trans/newline.$(OBJEXT): $(NEWLINE_C)

verconf.h: $(srcdir)/template/verconf.h.tmpl $(tooldir)/generic_erb.rb $(RBCONFIG)
	$(ECHO) creating $@
	$(Q) $(BOOTSTRAPRUBY) "$(tooldir)/generic_erb.rb" -o $@ $(srcdir)/template/verconf.h.tmpl

ruby-glommed.$(OBJEXT): $(OBJS)

$(OBJS):  {$(VPATH)}config.h {$(VPATH)}missing.h

INSNS2VMOPT = --srcdir="$(srcdir)"

srcs_vpath = {$(VPATH)}

inc_common_headers = $(tooldir)/ruby_vm/views/_copyright.erb $(tooldir)/ruby_vm/views/_notice.erb
$(srcs_vpath)optinsn.inc: $(tooldir)/ruby_vm/views/optinsn.inc.erb $(inc_common_headers)
$(srcs_vpath)optunifs.inc: $(tooldir)/ruby_vm/views/optunifs.inc.erb $(inc_common_headers)
$(srcs_vpath)insns.inc: $(tooldir)/ruby_vm/views/insns.inc.erb $(inc_common_headers)
$(srcs_vpath)insns_info.inc: $(tooldir)/ruby_vm/views/insns_info.inc.erb $(inc_common_headers) \
  $(tooldir)/ruby_vm/views/_insn_type_chars.erb $(tooldir)/ruby_vm/views/_insn_name_info.erb \
  $(tooldir)/ruby_vm/views/_insn_len_info.erb $(tooldir)/ruby_vm/views/_insn_operand_info.erb \
  $(tooldir)/ruby_vm/views/_attributes.erb $(tooldir)/ruby_vm/views/_comptime_insn_stack_increase.erb \
  $(tooldir)/ruby_vm/views/_zjit_helpers.erb
$(srcs_vpath)vmtc.inc: $(tooldir)/ruby_vm/views/vmtc.inc.erb $(inc_common_headers)
$(srcs_vpath)vm.inc: $(tooldir)/ruby_vm/views/vm.inc.erb $(inc_common_headers) \
  $(tooldir)/ruby_vm/views/_insn_entry.erb $(tooldir)/ruby_vm/views/_trace_instruction.erb \
  $(tooldir)/ruby_vm/views/_zjit_instruction.erb

BUILTIN_RB_SRCS = \
		$(srcdir)/ast.rb \
		$(srcdir)/dir.rb \
		$(srcdir)/gc.rb \
		$(srcdir)/numeric.rb \
		$(srcdir)/io.rb \
		$(srcdir)/marshal.rb \
		$(srcdir)/pack.rb \
		$(srcdir)/trace_point.rb \
		$(srcdir)/warning.rb \
		$(srcdir)/array.rb \
		$(srcdir)/hash.rb \
		$(srcdir)/kernel.rb \
		$(srcdir)/pathname_builtin.rb \
		$(srcdir)/ractor.rb \
		$(srcdir)/symbol.rb \
		$(srcdir)/timev.rb \
		$(srcdir)/thread_sync.rb \
		$(srcdir)/nilclass.rb \
		$(srcdir)/prelude.rb \
		$(srcdir)/gem_prelude.rb \
		$(srcdir)/jit_hook.rb \
		$(srcdir)/jit_undef.rb \
		$(srcdir)/yjit.rb \
		$(srcdir)/zjit.rb \
		$(empty)
BUILTIN_RB_INCS = $(BUILTIN_RB_SRCS:.rb=.rbinc)

common-srcs: $(srcs_vpath)parse.c $(srcs_vpath)lex.c $(srcs_vpath)enc/trans/newline.c $(srcs_vpath)id.c \
	     $(BUILTIN_RB_INCS) \
	     srcs-lib srcs-ext incs preludes

missing-srcs: $(srcdir)/missing/des_tables.c

srcs: common-srcs missing-srcs srcs-enc srcs-doc

RIPPER_SRCS = $(srcdir)/ext/ripper/ripper.c \
	      $(srcdir)/ext/ripper/ripper_init.c \
	      $(srcdir)/ext/ripper/eventids1.h \
	      $(srcdir)/ext/ripper/eventids1.c \
	      $(srcdir)/ext/ripper/eventids2table.c \
	      # RIPPER_SRCS

EXT_SRCS = ripper_srcs \
	   $(srcdir)/ext/rbconfig/sizeof/sizes.c \
	   $(srcdir)/ext/rbconfig/sizeof/limits.c \
	   $(srcdir)/ext/socket/constdefs.c \
	   $(srcdir)/ext/etc/constdefs.h \
	   # EXT_SRCS

srcs-ext: $(EXT_SRCS)
realclean-srcs-ext::
	$(Q)$(RM) $(EXT_SRCS)

EXTRA_SRCS = \
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

all-incs: incs {$(VPATH)}encdb.h {$(VPATH)}transdb.h {$(VPATH)}probes.h
incs: $(INSNS) {$(VPATH)}node_name.inc {$(VPATH)}known_errors.inc \
      {$(VPATH)}vm_call_iseq_optimized.inc $(srcdir)/revision.h \
      $(REVISION_H) \
      $(UNICODE_DATA_HEADERS) $(ENC_HEADERS) \
      $(srcs_vpath)prism/ast.h $(srcs_vpath)prism/diagnostic.h \
      {$(VPATH)}id.h {$(VPATH)}probes.dmyh

insns: $(INSNS)

id.h: $(tooldir)/generic_erb.rb $(srcdir)/template/id.h.tmpl $(srcdir)/defs/id.def
	$(ECHO) generating $@
	$(Q) $(BASERUBY) $(tooldir)/generic_erb.rb --output=$@ \
		$(srcdir)/template/id.h.tmpl

id.c: $(tooldir)/generic_erb.rb $(srcdir)/template/id.c.tmpl $(srcdir)/defs/id.def
	$(ECHO) generating $@
	$(Q) $(BASERUBY) $(tooldir)/generic_erb.rb --output=$@ \
		$(srcdir)/template/id.c.tmpl

node_name.inc: $(tooldir)/node_name.rb $(srcdir)/rubyparser.h
	$(ECHO) generating $@
	$(Q) $(BASERUBY) -n $(tooldir)/node_name.rb < $(srcdir)/rubyparser.h > $@

encdb.h: $(RBCONFIG) $(tooldir)/generic_erb.rb $(srcdir)/template/encdb.h.tmpl
	$(ECHO) generating $@
	$(Q) $(BOOTSTRAPRUBY) $(tooldir)/generic_erb.rb -c -o $@ $(srcdir)/template/encdb.h.tmpl $(srcdir)/enc enc

transdb.h: $(RBCONFIG) srcs-enc $(tooldir)/generic_erb.rb $(srcdir)/template/transdb.h.tmpl
	$(ECHO) generating $@
	$(Q) $(BOOTSTRAPRUBY) $(tooldir)/generic_erb.rb -c -o $@ $(srcdir)/template/transdb.h.tmpl $(srcdir)/enc/trans enc/trans

enc/encinit.c: $(ENC_MK) $(srcdir)/enc/encinit.c.erb

known_errors.inc: $(srcdir)/template/known_errors.inc.tmpl $(srcdir)/defs/known_errors.def
	$(ECHO) generating $@
	$(Q) $(BASERUBY) $(tooldir)/generic_erb.rb -c -o $@ $(srcdir)/template/known_errors.inc.tmpl $(srcdir)/defs/known_errors.def

vm_call_iseq_optimized.inc: $(srcdir)/template/call_iseq_optimized.inc.tmpl
	$(ECHO) generating $@
	$(Q) $(BASERUBY) $(tooldir)/generic_erb.rb -c -o $@ $(srcdir)/template/call_iseq_optimized.inc.tmpl

$(MINIPRELUDE_C): $(COMPILE_PRELUDE) $(BUILTIN_RB_SRCS)
	$(ECHO) generating $@
	$(Q) $(BASERUBY) $(tooldir)/generic_erb.rb -I$(srcdir) -o $@ \
		$(srcdir)/template/prelude.c.tmpl $(BUILTIN_RB_SRCS)

golf_prelude.rbbin: {$(srcdir)}golf_prelude.rb $(tooldir)/mk_rbbin.rb $(PREP)

MAINCPPFLAGS = $(ENABLE_DEBUG_ENV:yes=-DRUBY_DEBUG_ENV=1)

$(MAINOBJ): $(srcdir)/$(MAINSRC)
	$(ECHO) compiling $(srcdir)/$(MAINSRC)
	$(Q) $(CC) $(MAINCPPFLAGS) $(CFLAGS) $(XCFLAGS) $(CPPFLAGS) $(COUTFLAG)$@ -c $(CSRCFLAG)$(srcdir)/$(MAINSRC)

{$(VPATH)}probes.dmyh: {$(srcdir)}probes.d $(tooldir)/gen_dummy_probes.rb

probes.dmyh:
	$(BASERUBY) $(tooldir)/gen_dummy_probes.rb $(srcdir)/probes.d > $@

probes.h: {$(VPATH)}probes.$(DTRACE_EXT)

prereq: incs srcs preludes PHONY

preludes: {$(VPATH)}miniprelude.c

{$(srcdir)}.rb.rbbin:
	$(ECHO) making $@
	$(Q) $(MINIRUBY) $(tooldir)/mk_rbbin.rb $(SRC_FILE) > $(OS_DEST_FILE)

{$(srcdir)}.rb.rbinc:
	$(ECHO) making $@
	$(Q) $(BASERUBY) $(tooldir)/mk_builtin_loader.rb $(SRC_FILE)

$(BUILTIN_BINARY:yes=built)in_binary.rbbin: $(PREP) $(BUILTIN_RB_SRCS) $(srcdir)/template/builtin_binary.rbbin.tmpl
	$(Q) $(MINIRUBY) $(tooldir)/generic_erb.rb -o $@ \
		$(srcdir)/template/builtin_binary.rbbin.tmpl
	-$(Q) sha256sum $@ 2> $(NULL) || $(NULLCMD)

$(BUILTIN_BINARY:no=builtin)_binary.rbbin:
	$(Q) echo> $@ // empty $(@F)

$(BUILTIN_RB_INCS): $(top_srcdir)/tool/mk_builtin_loader.rb

$(srcdir)/revision.h$(no_baseruby:no=~disabled~): $(REVISION_H)

$(REVISION_H)$(no_baseruby:no=~disabled~):
	$(Q) $(BASERUBY) $(tooldir)/file2lastrev.rb -q --revision.h --srcdir="$(srcdir)" --output=revision.h --timestamp=$@
$(REVISION_H)$(yes_baseruby:yes=~disabled~):
	$(Q) exit > $@

# uncommon.mk: $(REVISION_H)
# $(MKFILES): $(REVISION_H)

ripper_srcs: $(RIPPER_SRCS)

$(RIPPER_SRCS): $(srcdir)/parse.y $(srcdir)/defs/id.def
$(RIPPER_SRCS): $(srcdir)/ext/ripper/tools/preproc.rb $(srcdir)/ext/ripper/tools/dsl.rb
$(RIPPER_SRCS): $(srcdir)/ext/ripper/ripper_init.c.tmpl $(srcdir)/ext/ripper/eventids2.c
	$(ECHO) generating $@
	$(Q) $(CHDIR) $(@D) && \
	$(CAT_DEPEND) depend | \
	$(exec) $(MAKE) -f - $(mflags) \
		Q=$(Q) ECHO=$(ECHO) RM="$(RM1)" top_srcdir=../.. srcdir=. VPATH=../.. \
		RUBY="$(BASERUBY)" BASERUBY="$(BASERUBY)" PATH_SEPARATOR="$(PATH_SEPARATOR)" LANG=C

$(srcdir)/ext/date/zonetab.h: $(srcdir)/ext/date/zonetab.list $(srcdir)/ext/date/prereq.mk
	$(ECHO) generating $@
	$(Q) $(CHDIR) $(@D) && $(exec) $(MAKE) -f prereq.mk $(mflags) \
		Q=$(Q) ECHO=$(ECHO) top_srcdir=../.. srcdir=. VPATH=../.. BASERUBY="$(BASERUBY)"

$(srcdir)/ext/rbconfig/sizeof/sizes.c: $(srcdir)/ext/rbconfig/sizeof/depend \
		$(tooldir)/generic_erb.rb $(srcdir)/template/sizes.c.tmpl $(srcdir)/configure.ac
	$(ECHO) generating $@
	$(Q) $(CHDIR) $(@D) && \
	$(CAT_DEPEND) depend | \
	$(exec) $(MAKE) -f - $(mflags) \
		Q=$(Q) ECHO=$(ECHO) top_srcdir=../../.. srcdir=. VPATH=../../.. RUBY="$(BASERUBY)" $(@F)

$(srcdir)/ext/rbconfig/sizeof/limits.c: $(srcdir)/ext/rbconfig/sizeof/depend \
		$(tooldir)/generic_erb.rb $(srcdir)/template/limits.c.tmpl
	$(ECHO) generating $@
	$(Q) $(CHDIR) $(@D) && \
	$(CAT_DEPEND) depend | \
	$(exec) $(MAKE) -f - $(mflags) \
		Q=$(Q) ECHO=$(ECHO) top_srcdir=../../.. srcdir=. VPATH=../../.. RUBY="$(BASERUBY)" $(@F)

$(srcdir)/ext/socket/constdefs.c: $(srcdir)/ext/socket/depend $(srcdir)/ext/socket/mkconstants.rb
	$(Q) $(CHDIR) $(@D) && \
	$(CAT_DEPEND) depend | \
	$(exec) $(MAKE) -f - $(mflags) \
		Q=$(Q) ECHO=$(ECHO) top_srcdir=../.. srcdir=. VPATH=../.. RUBY="$(BASERUBY)"

$(srcdir)/ext/etc/constdefs.h: $(srcdir)/ext/etc/depend
	$(Q) $(CHDIR) $(@D) && \
	$(CAT_DEPEND) depend | \
	$(exec) $(MAKE) -f - $(mflags) \
		Q=$(Q) ECHO=$(ECHO) top_srcdir=../.. srcdir=. VPATH=../.. RUBY="$(BASERUBY)"

##

run: yes-fake miniruby$(EXEEXT) PHONY
	$(BTESTRUBY) $(RUNOPT0) $(TESTRUN_SCRIPT) $(RUNOPT)

runruby: $(PROGRAM) PHONY
	RUBY_ON_BUG='gdb -x $(srcdir)/.gdbinit -p' $(RUNRUBY) $(RUNOPT0) $(TESTRUN_SCRIPT) $(RUNOPT)

runirb: $(PROGRAM) update-default-gemspecs
	RUBY_ON_BUG='gdb -x $(srcdir)/.gdbinit -p' $(RUNRUBY) $(RUNOPT0) -rrubygems -r irb -e 'IRB.start("make runirb")' $(RUNOPT)

parse: yes-fake miniruby$(EXEEXT) PHONY
	$(BTESTRUBY) --dump=parsetree_with_comment,insns $(TESTRUN_SCRIPT)

bisect: PHONY
	$(tooldir)/bisect.sh miniruby $(srcdir)

bisect-ruby: PHONY
	$(tooldir)/bisect.sh ruby $(srcdir)

COMPARE_RUBY = $(BASERUBY)
BENCH_RUBY = $(RUNRUBY)
BENCH_OPTS = --output=markdown --output-compare -v
ITEM =
ARGS = $$(find $(srcdir)/benchmark -maxdepth 1 -name '$(ITEM)' -o -name '*$(ITEM)*.yml' -o -name '*$(ITEM)*.rb' | sort)
OPTS =

# See benchmark/README.md for details.
benchmark: miniruby$(EXEEXT) update-benchmark-driver PHONY
	$(BASERUBY) -rrubygems -I$(srcdir)/benchmark/lib $(srcdir)/benchmark/benchmark-driver/exe/benchmark-driver \
	            --executables="compare-ruby::$(COMPARE_RUBY) -I$(EXTOUT)/common --disable-gem" \
	            --executables="built-ruby::$(BENCH_RUBY) --disable-gem" \
	            $(BENCH_OPTS) $(ARGS) $(OPTS)

run.gdb:
	echo set breakpoint pending on         > run.gdb
	echo b rb_assert_failure              >> run.gdb
	echo b rb_bug                         >> run.gdb
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

GDB = gdb

gdb: miniruby$(EXEEXT) run.gdb PHONY
	$(GDB) -x run.gdb --quiet --args $(MINIRUBY) $(RUNOPT0) $(TESTRUN_SCRIPT) $(RUNOPT)

gdb-ruby: $(PROGRAM) run.gdb PHONY
	$(Q) $(RUNRUBY_COMMAND) $(RUNRUBY_DEBUGGER) -- $(RUNOPT0) $(TESTRUN_SCRIPT) $(RUNOPT)

LLDB_INIT = command script import -r $(srcdir)/misc/lldb_cruby.py

lldb: miniruby$(EXEEXT) PHONY
	lldb -o '$(LLDB_INIT)' miniruby$(EXEEXT) -- $(RUNOPT0) $(TESTRUN_SCRIPT) $(RUNOPT)

lldb-ruby: $(PROGRAM) PHONY
	lldb $(enable_shared:yes=-o 'target modules add ${LIBRUBY_SO}') -o '$(LLDB_INIT)' $(PROGRAM) -- $(RUNOPT0) $(TESTRUN_SCRIPT) $(RUNOPT)

DISTPKGS = gzip,zip,all
PKGSDIR = tmp
dist:
	$(BASERUBY) $(V0:1=-v) $(tooldir)/make-snapshot \
	-srcdir=$(srcdir) -packages=$(DISTPKGS) \
	-unicode-version=$(UNICODE_VERSION) \
	$(DISTOPTS) $(PKGSDIR) $(RELNAME)

up:: update-remote

up$(DOT_WAIT)::
	-$(Q)$(MAKE) $(mflags) Q=$(Q) REVISION_FORCE=PHONY ALWAYS_UPDATE_UNICODE= after-update

yes::
no::

after-update:: common-srcs
after-update:: $(REVISION_H)
after-update:: extract-extlibs
after-update:: extract-gems

update-src::
	$(Q) $(RM) $(REVISION_H) revision.h "$(srcdir)/$(REVISION_H)" "$(srcdir)/revision.h"
	$(Q) exit > "$(srcdir)/revision.h"

update-remote:: update-src update-download
update-download:: $(ALWAYS_UPDATE_UNICODE:yes=update-unicode)
update-download:: update-gems
update-download:: download-extlibs

update-mspec:
update-rubyspec:

update-config_files: PHONY
	$(Q) $(BASERUBY) -C "$(srcdir)" tool/downloader.rb -d tool --cache-dir=$(CACHE_DIR) -e gnu \
	    config.guess config.sub

update-coverage: main PHONY
	$(XRUBY) -C "$(srcdir)" bin/gem install --no-document \
		--install-dir .bundle --conservative "simplecov"

refresh-gems: update-bundled_gems prepare-gems
# can't recall exactly, but `make` somewhere (not GNU or nmake)
# couldn't handle spaces in replacement strings; i.e.,
# `$(HAVE_BASERUBY:yes=word word ...)` didn't work.
prepare-gems: $(HAVE_BASERUBY:yes=update-gems) $(HAVE_BASERUBY:yes=extract-gems)
extract-gems: $(HAVE_BASERUBY:yes=update-gems) $(HAVE_BASERUBY:yes=outdate-bundled-gems)
update-gems: $(HAVE_BASERUBY:yes=outdate-bundled-gems)

split_option = -F"\s+|$(HASH_SIGN).*"

update-gems$(sequential): PHONY
	$(ECHO) Downloading bundled gem files...
	$(Q) $(BASERUBY) -C "$(srcdir)" \
	    -I./tool -rdownloader $(split_option) -answ \
	    -e 'gem, ver = *$$F' \
	    -e 'next if !ver' \
	    -e 'old = Dir.glob("gems/#{gem}-*.gem")' \
	    -e 'gem = "#{gem}-#{ver}.gem"' \
	    -e 'Downloader::RubyGems.download(gem, "gems", nil) and' \
	    -e '(old.delete("gems/#{gem}"); !old.empty?) and' \
	    -e 'File.unlink(*old) and' \
	    -e 'FileUtils.rm_rf(old.map{'"|n|"'n.chomp(".gem")})' \
	    gems/bundled_gems

extract-gems$(sequential): PHONY
	$(ECHO) Extracting bundled gem files...
	$(Q) $(BASERUBY) -C "$(srcdir)" \
	    -Itool/lib -rfileutils -rbundled_gem $(split_option) -answ \
	    -e 'BEGIN {d = ".bundle/gems"}' \
	    -e 'gem, ver, _, rev = *$$F' \
	    -e 'next if !ver' \
	    -e 'g = "#{gem}-#{ver}"' \
	    -e 'unless File.directory?("#{d}/#{g}")' \
	    -e   'if rev and File.exist?(gs = "gems/src/#{gem}/#{gem}.gemspec")' \
	    -e     'BundledGem.build(gs, ver, "gems")' \
	    -e   'end' \
	    -e   'BundledGem.unpack("gems/#{g}.gem", ".bundle")' \
	    -e 'end' \
	    gems/bundled_gems

extract-gems$(sequential): $(HAVE_GIT:yes=clone-bundled-gems-src)

flush-gems: outdate-bundled-gems
outdate-bundled-gems: PHONY
	$(Q) $(BASERUBY) $(tooldir)/$@.rb --make="$(MAKE)" --mflags="$(MFLAGS)" \
	--ruby-platform=$(arch) --ruby-version=$(ruby_version) \
	"$(srcdir)"

update-bundled_gems: PHONY
	$(Q) $(RUNRUBY) -rrubygems \
	     $(tooldir)/update-bundled_gems.rb \
	     "$(srcdir)/gems/bundled_gems" | \
	$(IFCHANGE) "$(srcdir)/gems/bundled_gems" -
	$(GIT) -C "$(srcdir)" diff --no-ext-diff --ignore-submodules --exit-code || \
	$(GIT) -C "$(srcdir)" commit -m "Update bundled_gems" gems/bundled_gems

PRECHECK_BUNDLED_GEMS = yes
test-bundled-gems-precheck: $(TEST_RUNNABLE)-test-bundled-gems-precheck
yes-test-bundled-gems-precheck: $(PRECHECK_BUNDLED_GEMS:yes=main)
no-test-bundled-gems-precheck:

update-default-gemspecs: $(TEST_RUNNABLE)-update-default-gemspecs
no-update-default-gemspecs:
yes-update-default-gemspecs: $(PRECHECK_BUNDLED_GEMS:yes=main)
	@$(MAKEDIRS) $(srcdir)/.bundle/specifications
	@$(XRUBY) -W0 -C "$(srcdir)" -rrubygems \
	    -e "destdir = ARGV.shift" \
	    -e "ARGV.each do |basedir|" \
	    -e   "Dir.glob(basedir+'/**/*.gemspec') do |g|" \
	    -e     "dir, base = File.split(g)" \
	    -e     "spec = Dir.chdir(dir) {Gem::Specification.load(base)} ||" \
	    -e         "Gem::Specification.load(g)" \
	    -e     "unless spec" \
	    -e       "puts %[Ignoring #{g}]" \
	    -e       "next" \
	    -e     "end" \
	    -e     "spec.files.clear" \
	    -e     "spec.extensions.clear" \
	    -e     "File.binwrite(File.join(destdir, spec.full_name+'.gemspec'), spec.to_ruby)" \
	    -e   "end" \
	    -e "end" \
	    -- .bundle/specifications lib ext

install-for-test-bundled-gems: $(TEST_RUNNABLE)-install-for-test-bundled-gems
no-install-for-test-bundled-gems: no-update-default-gemspecs
yes-install-for-test-bundled-gems: yes-update-default-gemspecs
	$(XRUBY) -C "$(srcdir)" -r./tool/lib/gem_env.rb bin/gem \
		install --no-document --conservative \
		"hoe" "json-schema:5.1.0" "test-unit-rr" "simplecov" "simplecov-html" "simplecov-json" "rspec" "zeitwerk" \
		"sinatra" "rack" "tilt" "mustermann" "base64" "compact_index" "rack-test" "logger" "kpeg" "tracer"

test-bundled-gems-fetch: yes-test-bundled-gems-fetch
yes-test-bundled-gems-fetch: clone-bundled-gems-src
clone-bundled-gems-src: PHONY
	$(Q) $(BASERUBY) -C $(srcdir) tool/fetch-bundled_gems.rb BUNDLED_GEMS="$(BUNDLED_GEMS)" gems/src gems/bundled_gems
no-test-bundled-gems-fetch:

test-bundled-gems-prepare: $(TEST_RUNNABLE)-test-bundled-gems-prepare
no-test-bundled-gems-prepare: no-test-bundled-gems-precheck no-test-bundled-gems-fetch
Preparing-test-bundled-gems:
	$(ACTIONS_GROUP)
yes-test-bundled-gems-prepare: Preparing-test-bundled-gems $(DOT_WAIT)
	$(ACTIONS_ENDGROUP)
yes-test-bundled-gems-prepare: yes-test-bundled-gems-precheck $(DOT_WAIT)
yes-test-bundled-gems-prepare: yes-install-for-test-bundled-gems $(DOT_WAIT)
yes-test-bundled-gems-prepare: yes-test-bundled-gems-fetch $(DOT_WAIT)
yes-test-bundled-gems-precheck: Preparing-test-bundled-gems
yes-install-for-test-bundled-gems: Preparing-test-bundled-gems
yes-test-bundled-gems-fetch: Preparing-test-bundled-gems

PREPARE_BUNDLED_GEMS = test-bundled-gems-prepare
test-bundled-gems: $(TEST_RUNNABLE)-test-bundled-gems $(DOT_WAIT) $(TEST_RUNNABLE)-test-bundled-gems-spec
yes-test-bundled-gems: test-bundled-gems-run
no-test-bundled-gems:

bundled_gems_spec-run: install-for-test-bundled-gems
	$(XRUBY) -C $(srcdir) .bundle/bin/rspec spec/bundled_gems_spec.rb

# Override this to allow failure of specific gems on CI
# TEST_BUNDLED_GEMS_ALLOW_FAILURES =

BUNDLED_GEMS =
test-bundled-gems-run: $(TEST_RUNNABLE)-test-bundled-gems-run
yes-test-bundled-gems-run: $(PREPARE_BUNDLED_GEMS)
	$(gnumake_recursive)$(Q) $(XRUBY) $(tooldir)/test-bundled-gems.rb $(BUNDLED_GEMS)
no-test-bundled-gems-run: $(PREPARE_BUNDLED_GEMS)

test-bundled-gems-spec: $(TEST_RUNNABLE)-test-bundled-gems-spec
yes-test-bundled-gems-spec: yes-test-spec-precheck $(PREPARE_BUNDLED_GEMS)
	$(ACTIONS_GROUP)
	$(gnumake_recursive)$(Q) \
	$(RUNRUBY) -r./$(arch)-fake -r$(tooldir)/lib/_tmpdir \
		$(srcdir)/spec/mspec/bin/mspec run --env BUNDLED_GEMS=$(BUNDLED_GEMS) -B $(srcdir)/spec/bundled_gems.mspec \
		$(MSPECOPT) $(SPECOPTS)
	$(ACTIONS_ENDGROUP)
no-test-bundled-gems-spec:


test-syntax-suggest:

check: $(DOT_WAIT) $(PREPARE_SYNTAX_SUGGEST) test-syntax-suggest

test-bundler-precheck: $(TEST_RUNNABLE)-test-bundler-precheck
no-test-bundler-precheck:
yes-test-bundler-precheck: main $(arch)-fake.rb
yes-test-bundler-parallel-precheck: yes-test-bundler-precheck

test-bundler-prepare: $(TEST_RUNNABLE)-test-bundler-prepare
no-test-bundler-prepare: no-test-bundler-precheck
yes-test-bundler-prepare: yes-test-bundler-precheck
	$(ACTIONS_GROUP)
	$(XRUBY) -C $(srcdir) -Ilib -r./tool/lib/bundle_env.rb \
		spec/bin/bundle install --quiet --gemfile=tool/bundler/dev_gems.rb
	$(ACTIONS_ENDGROUP)

RSPECOPTS = -r formatter_overrides
BUNDLER_SPECS =
PREPARE_BUNDLER = $(TEST_RUNNABLE)-test-bundler-prepare
test-bundler: $(TEST_RUNNABLE)-test-bundler
yes-test-bundler: $(PREPARE_BUNDLER)
	$(gnumake_recursive)$(XRUBY) \
		-r./$(arch)-fake \
		-C $(srcdir) -Ispec/bundler -Ispec/lib spec/bin/rspec \
		-r spec_helper $(RSPECOPTS) spec/bundler/$(BUNDLER_SPECS)
no-test-bundler:

PARALLELRSPECOPTS = --runtime-log $(srcdir)/tmp/parallel_runtime_rspec.log
test-bundler-parallel: $(TEST_RUNNABLE)-test-bundler-parallel
yes-test-bundler-parallel: $(PREPARE_BUNDLER)
	$(gnumake_recursive)$(XRUBY) \
		-r./$(arch)-fake \
		-I$(srcdir)/spec/bundler \
		-e "ruby = ENV['RUBY']" \
		-e "ARGV[-1] = File.expand_path(ARGV[-1])" \
		-e "ENV['RSPEC_EXECUTABLE'] = ruby + ARGV.shift" \
		-e "load ARGV.shift" \
		" -C $(srcdir) -Ispec/bundler -Ispec/lib .bundle/bin/rspec -r spec_helper" \
		$(srcdir)/spec/bin/parallel_rspec $(RSPECOPTS) \
		$(PARALLELRSPECOPTS) $(srcdir)/spec/bundler/$(BUNDLER_SPECS)
no-test-bundler-parallel:

# The annocheck supports ELF format binaries compiled for any OS and for any
# architecture. It is designed to be independent of the host OS and the
# architecture. The test-annocheck.sh requires docker or podman.
test-annocheck: $(PROGRAM) $(LIBRUBY_SO)
	$(tooldir)/test-annocheck.sh $(PROGRAM) $(LIBRUBY_SO)

GEM = up
sync-default-gems:
	$(Q) $(XRUBY) -C "$(srcdir)" tool/sync_default_gems.rb $(GEM)

UNICODE_FILES = $(UNICODE_SRC_DATA_DIR)/UnicodeData.txt \
		$(UNICODE_SRC_DATA_DIR)/CompositionExclusions.txt \
		$(UNICODE_SRC_DATA_DIR)/NormalizationTest.txt \
		$(UNICODE_SRC_DATA_DIR)/CaseFolding.txt \
		$(UNICODE_SRC_DATA_DIR)/SpecialCasing.txt \
		$(empty)

UNICODE_PROPERTY_FILES = \
		$(UNICODE_SRC_DATA_DIR)/Blocks.txt \
		$(UNICODE_SRC_DATA_DIR)/DerivedAge.txt \
		$(UNICODE_SRC_DATA_DIR)/DerivedCoreProperties.txt \
		$(UNICODE_SRC_DATA_DIR)/PropList.txt \
		$(UNICODE_SRC_DATA_DIR)/PropertyAliases.txt \
		$(UNICODE_SRC_DATA_DIR)/PropertyValueAliases.txt \
		$(UNICODE_SRC_DATA_DIR)/Scripts.txt \
		$(empty)

UNICODE_AUXILIARY_FILES = \
		$(UNICODE_SRC_DATA_DIR)/auxiliary/GraphemeBreakProperty.txt \
		$(UNICODE_SRC_DATA_DIR)/auxiliary/GraphemeBreakTest.txt \
		$(empty)

UNICODE_UCD_EMOJI_FILES = \
		$(UNICODE_SRC_DATA_DIR)/emoji/emoji-data.txt \
		$(UNICODE_SRC_DATA_DIR)/emoji/emoji-variation-sequences.txt \
		$(empty)

UNICODE_EMOJI_FILES = \
		$(UNICODE_SRC_EMOJI_DATA_DIR)/emoji-sequences.txt \
		$(UNICODE_SRC_EMOJI_DATA_DIR)/emoji-test.txt \
		$(UNICODE_SRC_EMOJI_DATA_DIR)/emoji-zwj-sequences.txt \
		$(empty)

update-unicode: $(UNICODE_FILES) $(UNICODE_PROPERTY_FILES) \
		$(UNICODE_AUXILIARY_FILES) $(UNICODE_UCD_EMOJI_FILES) $(UNICODE_EMOJI_FILES)

CACHE_DIR = $(srcdir)/.downloaded-cache
UNICODE_DOWNLOADER_ALWAYS_UPDATE = $(ALWAYS_UPDATE_UNICODE:yes=--always)
UNICODE_DOWNLOADER = \
	$(BASERUBY) $(tooldir)/downloader.rb \
	    --cache-dir=$(CACHE_DIR) \
	    --exist $(UNICODE_DOWNLOADER_ALWAYS_UPDATE:no=) \
	    unicode --unicode-beta=$(UNICODE_BETA)
UNICODE_DOWNLOAD = \
	$(UNICODE_DOWNLOADER) \
	    -d $(UNICODE_SRC_DATA_DIR) \
	    -p $(UNICODE_VERSION)/ucd
UNICODE_AUXILIARY_DOWNLOAD = \
	$(UNICODE_DOWNLOADER) \
	    -d $(UNICODE_SRC_DATA_DIR)/auxiliary \
	    -p $(UNICODE_VERSION)/ucd/auxiliary
UNICODE_UCD_EMOJI_DOWNLOAD = \
	$(UNICODE_DOWNLOADER) \
	    -d $(UNICODE_SRC_DATA_DIR)/emoji \
	    -p $(UNICODE_VERSION)/ucd/emoji
UNICODE_EMOJI_DOWNLOAD = \
	$(UNICODE_DOWNLOADER) \
	    -d $(UNICODE_SRC_EMOJI_DATA_DIR) \
	    -p emoji/$(UNICODE_EMOJI_VERSION)

update-unicode-files:
	$(ECHO) Downloading Unicode $(UNICODE_VERSION) data and property files...
	$(Q) $(MAKEDIRS) "$(UNICODE_SRC_DATA_DIR)"
	$(Q) $(UNICODE_DOWNLOAD) $(UNICODE_FILES) $(UNICODE_PROPERTY_FILES)

update-unicode-auxiliary-files:
	$(ECHO) Downloading Unicode $(UNICODE_VERSION) auxiliary files...
	$(Q) $(MAKEDIRS) "$(UNICODE_SRC_DATA_DIR)/auxiliary"
	$(Q) $(UNICODE_AUXILIARY_DOWNLOAD) $(UNICODE_AUXILIARY_FILES)

update-unicode-ucd-emoji-files:
	$(ECHO) Downloading Unicode UCD emoji $(UNICODE_EMOJI_VERSION) files...
	$(Q) $(MAKEDIRS) "$(UNICODE_SRC_DATA_DIR)/emoji"
	$(Q) $(UNICODE_UCD_EMOJI_DOWNLOAD) $(UNICODE_UCD_EMOJI_FILES)

update-unicode-emoji-files:
	$(ECHO) Downloading Unicode emoji $(UNICODE_EMOJI_VERSION) files...
	$(Q) $(MAKEDIRS) "$(UNICODE_SRC_EMOJI_DATA_DIR)"
	$(Q) $(UNICODE_EMOJI_DOWNLOAD) $(UNICODE_EMOJI_FILES)

$(UNICODE_FILES) $(UNICODE_PROPERTY_FILES):
	$(ECHO) Downloading Unicode $(UNICODE_VERSION) data and property files...
	$(Q) $(MAKEDIRS) "$(UNICODE_SRC_DATA_DIR)"
	$(Q) $(UNICODE_DOWNLOAD) $@

$(UNICODE_AUXILIARY_FILES):
	$(ECHO) Downloading Unicode $(UNICODE_VERSION) auxiliary files...
	$(Q) $(MAKEDIRS) "$(UNICODE_SRC_DATA_DIR)/auxiliary"
	$(Q) $(UNICODE_AUXILIARY_DOWNLOAD) $@

$(UNICODE_UCD_EMOJI_FILES):
	$(ECHO) Downloading Unicode UCD emoji $(UNICODE_EMOJI_VERSION) files...
	$(Q) $(MAKEDIRS) "$(UNICODE_SRC_DATA_DIR)/emoji"
	$(Q) $(UNICODE_UCD_EMOJI_DOWNLOAD) $@

$(UNICODE_EMOJI_FILES):
	$(ECHO) Downloading Unicode emoji $(UNICODE_EMOJI_VERSION) files...
	$(Q) $(MAKEDIRS) "$(UNICODE_SRC_EMOJI_DATA_DIR)"
	$(Q) $(UNICODE_EMOJI_DOWNLOAD) $@

$(srcdir)/lib/unicode_normalize/tables.rb: \
	$(UNICODE_SRC_DATA_DIR)/$(HAVE_BASERUBY:yes=.unicode-tables.time)

$(UNICODE_SRC_DATA_DIR)/$(ALWAYS_UPDATE_UNICODE:yes=.unicode-tables.time): \
	$(UNICODE_FILES) $(UNICODE_PROPERTY_FILES) \
	$(UNICODE_AUXILIARY_FILES) $(UNICODE_UCD_EMOJI_FILES) $(UNICODE_EMOJI_FILES)

touch-unicode-files:
	$(MAKEDIRS) $(UNICODE_SRC_DATA_DIR)
	$(Q) $(TOUCH) $(UNICODE_SRC_DATA_DIR)/.unicode-tables.time $(UNICODE_DATA_HEADERS)

UNICODE_TABLES_DATA_FILES = \
	$(UNICODE_SRC_DATA_DIR)/UnicodeData.txt \
	$(UNICODE_SRC_DATA_DIR)/CompositionExclusions.txt \
	$(empty)

UNICODE_TABLES_DEPENDENTS_1 = none$(ALWAYS_UPDATE_UNICODE)
UNICODE_TABLES_DEPENDENTS = $(UNICODE_TABLES_DEPENDENTS_1:noneyes=force)
UNICODE_TABLES_TIMESTAMP = yes
$(UNICODE_SRC_DATA_DIR)/.unicode-tables.$(UNICODE_TABLES_DEPENDENTS:none=time):
	$(Q) $(MAKEDIRS) $(@D)
	$(Q) exit > $(@) || $(NULLCMD)
$(UNICODE_SRC_DATA_DIR)/.unicode-tables.$(UNICODE_TABLES_DEPENDENTS:force=time): \
		$(tooldir)/generic_erb.rb \
		$(srcdir)/template/unicode_norm_gen.tmpl \
		$(UNICODE_TABLES_DATA_FILES) \
	$(order_only) \
		$(UNICODE_SRC_DATA_DIR)
	$(Q) $(BASERUBY) $(tooldir)/generic_erb.rb \
		-c $(UNICODE_TABLES_TIMESTAMP:yes=-t$@) \
		-o $(srcdir)/lib/unicode_normalize/tables.rb \
		-I $(srcdir) \
		$(srcdir)/template/unicode_norm_gen.tmpl \
		$(UNICODE_DATA_DIR) lib/unicode_normalize

$(UNICODE_SRC_DATA_DIR):
	$(gnumake_recursive)$(Q) $(MAKEDIRS) $@

$(UNICODE_HDR_DIR)/$(ALWAYS_UPDATE_UNICODE:yes=name2ctype.h): \
		$(tooldir)/enc-unicode.rb \
		$(UNICODE_SRC_DATA_DIR)/UnicodeData.txt \
		$(UNICODE_AUXILIARY_FILES) \
		$(UNICODE_PROPERTY_FILES) \
		$(UNICODE_UCD_EMOJI_FILES) \
		$(UNICODE_EMOJI_FILES)

$(UNICODE_HDR_DIR)/name2ctype.h:
	$(MAKEDIRS) $(@D)
	$(BOOTSTRAPRUBY) $(tooldir)/enc-unicode.rb --header \
		$(UNICODE_SRC_DATA_DIR) $(UNICODE_SRC_EMOJI_DATA_DIR) > $@.new
	$(MV) $@.new $@

srcs-doc: $(srcdir)/doc/regexp/unicode_properties.rdoc
$(srcdir)/doc/regexp/$(ALWAYS_UPDATE_UNICODE:yes=unicode_properties.rdoc): \
	$(UNICODE_HDR_DIR)/name2ctype.h $(UNICODE_PROPERTY_FILES)

$(srcdir)/doc/regexp/unicode_properties.rdoc:
	$(Q) $(BOOTSTRAPRUBY) $(tooldir)/generic_erb.rb -c -o $@ \
		$(srcdir)/template/unicode_properties.rdoc.tmpl \
		$(UNICODE_SRC_DATA_DIR) $(UNICODE_HDR_DIR)/name2ctype.h || \
	$(TOUCH) $@

# the next non-comment line was:
# $(UNICODE_HDR_DIR)/casefold.h: $(tooldir)/enc-case-folding.rb \
# but was changed to make sure CI works on systems that don't have gperf
unicode-up: $(UNICODE_DATA_HEADERS)

$(UNICODE_HDR_DIR)/$(ALWAYS_UPDATE_UNICODE:yes=casefold.h): \
		$(tooldir)/enc-case-folding.rb \
		$(UNICODE_SRC_DATA_DIR)/UnicodeData.txt \
		$(UNICODE_SRC_DATA_DIR)/SpecialCasing.txt \
		$(UNICODE_SRC_DATA_DIR)/CaseFolding.txt

$(UNICODE_HDR_DIR)/casefold.h:
	$(MAKEDIRS) $(@D)
	$(Q) $(BASERUBY) $(tooldir)/enc-case-folding.rb \
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
exam: $(DOT_WAIT) test-bundler-parallel
exam: $(DOT_WAIT) bundled_gems_spec-run
exam: $(DOT_WAIT) test-bundled-gems

love: sudo-precheck up all test exam install
	@echo love is all you need

great: exam

yes-test-all no-test-all: sudo-precheck

sudo-precheck: PHONY
	@$(SUDO) echo > $(NULL)

update-man-date: PHONY
	-$(Q) $(BASERUBY) -I"$(tooldir)/lib" -rvcs -i -p \
	-e 'BEGIN{@vcs=VCS.detect(ARGV.shift)}' \
	-e '$$_.sub!(/^(\.Dd ).*/){$$1+@vcs.modified(ARGF.path).strftime("%B %d, %Y")}' \
	"$(srcdir)" "$(srcdir)"/man/*.1

.PHONY: ChangeLog
ChangeLog:
	$(ECHO) Generating $@
	-$(Q) $(BASERUBY) -I"$(tooldir)/lib" -rvcs \
	-e 'VCS.detect(ARGV[0]).export_changelog(path: ARGV[1])' \
	"$(srcdir)" $@

# CAUTION: If using GNU make 3 which does not support `.WAIT`, this
# recipe with multiple jobs makes build and `git reset` run
# simultaneously, and will cause inconsistent results.  Run with `-j1`
# or update GNU make.
nightly: yesterday $(DOT_WAIT) install
	$(NULLCMD)

# Rewind to the last commit "yesterday".  "Yesterday" means here the
# period where `RUBY_RELEASE_DATE` is the day before the date to be
# generated now.  In short, the yesterday in JST-9 time zone.
yesterday: rewindable

rewindable:
	$(GIT) -C $(srcdir) status --porcelain
	$(GIT) -C $(srcdir) diff --quiet

HELP_EXTRA_TASKS = ""

gc/Makefile:
	$(MAKEDIRS) $(@D)
	$(MESSAGE_BEGIN) \
	"all:" \
	"	@echo You must specify MODULAR_GC with the GC to build" \
	"	@exit 1" \
	$(MESSAGE_END) > $@
gc/distclean gc/realclean::
	-$(Q) $(RM) gc/Makefile

modular-gc-precheck:
modular-gc: probes.h gc/Makefile
	$(Q) $(RUNRUBY) $(srcdir)/ext/extmk.rb \
		$(SCRIPT_ARGS) \
		--make='$(MAKE)' --make-flags="V=$(V) MINIRUBY='$(MINIRUBY)'" \
		--gnumake=$(gnumake) --extflags="$(EXTLDFLAGS)" \
		--ext-build-dir=gc --command-output=gc/$(MODULAR_GC)/exts.mk -- \
		configure gc/$(MODULAR_GC)
	$(CHDIR) gc/$(MODULAR_GC) && $(exec) $(MAKE) TARGET_SO_DIR=./
install-modular-gc: modular-gc modular-gc-precheck
	$(Q) $(MAKEDIRS) $(modular_gc_dir)
	$(CP) gc/$(MODULAR_GC)/librubygc.$(MODULAR_GC).$(DLEXT) $(modular_gc_dir)

clean-modular-gc: gc/clean
distclean-modular-gc: gc/distclean
realclean-modular-gc: gc/realclean
distclean-modular-gc realclean-modular-gc:
	-$(Q) $(RMDIR) gc

help: PHONY
	$(MESSAGE_BEGIN) \
	"                Makefile of Ruby" \
	"" \
	"targets:" \
	"  all (default):         builds all of below" \
	"  miniruby:              builds only miniruby" \
	"  encs:                  builds encodings" \
	"  exts:                  builds extensions" \
	"  main:                  builds encodings, extensions and ruby" \
	"  docs:                  builds documents" \
	"  install-capi:          builds C API documents" \
	"  run:                   runs test.rb by miniruby" \
	"  runruby:               runs test.rb by ruby you just built" \
	"  gdb:                   runs test.rb by miniruby under gdb" \
	"  gdb-ruby:              runs test.rb by ruby under gdb" \
	"  runirb:                starts irb on built ruby (not installed ruby)" \
	"  exam:                  equals make check test-bundler-parallel test-bundled-gems" \
	"  check:                 equals make test test-tool test-all test-spec test-syntax-suggest" \
	"  test:                  ruby core tests [BTESTS=<bootstraptest files>]" \
	"  test-all:              all ruby tests [TESTOPTS=-j4 TESTS=<test files>]" \
	"  test-spec:             run the Ruby spec suite [SPECOPTS=<specs, opts>]" \
	"  test-bundler:          run the Bundler spec" \
	"  test-bundler-parallel: run the Bundler spec with parallel" \
	"  test-syntax-suggest:   run the SyntaxSuggest spec" \
	"  test-bundled-gems:     run the test suite of bundled gems [BUNDLED_GEMS=<gems>]" \
	"  test-tool:             tests under the tool/test" \
	"  update-gems:           download files of the bundled gems" \
	"  update-bundled_gems:   update the latest version of bundled gems" \
	"  sync-default-gems:     sync default gems from upstream [GEM=<gem_name git_ref>]" \
	"  up:                    update local copy and autogenerated files" \
	"  benchmark:             benchmark this ruby and COMPARE_RUBY." \
	"  gcbench:               gc benchmark [GCBENCH_ITEM=<item_name>]" \
	"  install:               install all ruby distributions" \
	"  install-nodoc:         install without rdoc" \
	"  install-cross:         install cross compiling stuff" \
	"  clean:                 clean up to the state before build" \
	"  distclean:             clean up to the state before configure" \
	"  golf:                  build goruby for golfers" \
	$(HELP_EXTRA_TASKS) \
	"see DeveloperHowto for more detail: " \
	"  https://github.com/ruby/ruby/wiki/Developer-How-To" \
	$(MESSAGE_END)

$(CROSS_COMPILING:yes=)builtin.$(OBJEXT): {$(VPATH)}mini_builtin.c
$(CROSS_COMPILING:yes=)builtin.$(OBJEXT): {$(VPATH)}miniprelude.c
