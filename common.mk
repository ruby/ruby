EXTCONF       = extconf.rb
RBCONFIG      = ./.rbconfig.time

DMYEXT	      = dmyext.$(OBJEXT)
MAINOBJ	      = main.$(OBJEXT)

OBJS	      = ascii.$(OBJEXT) \
		array.$(OBJEXT) \
		bignum.$(OBJEXT) \
		class.$(OBJEXT) \
		compar.$(OBJEXT) \
		dir.$(OBJEXT) \
		dln.$(OBJEXT) \
		enum.$(OBJEXT) \
		error.$(OBJEXT) \
		euc_jp.$(OBJEXT) \
		eval.$(OBJEXT) \
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
		reggnu.$(OBJEXT) \
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
		$(MISSING)

SCRIPT_ARGS   =	--dest-dir="$(DESTDIR)" \
		--make="$(MAKE)" \
		--mflags="$(MFLAGS)" \
		--make-flags="$(MAKEFLAGS)"
EXTMK_ARGS    =	$(SCRIPT_ARGS) --extout="$(EXTOUT)" --extension $(EXTS) --extstatic $(EXTSTATIC) --

all: $(MKFILES) $(PREP) $(RBCONFIG) $(LIBRUBY)
	@$(MINIRUBY) $(srcdir)/ext/extmk.rb $(EXTMK_ARGS)

miniruby$(EXEEXT): config.status $(LIBRUBY_A) $(MAINOBJ) $(OBJS) $(DMYEXT)

$(PROGRAM): $(LIBRUBY) $(MAINOBJ) $(OBJS) $(EXTOBJS) $(SETUP) $(PREP)

$(LIBRUBY_A):	$(OBJS) $(DMYEXT)

$(LIBRUBY_SO):	$(OBJS) $(DLDOBJS) $(PREP) $(ARCHFILE)

static-ruby: $(MAINOBJ) $(EXTOBJS) $(LIBRUBY_A)
	@$(RM) $@
	$(PURIFY) $(CC) $(LDFLAGS) $(XLDFLAGS) $(MAINLIBS) $(MAINOBJ) $(EXTOBJS) $(LIBRUBY_A) $(LIBS) $(OUTFLAG)$@

ruby.imp: $(LIBRUBY_A)
	@$(NM) -Pgp $(LIBRUBY_A) | awk 'BEGIN{print "#!"}; $$2~/^[BD]$$/{print $$1}' | sort -u -o $@

install: install-nodoc $(RDOCTARGET)
install-all: install-nodoc install-doc

install-nodoc: install-local install-ext
install-local: $(RBCONFIG)
	$(MINIRUBY) $(srcdir)/instruby.rb $(SCRIPT_ARGS) --mantype="$(MANTYPE)"
install-ext: $(RBCONFIG)
	$(MINIRUBY) $(srcdir)/ext/extmk.rb $(EXTMK_ARGS) install

what-where-all no-install-all: no-install no-install-doc
what-where no-install: no-install-local no-install-ext
what-where-local: no-install-local
no-install-local: $(RBCONFIG)
	$(MINIRUBY) $(srcdir)/instruby.rb -n $(SCRIPT_ARGS) --mantype="$(MANTYPE)"
what-where-ext: no-install-ext
no-install-ext: $(RBCONFIG)
	$(MINIRUBY) $(srcdir)/ext/extmk.rb -n $(EXTMK_ARGS) install

install-doc: $(PROGRAM)
	@echo Generating RDoc documentation
	$(RUNRUBY) "$(srcdir)/bin/rdoc" --all --ri --op "$(RIDATADIR)" "$(srcdir)"

clean: clean-ext clean-local
clean-local::
	@$(RM) $(OBJS) $(MAINOBJ) $(WINMAINOBJ) $(LIBRUBY_A) $(LIBRUBY_SO) $(LIBRUBY_ALIASES)
	@$(RM) ext/extinit.c ext/extinit.$(OBJEXT) dmyext.$(OBJEXT)
	@$(RM) $(PROGRAM) $(WPROGRAM) miniruby$(EXEEXT)
clean-ext:
	@-$(MINIRUBY) $(srcdir)/ext/extmk.rb $(EXTMK_ARGS) clean

distclean: distclean-ext distclean-local
distclean-local:: clean-local
	@$(RM) $(MKFILES) config.h rbconfig.rb $(RBCONFIG)
	@$(RM) ext/config.cache config.cache config.log config.status
	@$(RM) *~ *.bak *.stackdump core *.core gmon.out y.tab.c y.output ruby.imp
distclean-ext:
	@-$(MINIRUBY) $(srcdir)/ext/extmk.rb $(EXTMK_ARGS) distclean 2> $(NULL)

realclean:: distclean
	@$(RM) parse.c lex.c

test: miniruby$(EXEEXT) $(RBCONFIG) $(PROGRAM) PHONY
	@$(MINIRUBY) $(srcdir)/rubytest.rb

test-all:
	$(RUNRUBY) -C "$(srcdir)/test" runner.rb --runner=$(TESTUI) $(TESTS)

extconf:
	$(MINIRUBY) -I$(srcdir)/lib -run -e mkdir -- -p "$(EXTCONFDIR)"
	$(RUNRUBY) -C "$(EXTCONFDIR)" $(EXTCONF) $(EXTCONFARGS)

$(RBCONFIG): $(srcdir)/mkconfig.rb config.status $(PREP)
	@$(MINIRUBY) $(srcdir)/mkconfig.rb -timestamp=$@ \
		-install_name=$(RUBY_INSTALL_NAME) \
		-so_name=$(RUBY_SO_NAME) rbconfig.rb

.PRECIOUS: $(MKFILES)

.PHONY: test install install-nodoc install-doc

PHONY:

{$(VPATH)}parse.c: parse.y
ext/extinit.$(OBJEXT): ext/extinit.c $(SETUP)
	$(CC) $(CFLAGS) $(XCFLAGS) $(CPPFLAGS) $(OUTFLAG)$@ -c ext/extinit.c

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
vsnprintf.$(OBJEXT): {$(VPATH)}vsnprintf.c
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

ascii.$(OBJEXT): {$(VPATH)}ascii.c {$(VPATH)}regenc.h \
  {$(VPATH)}oniguruma.h config.h
array.$(OBJEXT): {$(VPATH)}array.c {$(VPATH)}ruby.h config.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h \
  {$(VPATH)}util.h {$(VPATH)}st.h
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
dmyext.$(OBJEXT): {$(VPATH)}dmyext.c
enum.$(OBJEXT): {$(VPATH)}enum.c {$(VPATH)}ruby.h config.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h \
  {$(VPATH)}node.h {$(VPATH)}util.h
error.$(OBJEXT): {$(VPATH)}error.c {$(VPATH)}ruby.h config.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h \
  {$(VPATH)}env.h {$(VPATH)}version.h {$(VPATH)}st.h
euc_jp.$(OBJEXT): {$(VPATH)}euc_jp.c {$(VPATH)}regenc.h \
  {$(VPATH)}oniguruma.h
eval.$(OBJEXT): {$(VPATH)}eval.c {$(VPATH)}ruby.h config.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h \
  {$(VPATH)}node.h {$(VPATH)}env.h {$(VPATH)}util.h \
  {$(VPATH)}rubysig.h {$(VPATH)}st.h {$(VPATH)}dln.h
file.$(OBJEXT): {$(VPATH)}file.c {$(VPATH)}ruby.h config.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h \
  {$(VPATH)}rubyio.h {$(VPATH)}rubysig.h {$(VPATH)}util.h \
  {$(VPATH)}dln.h
gc.$(OBJEXT): {$(VPATH)}gc.c {$(VPATH)}ruby.h config.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h \
  {$(VPATH)}rubysig.h {$(VPATH)}st.h {$(VPATH)}node.h \
  {$(VPATH)}env.h {$(VPATH)}re.h {$(VPATH)}regex.h
hash.$(OBJEXT): {$(VPATH)}hash.c {$(VPATH)}ruby.h config.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h \
  {$(VPATH)}st.h {$(VPATH)}util.h {$(VPATH)}rubysig.h
inits.$(OBJEXT): {$(VPATH)}inits.c {$(VPATH)}ruby.h config.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h
io.$(OBJEXT): {$(VPATH)}io.c {$(VPATH)}ruby.h config.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h \
  {$(VPATH)}rubyio.h {$(VPATH)}rubysig.h {$(VPATH)}env.h \
  {$(VPATH)}util.h
main.$(OBJEXT): {$(VPATH)}main.c {$(VPATH)}ruby.h config.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h
marshal.$(OBJEXT): {$(VPATH)}marshal.c {$(VPATH)}ruby.h config.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h \
  {$(VPATH)}rubyio.h {$(VPATH)}st.h {$(VPATH)}util.h
math.$(OBJEXT): {$(VPATH)}math.c {$(VPATH)}ruby.h config.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h
numeric.$(OBJEXT): {$(VPATH)}numeric.c {$(VPATH)}ruby.h config.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h
object.$(OBJEXT): {$(VPATH)}object.c {$(VPATH)}ruby.h config.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h \
  {$(VPATH)}st.h {$(VPATH)}util.h
pack.$(OBJEXT): {$(VPATH)}pack.c {$(VPATH)}ruby.h config.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h
parse.$(OBJEXT): {$(VPATH)}parse.c {$(VPATH)}ruby.h config.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h \
  {$(VPATH)}env.h {$(VPATH)}node.h {$(VPATH)}st.h \
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
reggnu.$(OBJEXT): {$(VPATH)}reggnu.c {$(VPATH)}regint.h \
  {$(VPATH)}regenc.h {$(VPATH)}oniguruma.h {$(VPATH)}oniggnu.h \
  config.h
regparse.$(OBJEXT): {$(VPATH)}regparse.c {$(VPATH)}oniguruma.h \
  {$(VPATH)}regint.h {$(VPATH)}regparse.h {$(VPATH)}regenc.h config.h
ruby.$(OBJEXT): {$(VPATH)}ruby.c {$(VPATH)}ruby.h config.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h \
  {$(VPATH)}dln.h {$(VPATH)}node.h {$(VPATH)}util.h
signal.$(OBJEXT): {$(VPATH)}signal.c {$(VPATH)}ruby.h config.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h \
  {$(VPATH)}rubysig.h
sjis.$(OBJEXT): {$(VPATH)}sjis.c {$(VPATH)}regenc.h \
  {$(VPATH)}oniguruma.h config.h
sprintf.$(OBJEXT): {$(VPATH)}sprintf.c {$(VPATH)}ruby.h config.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h
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
  {$(VPATH)}env.h {$(VPATH)}node.h {$(VPATH)}st.h {$(VPATH)}util.h
version.$(OBJEXT): {$(VPATH)}version.c {$(VPATH)}ruby.h config.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h \
  {$(VPATH)}version.h
