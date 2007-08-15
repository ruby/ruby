bin: $(PROGRAM) $(WPROGRAM)
lib: $(LIBRUBY);
dll: $(LIBRUBY_SO);

RUBYOPT       =

STATIC_RUBY   = static-ruby

EXTCONF       = extconf.rb
RBCONFIG      = ./.rbconfig.time

DMYEXT	      = dmyext.$(OBJEXT)
MAINOBJ	      = main.$(OBJEXT)
EXTOBJS	      = 
DLDOBJS	      = $(DMYEXT)

OBJS	      = array.$(OBJEXT) \
		bignum.$(OBJEXT) \
		class.$(OBJEXT) \
		compar.$(OBJEXT) \
		dir.$(OBJEXT) \
		dln.$(OBJEXT) \
		enum.$(OBJEXT) \
		error.$(OBJEXT) \
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
		regex.$(OBJEXT) \
		ruby.$(OBJEXT) \
		signal.$(OBJEXT) \
		sprintf.$(OBJEXT) \
		st.$(OBJEXT) \
		string.$(OBJEXT) \
		struct.$(OBJEXT) \
		time.$(OBJEXT) \
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
prog: $(PROGRAM) $(WPROGRAM)

miniruby$(EXEEXT): config.status $(LIBRUBY_A) $(MAINOBJ) $(MINIOBJS) $(OBJS) $(DMYEXT)

$(PROGRAM): $(LIBRUBY) $(MAINOBJ) $(OBJS) $(EXTOBJS) $(SETUP) $(PREP)

$(LIBRUBY_A):	$(OBJS) $(DMYEXT) $(ARCHFILE)

$(LIBRUBY_SO):	$(OBJS) $(DLDOBJS) $(LIBRUBY_A) $(PREP)

$(STATIC_RUBY)$(EXEEXT): $(MAINOBJ) $(DLDOBJS) $(EXTOBJS) $(LIBRUBY_A)
	@$(RM) $@
	$(PURIFY) $(CC) $(MAINOBJ) $(DLDOBJS) $(EXTOBJS) $(LIBRUBY_A) $(MAINLIBS) $(EXTLIBS) $(LIBS) $(OUTFLAG)$@ $(LDFLAGS) $(XLDFLAGS)

ruby.imp: $(OBJS)
	@$(NM) -Pgp $(OBJS) | awk 'BEGIN{print "#!"}; $$2~/^[BD]$$/{print $$1}' | sort -u -o $@

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
	$(PREINSTALL)
pre-install-ext:: PHONY
pre-install-doc:: PHONY

post-install: post-install-local post-install-ext
post-install-local:: PHONY
post-install-ext:: PHONY
post-install-doc:: PHONY

clean: clean-ext clean-local
clean-local::
	@$(RM) $(OBJS) $(MAINOBJ) $(WINMAINOBJ) $(LIBRUBY_A) $(LIBRUBY_SO) $(LIBRUBY) $(LIBRUBY_ALIASES)
	@$(RM) $(PROGRAM) $(WPROGRAM) miniruby$(EXEEXT) dmyext.$(OBJEXT) $(ARCHFILE)
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

.PHONY: test install install-nodoc install-doc dist

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
dmydln.$(OBJEXT): {$(VPATH)}dmydln.c {$(VPATH)}dln.c {$(VPATH)}ruby.h \
  config.h {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h \
  {$(VPATH)}dln.h
dmyext.$(OBJEXT): {$(VPATH)}dmyext.c
enum.$(OBJEXT): {$(VPATH)}enum.c {$(VPATH)}ruby.h config.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h \
  {$(VPATH)}node.h {$(VPATH)}util.h
error.$(OBJEXT): {$(VPATH)}error.c {$(VPATH)}ruby.h config.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h \
  {$(VPATH)}env.h {$(VPATH)}st.h
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
  {$(VPATH)}rubyio.h {$(VPATH)}rubysig.h  {$(VPATH)}util.h \
  {$(VPATH)}env.h
main.$(OBJEXT): {$(VPATH)}main.c {$(VPATH)}ruby.h config.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h
marshal.$(OBJEXT): {$(VPATH)}marshal.c {$(VPATH)}ruby.h config.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h \
  {$(VPATH)}rubyio.h {$(VPATH)}st.h {$(VPATH)}util.h
math.$(OBJEXT): {$(VPATH)}math.c {$(VPATH)}ruby.h config.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h
numeric.$(OBJEXT): {$(VPATH)}numeric.c {$(VPATH)}ruby.h config.h \
  {$(VPATH)}env.h {$(VPATH)}defines.h {$(VPATH)}intern.h \
  {$(VPATH)}missing.h
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
regex.$(OBJEXT): {$(VPATH)}regex.c config.h {$(VPATH)}regex.h
ruby.$(OBJEXT): {$(VPATH)}ruby.c {$(VPATH)}ruby.h config.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h \
  {$(VPATH)}dln.h {$(VPATH)}node.h {$(VPATH)}util.h
signal.$(OBJEXT): {$(VPATH)}signal.c {$(VPATH)}ruby.h config.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h \
  {$(VPATH)}rubysig.h
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
util.$(OBJEXT): {$(VPATH)}util.c {$(VPATH)}ruby.h config.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h \
  {$(VPATH)}util.h
variable.$(OBJEXT): {$(VPATH)}variable.c {$(VPATH)}ruby.h config.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h \
  {$(VPATH)}env.h {$(VPATH)}node.h {$(VPATH)}st.h {$(VPATH)}util.h
version.$(OBJEXT): {$(VPATH)}version.c {$(VPATH)}ruby.h config.h \
  {$(VPATH)}defines.h {$(VPATH)}intern.h {$(VPATH)}missing.h \
  {$(VPATH)}version.h

dist: $(PROGRAM)
	$(RUNRUBY) $(srcdir)/distruby.rb
