bin: $(PROGRAM) $(WPROGRAM)
lib: $(LIBRUBY);
dll: $(LIBRUBY_SO);

RUBYOPT       =

EXTCONF       = extconf.rb
RBCONFIG      = ./.rbconfig.time

DMYEXT	      = dmyext.$(OBJEXT)
MAINOBJ	      = main.$(OBJEXT)
EXTOBJS	      = 
DLDOBJS	      = $(DMYEXT)

OBJS	      = array.$(OBJEXT) \
		ascii.$(OBJEXT) \
		bignum.$(OBJEXT) \
		class.$(OBJEXT) \
		compar.$(OBJEXT) \
		dir.$(OBJEXT) \
		dln.$(OBJEXT) \
		enum.$(OBJEXT) \
		enumerator.$(OBJEXT) \
		error.$(OBJEXT) \
		euc_jp.$(OBJEXT) \
		eval.$(OBJEXT) \
		eval_load.$(OBJEXT) \
		eval_proc.$(OBJEXT) \
		eval_thread.$(OBJEXT) \
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
		re.$(OBJEXT) \
		regcomp.$(OBJEXT) \
		regenc.$(OBJEXT) \
		regerror.$(OBJEXT) \
		regexec.$(OBJEXT) \
		regparse.$(OBJEXT) \
		ruby.$(OBJEXT) \
		signal.$(OBJEXT) \
		sjis.$(OBJEXT) \
		sprintf.$(OBJEXT) \
		st.$(OBJEXT) \
		string.$(OBJEXT) \
		struct.$(OBJEXT) \
		time.$(OBJEXT) \
		utf8.$(OBJEXT) \
		util.$(OBJEXT) \
		variable.$(OBJEXT) \
		version.$(OBJEXT) \
		blockinlining.$(OBJEXT) \
		compile.$(OBJEXT) \
		debug.$(OBJEXT) \
		iseq.$(OBJEXT) \
		vm.$(OBJEXT) \
		vm_dump.$(OBJEXT) \
		yarvcore.$(OBJEXT) \
		thread.$(OBJEXT) \
		$(MISSING)

SCRIPT_ARGS   =	--dest-dir="$(DESTDIR)" \
		--make="$(MAKE)" \
		--mflags="$(MFLAGS)" \
		--make-flags="$(MAKEFLAGS)"
EXTMK_ARGS    =	$(SCRIPT_ARGS) --extout="$(EXTOUT)" --extension $(EXTS) --extstatic $(EXTSTATIC) --

all: $(MKFILES) $(PREP) $(RBCONFIG) $(LIBRUBY)
	$(MINIRUBY) $(srcdir)/ext/extmk.rb $(EXTMK_ARGS)

prog: $(PROGRAM) $(WPROGRAM)

miniruby$(EXEEXT): config.status $(LIBRUBY_A) $(MAINOBJ) $(MINIOBJS) $(OBJS) $(DMYEXT)

$(PROGRAM): $(LIBRUBY) $(MAINOBJ) $(OBJS) $(EXTOBJS) $(SETUP) $(PREP)

$(LIBRUBY_A):	$(OBJS) $(DMYEXT)

$(LIBRUBY_SO):	$(OBJS) $(DLDOBJS) $(LIBRUBY_A) $(PREP) $(ARCHFILE)

static-ruby: $(MAINOBJ) $(EXTOBJS) $(LIBRUBY_A)
	@$(RM) $@
	$(PURIFY) $(CC) $(LDFLAGS) $(XLDFLAGS) $(MAINLIBS) $(MAINOBJ) $(EXTOBJS) $(LIBRUBY_A) $(LIBS) $(OUTFLAG)$@

ruby.imp: $(LIBRUBY_A)
	@$(NM) -Pgp $(LIBRUBY_A) | awk 'BEGIN{print "#!"}; $$2~/^[BD]$$/{print $$1}' | sort -u -o $@

install: install-nodoc $(RDOCTARGET)
install-all: install-nodoc install-doc

install-nodoc: install-local install-ext
install-local: pre-install-local do-install-local post-install-local
install-ext: pre-install-ext do-install-ext post-install-ext

do-install-local: $(RBCONFIG)
	$(MINIRUBY) $(srcdir)/instruby.rb $(SCRIPT_ARGS) --mantype="$(MANTYPE)"
do-install-ext: $(RBCONFIG)
	$(MINIRUBY) $(srcdir)/ext/extmk.rb $(EXTMK_ARGS) install

install-bin: $(RBCONFIG)
	$(MINIRUBY) $(srcdir)/instruby.rb $(SCRIPT_ARGS) --install=bin
install-lib: $(RBCONFIG)
	$(MINIRUBY) $(srcdir)/instruby.rb $(SCRIPT_ARGS) --install=lib
install-man: $(RBCONFIG)
	$(MINIRUBY) $(srcdir)/instruby.rb $(SCRIPT_ARGS) --install=man --mantype="$(MANTYPE)"

what-where-all no-install-all: no-install no-install-doc
what-where no-install: no-install-local no-install-ext
what-where-local: no-install-local
no-install-local: $(RBCONFIG)
	$(MINIRUBY) $(srcdir)/instruby.rb -n $(SCRIPT_ARGS) --mantype="$(MANTYPE)"
what-where-ext: no-install-ext
no-install-ext: $(RBCONFIG)
	$(MINIRUBY) $(srcdir)/ext/extmk.rb -n $(EXTMK_ARGS) install

install-doc: pre-install-doc do-install-doc post-install-doc
do-install-doc: $(PROGRAM)
	@echo Generating RDoc documentation
	$(RUNRUBY) "$(srcdir)/bin/rdoc" --all --ri --op "$(RIDATADIR)" "$(srcdir)"

pre-install: pre-install-local pre-install-ext
pre-install-local:: PHONY
pre-install-ext:: PHONY
pre-install-doc:: PHONY

post-install: post-install-local post-install-ext
post-install-local:: PHONY
post-install-ext:: PHONY
post-install-doc:: PHONY

# no ext
# clean: clean-ext clean-local
clean: clean-local

clean-local::
	@$(RM) $(OBJS) $(MAINOBJ) $(WINMAINOBJ) $(LIBRUBY_A) $(LIBRUBY_SO) $(LIBRUBY) $(LIBRUBY_ALIASES)
	@$(RM) $(PROGRAM) $(WPROGRAM) miniruby$(EXEEXT) dmyext.$(OBJEXT) $(ARCHFILE)
	@$(RM) *.inc

clean-ext:
	@-$(MINIRUBY) $(srcdir)/ext/extmk.rb $(EXTMK_ARGS) clean

distclean: distclean-ext distclean-local
distclean-local:: clean-local
	@$(RM) $(MKFILES) config.h rbconfig.rb
	@$(RM) config.cache config.log config.status
	@$(RM) *~ *.bak *.stackdump core *.core gmon.out y.tab.c y.output $(PREP)
distclean-ext:
	@-$(MINIRUBY) $(srcdir)/ext/extmk.rb $(EXTMK_ARGS) distclean

realclean:: distclean
	@$(RM) parse.c lex.c

check: test test-all

test: miniruby$(EXEEXT) $(RBCONFIG) $(PROGRAM) PHONY
	@$(MINIRUBY) $(srcdir)/rubytest.rb

test-all: miniruby$(EXEEXT) ruby
	$(RUNRUBY) -C "$(srcdir)/test" runner.rb --runner=$(TESTUI) $(TESTS)

extconf:
	$(MINIRUBY) -I$(srcdir)/lib -run -e mkdir -- -p "$(EXTCONFDIR)"
	$(RUNRUBY) -C "$(EXTCONFDIR)" $(EXTCONF) $(EXTCONFARGS)

$(RBCONFIG): $(srcdir)/mkconfig.rb config.status $(PREP)
	$(MINIRUBY) $(srcdir)/mkconfig.rb -timestamp=$@ \
		-install_name=$(RUBY_INSTALL_NAME) \
		-so_name=$(RUBY_SO_NAME) rbconfig.rb

.PRECIOUS: $(MKFILES)

.PHONY: test install install-nodoc install-doc

PHONY:

{$(VPATH)}parse.c: parse.y

acosh.$(OBJEXT): {$(VPATH)}acosh.c
alloca.$(OBJEXT): {$(VPATH)}alloca.c
crypt.$(OBJEXT): {$(VPATH)}crypt.c
dup2.$(OBJEXT): {$(VPATH)}dup2.c
erf.$(OBJEXT): {$(VPATH)}erf.c
finite.$(OBJEXT): {$(VPATH)}finite.c
flock.$(OBJEXT): {$(VPATH)}flock.c
memcmp.$(OBJEXT): {$(VPATH)}memcmp.c
memmove.$(OBJEXT): {$(VPATH)}memmove.c
mkdir.$(OBJEXT): {$(VPATH)}mkdir.c
strcasecmp.$(OBJEXT): {$(VPATH)}strcasecmp.c
strncasecmp.$(OBJEXT): {$(VPATH)}strncasecmp.c
strchr.$(OBJEXT): {$(VPATH)}strchr.c
strdup.$(OBJEXT): {$(VPATH)}strdup.c
strerror.$(OBJEXT): {$(VPATH)}strerror.c
strftime.$(OBJEXT): {$(VPATH)}strftime.c
strstr.$(OBJEXT): {$(VPATH)}strstr.c
strtod.$(OBJEXT): {$(VPATH)}strtod.c
strtol.$(OBJEXT): {$(VPATH)}strtol.c
strtoul.$(OBJEXT): {$(VPATH)}strtoul.c
nt.$(OBJEXT): {$(VPATH)}nt.c
x68.$(OBJEXT): {$(VPATH)}x68.c
os2.$(OBJEXT): {$(VPATH)}os2.c
dl_os2.$(OBJEXT): {$(VPATH)}dl_os2.c

# when I use -I., there is confliction at "OpenFile" 
# so, set . into environment varible "include"
win32.$(OBJEXT): {$(VPATH)}win32.c

###

array.$(OBJEXT): {$(VPATH)}array.c {$(VPATH)}ruby.h config.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h \
  {$(VPATH)}util.h {$(VPATH)}st.h
ascii.$(OBJEXT): {$(VPATH)}ascii.c {$(VPATH)}regenc.h \
  {$(VPATH)}oniguruma.h config.h
bignum.$(OBJEXT): {$(VPATH)}bignum.c {$(VPATH)}ruby.h config.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h
class.$(OBJEXT): {$(VPATH)}class.c {$(VPATH)}ruby.h config.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h \
  {$(VPATH)}rubysig.h {$(VPATH)}node.h {$(VPATH)}st.h
compar.$(OBJEXT): {$(VPATH)}compar.c {$(VPATH)}ruby.h config.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h
dir.$(OBJEXT): {$(VPATH)}dir.c {$(VPATH)}ruby.h config.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h \
  {$(VPATH)}util.h
dln.$(OBJEXT): {$(VPATH)}dln.c {$(VPATH)}ruby.h config.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h \
  {$(VPATH)}dln.h
dmydln.$(OBJEXT): {$(VPATH)}dmydln.c {$(VPATH)}dln.c {$(VPATH)}ruby.h \
  config.h {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h \
  {$(VPATH)}dln.h
dmyext.$(OBJEXT): {$(VPATH)}dmyext.c
enum.$(OBJEXT): {$(VPATH)}enum.c {$(VPATH)}ruby.h config.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h \
  {$(VPATH)}node.h {$(VPATH)}util.h
enumerator.$(OBJEXT): {$(VPATH)}enumerator.c {$(VPATH)}ruby.h config.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h
error.$(OBJEXT): {$(VPATH)}error.c {$(VPATH)}ruby.h config.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h \
  {$(VPATH)}st.h vm_opts.h
euc_jp.$(OBJEXT): {$(VPATH)}euc_jp.c {$(VPATH)}regenc.h \
  {$(VPATH)}oniguruma.h

eval.$(OBJEXT): {$(VPATH)}eval.c  {$(VPATH)}eval_intern.h \
  {$(VPATH)}eval_method.h {$(VPATH)}eval_safe.h {$(VPATH)}eval_jump.h \
  {$(VPATH)}ruby.h config.h  {$(VPATH)}yarvcore.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h \
  {$(VPATH)}node.h {$(VPATH)}util.h \
  {$(VPATH)}rubysig.h {$(VPATH)}st.h {$(VPATH)}dln.h {$(VPATH)}yarv.h
eval_load.$(OBJEXT): {$(VPATH)}eval_load.c {$(VPATH)}eval_intern.h \
  {$(VPATH)}ruby.h config.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h \
  {$(VPATH)}node.h {$(VPATH)}util.h  {$(VPATH)}yarvcore.h \
  {$(VPATH)}rubysig.h {$(VPATH)}st.h {$(VPATH)}dln.h {$(VPATH)}yarv.h
eval_thread.$(OBJEXT): {$(VPATH)}eval_thread.c {$(VPATH)}eval_intern.h \
  {$(VPATH)}ruby.h config.h  {$(VPATH)}yarvcore.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h \
  {$(VPATH)}node.h {$(VPATH)}util.h \
  {$(VPATH)}rubysig.h {$(VPATH)}st.h {$(VPATH)}dln.h {$(VPATH)}yarv.h
eval_proc.$(OBJEXT): {$(VPATH)}eval_proc.c  {$(VPATH)}eval_intern.h \
  {$(VPATH)}ruby.h config.h  {$(VPATH)}yarvcore.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h \
  {$(VPATH)}node.h {$(VPATH)}util.h \
  {$(VPATH)}rubysig.h {$(VPATH)}st.h {$(VPATH)}dln.h {$(VPATH)}yarv.h

thread.$(OBJEXT): {$(VPATH)}thread.c  {$(VPATH)}eval_intern.h \
  {$(VPATH)}thread_win32.h {$(VPATH)}thread_pthread.h \
  {$(VPATH)}thread_win32.ci {$(VPATH)}thread_pthread.ci \
  {$(VPATH)}ruby.h config.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h \
  {$(VPATH)}node.h {$(VPATH)}util.h \
  {$(VPATH)}rubysig.h {$(VPATH)}st.h {$(VPATH)}dln.h \
  {$(VPATH)}yarv.h {$(VPATH)}yarvcore.h

file.$(OBJEXT): {$(VPATH)}file.c {$(VPATH)}ruby.h config.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h \
  {$(VPATH)}rubyio.h {$(VPATH)}rubysig.h {$(VPATH)}util.h \
  {$(VPATH)}dln.h
gc.$(OBJEXT): {$(VPATH)}gc.c {$(VPATH)}ruby.h config.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h \
  {$(VPATH)}rubysig.h {$(VPATH)}st.h {$(VPATH)}node.h \
  {$(VPATH)}re.h {$(VPATH)}regex.h {$(VPATH)}yarvcore.h
hash.$(OBJEXT): {$(VPATH)}hash.c {$(VPATH)}ruby.h config.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h \
  {$(VPATH)}st.h {$(VPATH)}util.h {$(VPATH)}rubysig.h
inits.$(OBJEXT): {$(VPATH)}inits.c {$(VPATH)}ruby.h config.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h
io.$(OBJEXT): {$(VPATH)}io.c {$(VPATH)}ruby.h config.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h \
  {$(VPATH)}rubyio.h {$(VPATH)}rubysig.h  {$(VPATH)}util.h
main.$(OBJEXT): {$(VPATH)}main.c {$(VPATH)}ruby.h config.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h
marshal.$(OBJEXT): {$(VPATH)}marshal.c {$(VPATH)}ruby.h config.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h \
  {$(VPATH)}rubyio.h {$(VPATH)}st.h {$(VPATH)}util.h
math.$(OBJEXT): {$(VPATH)}math.c {$(VPATH)}ruby.h config.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h
numeric.$(OBJEXT): {$(VPATH)}numeric.c {$(VPATH)}ruby.h config.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h \
  {$(VPATH)}missing.h
object.$(OBJEXT): {$(VPATH)}object.c {$(VPATH)}ruby.h config.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h \
  {$(VPATH)}st.h {$(VPATH)}util.h
pack.$(OBJEXT): {$(VPATH)}pack.c {$(VPATH)}ruby.h config.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h
parse.$(OBJEXT): {$(VPATH)}parse.c {$(VPATH)}ruby.h config.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h \
  {$(VPATH)}node.h {$(VPATH)}st.h \
  {$(VPATH)}regex.h {$(VPATH)}util.h {$(VPATH)}lex.c
prec.$(OBJEXT): {$(VPATH)}prec.c {$(VPATH)}ruby.h config.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h
process.$(OBJEXT): {$(VPATH)}process.c {$(VPATH)}ruby.h config.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h \
  {$(VPATH)}rubysig.h {$(VPATH)}st.h
random.$(OBJEXT): {$(VPATH)}random.c {$(VPATH)}ruby.h config.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h
range.$(OBJEXT): {$(VPATH)}range.c {$(VPATH)}ruby.h config.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h
re.$(OBJEXT): {$(VPATH)}re.c {$(VPATH)}ruby.h config.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h \
  {$(VPATH)}re.h {$(VPATH)}regex.h
regcomp.$(OBJEXT): {$(VPATH)}regcomp.c {$(VPATH)}oniguruma.h \
  {$(VPATH)}regint.h {$(VPATH)}regparse.h {$(VPATH)}regenc.h config.h
regenc.$(OBJEXT): {$(VPATH)}regenc.c {$(VPATH)}regint.h \
  {$(VPATH)}regenc.h {$(VPATH)}oniguruma.h config.h
regerror.$(OBJEXT): {$(VPATH)}regerror.c {$(VPATH)}regint.h \
  {$(VPATH)}regenc.h {$(VPATH)}oniguruma.h config.h
regexec.$(OBJEXT): {$(VPATH)}regexec.c {$(VPATH)}regint.h \
  {$(VPATH)}regenc.h {$(VPATH)}oniguruma.h config.h
regparse.$(OBJEXT): {$(VPATH)}regparse.c {$(VPATH)}oniguruma.h \
  {$(VPATH)}regint.h {$(VPATH)}regparse.h {$(VPATH)}regenc.h config.h
ruby.$(OBJEXT): {$(VPATH)}ruby.c {$(VPATH)}ruby.h config.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h \
  {$(VPATH)}dln.h {$(VPATH)}node.h {$(VPATH)}util.h
signal.$(OBJEXT): {$(VPATH)}signal.c {$(VPATH)}ruby.h config.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h \
  {$(VPATH)}rubysig.h {$(VPATH)}yarvcore.h
sjis.$(OBJEXT): {$(VPATH)}sjis.c {$(VPATH)}regenc.h \
  {$(VPATH)}oniguruma.h config.h
sprintf.$(OBJEXT): {$(VPATH)}sprintf.c {$(VPATH)}ruby.h config.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h {$(VPATH)}vsnprintf.c
st.$(OBJEXT): {$(VPATH)}st.c config.h {$(VPATH)}st.h
string.$(OBJEXT): {$(VPATH)}string.c {$(VPATH)}ruby.h config.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h \
  {$(VPATH)}re.h {$(VPATH)}regex.h
struct.$(OBJEXT): {$(VPATH)}struct.c {$(VPATH)}ruby.h config.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h
time.$(OBJEXT): {$(VPATH)}time.c {$(VPATH)}ruby.h config.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h
utf8.$(OBJEXT): {$(VPATH)}utf8.c {$(VPATH)}regenc.h \
  {$(VPATH)}oniguruma.h config.h
util.$(OBJEXT): {$(VPATH)}util.c {$(VPATH)}ruby.h config.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h \
  {$(VPATH)}util.h
variable.$(OBJEXT): {$(VPATH)}variable.c {$(VPATH)}ruby.h config.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h \
  {$(VPATH)}node.h {$(VPATH)}st.h {$(VPATH)}util.h
version.$(OBJEXT): {$(VPATH)}version.c {$(VPATH)}ruby.h config.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h \
  {$(VPATH)}version.h {$(VPATH)}yarv_version.h 

compile.$(OBJEXT): {$(VPATH)}compile.c {$(VPATH)}yarvcore.h \
        {$(VPATH)}compile.h {$(VPATH)}debug.h \
        insns.inc insns_info.inc optinsn.inc opt_sc.inc optunifs.inc vm_opts.h
iseq.$(OBJEXT): {$(VPATH)}iseq.c {$(VPATH)}yarvcore.h {$(VPATH)}debug.h vm_opts.h
vm.$(OBJEXT): {$(VPATH)}vm.c {$(VPATH)}vm.h {$(VPATH)}insnhelper.h \
        {$(VPATH)}yarvcore.h {$(VPATH)}debug.h \
        {$(VPATH)}vm_evalbody.ci {$(VPATH)}call_cfunc.ci \
        insns.inc vm.inc vmtc.inc vm_macro.inc vm_opts.h {$(VPATH)}eval_intern.h
vm_dump.$(OBJEXT): {$(VPATH)}yarvcore.h {$(VPATH)}vm.h
yarvcore.$(OBJEXT): {$(VPATH)}yarvcore.c {$(VPATH)}yarvcore.h \
        {$(VPATH)}yarv_version.h {$(VPATH)}debug.h
debug.$(OBJEXT): {$(VPATH)}debug.h
blockinlining.$(OBJEXT): {$(VPATH)}yarv.h {$(VPATH)}yarvcore.h vm_opts.h


BASERUBY = ruby

INSNS2VMOPT = $(CPPFLAGS) --srcdir=$(srcdir)

minsns.inc:
	$(BASERUBY) $(srcdir)/tool/insns2vm.rb $(INSNS2VMOPT)

opt_sc.inc:
	$(BASERUBY) $(srcdir)/tool/insns2vm.rb $(INSNS2VMOPT)

optinsn.inc:
	$(BASERUBY) $(srcdir)/tool/insns2vm.rb $(INSNS2VMOPT) optinsn.inc

optunifs.inc:
	$(BASERUBY) $(srcdir)/tool/insns2vm.rb $(INSNS2VMOPT) optunifs.inc

insns.inc:
	$(BASERUBY) $(srcdir)/tool/insns2vm.rb $(INSNS2VMOPT)

vmtc.inc:
	$(BASERUBY) $(srcdir)/tool/insns2vm.rb $(INSNS2VMOPT) vmtc.inc

vm.inc: $(srcdir)/insns.def
	$(BASERUBY) $(srcdir)/tool/insns2vm.rb $(INSNS2VMOPT) vm.inc

vm_macro.inc: $(srcdir)/vm_macro.def
	$(BASERUBY) $(srcdir)/rb/insns2vm.rb $(INSNS2VMOPT) vm_macro.inc

vm_opts.h: $(srcdir)/vm_opts.h.base
	$(BASERUBY) $(srcdir)/tool/insns2vm.rb $(INSNS2VMOPT)

incs:
	$(BASERUBY) $(srcdir)/tool/insns2vm.rb $(INSNS2VMOPT)

docs:
	$(BASERUBY) -I$(srcdir) $(srcdir)/tool/makedocs.rb $(INSNS2VMOPT)

yarv-test-all: miniruby$(EXEEXT)
	$(BASERUBY) -I$(srcdir) $(srcdir)/yarvtest/runner.rb $(OPT) yarv=$(MINIRUBY) ruby=$(BASERUBY)

yarv-test-each: miniruby$(EXEEXT)
	$(BASERUBY) -I$(srcdir) $(srcdir)/yarvtest/test_$(ITEM).rb $(OPT) yarv=$(MINIRUBY) ruby=$(BASERUBY)

allload: miniruby$(EXEEXT)
	$(MINIRUBY) -I$(srcdir) $(srcdir)/tool/allload.rb `$(BASERUBY) -rrbconfig -e 'print Config::CONFIG["rubylibdir"]'`

run: miniruby$(EXEEXT)
	$(MINIRUBY) -I$(srcdir)/lib $(srcdir)/test.rb $(RUNOPT)

runruby: $(RUBY)
	./$(RUBY)  -I$(srcdir)/lib -I. $(srcdir)/tool/runruby.rb $(srcdir)/test.rb

parse: miniruby$(EXEEXT)
	$(MINIRUBY) $(srcdir)/tool/parse.rb $(srcdir)/test.rb

benchmark: $(RUBY)
	$(BASERUBY) -I$(srcdir) -I$(srcdir)/lib $(srcdir)/benchmark/run_rite.rb $(OPT) $(ITEMS) --yarv-program=./$(PROGRAM) --ruby-program=$(BASERUBY) --opts=-I$(srcdir)/lib

tbench: prog
	$(BASERUBY) -I$(srcdir) -I$(srcdir)/lib $(srcdir)/benchmark/run_rite.rb bmx $(OPT) --yarv-program=./$(PROGRAM) --ruby-program=$(BASERUBY) --opts=-I$(srcdir)/lib

bench-each: $(RUBY)
	$(BASERUBY) -I$(srcdir) $(srcdir)/benchmark/run_rite.rb bm_$(ITEM) $(OPT) --yarv-program=./$(RUBY) --ruby-program=$(BASERUBY) --opts=-I$(srcdir)/lib

aotc:
	$(RUBY) -I$(srcdir) -I. $(srcdir)/tool/aotcompile.rb $(INSNS2VMOPT)

# for GCC
vmasm:
	$(CC) $(CFLAGS) $(CPPFLAGS) -S $(srcdir)/vm.c

# vm.o : CFLAGS += -fno-crossjumping

run.gdb:
	echo b debug_breakpoint > run.gdb
	echo handle SIGINT nostop
	echo handle SIGPIPE nostop
	echo run               >> run.gdb

gdb: miniruby$(EXEEXT) run.gdb
	gdb -x run.gdb --quiet --args $(MINIRUBY) -I$(srcdir)/lib $(srcdir)/test.rb

# Intel VTune

vtune: miniruby$(EXEEXT)
	vtl activity -c sampling -app ".\miniruby$(EXEEXT)","-I$(srcdir)/lib $(srcdir)/test.rb" run
	vtl view -hf -mn miniruby$(EXEEXT) -sum -sort -cd
	vtl view -ha -mn miniruby$(EXEEXT) -sum -sort -cd | $(BASERUBY) $(srcdir)/tool/vtlh.rb > ha.lines

