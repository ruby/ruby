bin: $(PROGRAM) $(WPROGRAM)
lib: $(LIBRUBY)
dll: $(LIBRUBY_SO)

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
MAINOBJ	      = main.$(OBJEXT)
EXTOBJS	      = 
DLDOBJS	      = $(DMYEXT)
MINIOBJS      = $(ARCHMINIOBJS) miniprelude.$(OBJEXT)

COMMONOBJS    = array.$(OBJEXT) \
		bignum.$(OBJEXT) \
		class.$(OBJEXT) \
		compar.$(OBJEXT) \
		dir.$(OBJEXT) \
		enum.$(OBJEXT) \
		enumerator.$(OBJEXT) \
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

OBJS          = $(COMMONOBJS) \
		dln.$(OBJEXT) \
		prelude.$(OBJEXT)

PRELUDE_SCRIPTS = $(srcdir)/prelude.rb
PRELUDES      = prelude.c miniprelude.c

SCRIPT_ARGS   =	--dest-dir="$(DESTDIR)" \
		--extout="$(EXTOUT)" \
		--mflags="$(MFLAGS)" \
		--make-flags="$(MAKEFLAGS)"
EXTMK_ARGS    =	$(SCRIPT_ARGS) --extension $(EXTS) --extstatic $(EXTSTATIC) \
		--make-flags="MINIRUBY='$(MINIRUBY)'" --
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

VCS           = svn

COMPILE_PRELUDE = $(MINIRUBY) -I$(srcdir) $(srcdir)/compile_prelude.rb

all: main $(RDOCTARGET)

main: exts
	@$(RUNCMD) $(MKMAIN_CMD) $(MAKE)

exts: $(MKMAIN_CMD)

$(MKMAIN_CMD): $(MKFILES) $(PREP) $(RBCONFIG) $(LIBRUBY)
	@$(MINIRUBY) $(srcdir)/ext/extmk.rb --make="$(MAKE)" --command-output=$@ $(EXTMK_ARGS)

prog: $(PROGRAM) $(WPROGRAM)

miniruby$(EXEEXT): config.status $(MAINOBJ) $(MINIOBJS) $(COMMONOBJS) $(DMYEXT)

$(PROGRAM): $(LIBRUBY) $(MAINOBJ) $(OBJS) $(EXTOBJS) $(SETUP) $(PREP)

$(LIBRUBY_A):	$(OBJS) $(DMYEXT) $(ARCHFILE)

$(LIBRUBY_SO):	$(OBJS) $(DLDOBJS) $(LIBRUBY_A) $(PREP) $(LIBRUBY_SO_UPDATE)

$(LIBRUBY_EXTS):
	@exit > $@

$(STATIC_RUBY)$(EXEEXT): $(MAINOBJ) $(DLDOBJS) $(EXTOBJS) $(LIBRUBY_A)
	@$(RM) $@
	$(PURIFY) $(CC) $(MAINOBJ) $(DLDOBJS) $(EXTOBJS) $(LIBRUBY_A) $(MAINLIBS) $(EXTLIBS) $(LIBS) $(OUTFLAG)$@ $(LDFLAGS) $(XLDFLAGS)

ruby.imp: $(OBJS)
	@$(NM) -Pgp $(OBJS) | awk 'BEGIN{print "#!"}; $$2~/^[BD]$$/{print $$1}' | sort -u -o $@

install: install-$(RDOCTARGET)
install-rdoc: install-all
doc-all: rdoc

install-all: doc-all pre-install-all do-install-all post-install-all
pre-install-all:: install-prereq
do-install-all: $(PROGRAM)
	$(MINIRUBY) $(srcdir)/instruby.rb --make="$(MAKE)" $(INSTRUBY_ARGS) --install=all --rdoc-output="$(RDOCOUT)"
post-install-all::
	@$(NULLCMD)

install-nodoc: pre-install-nodoc do-install-nodoc post-install-nodoc
pre-install-nodoc:: pre-install-local pre-install-ext
do-install-nodoc: 
	$(MINIRUBY) $(srcdir)/instruby.rb --make="$(MAKE)" $(INSTRUBY_ARGS) --mantype="$(MANTYPE)"
post-install-nodoc:: post-install-local post-install-ext

install-local: pre-install-local do-install-local post-install-local
pre-install-local:: pre-install-bin pre-install-lib pre-install-man
do-install-local:
	$(MINIRUBY) $(srcdir)/instruby.rb --make="$(MAKE)" $(INSTRUBY_ARGS) --install=local --mantype="$(MANTYPE)"
loadpath: $(PREP)
	$(MINIRUBY) -e 'p $$:'

post-install-local:: post-install-bin post-install-lib post-install-man

install-ext: pre-install-ext do-install-ext post-install-ext
pre-install-ext:: pre-install-ext-arch pre-install-ext-comm
do-install-ext:
	$(MINIRUBY) $(srcdir)/instruby.rb --make="$(MAKE)" $(INSTRUBY_ARGS) --install=ext
post-install-ext:: post-install-ext-arch post-install-ext-comm

install-arch: pre-install-arch do-install-arch post-install-arch
pre-install-arch:: pre-install-bin pre-install-ext-arch
do-install-arch:
	$(MINIRUBY) $(srcdir)/instruby.rb --make="$(MAKE)" $(INSTRUBY_ARGS) --install=bin --install=ext-arch
post-install-arch:: post-install-bin post-install-ext-arch

install-comm: pre-install-comm do-install-comm post-install-comm
pre-install-comm:: pre-install-lib pre-install-ext-comm pre-install-man
do-install-comm:
	$(MINIRUBY) $(srcdir)/instruby.rb --make="$(MAKE)" $(INSTRUBY_ARGS) --install=lib --install=ext-comm --install=man
post-install-comm:: post-install-lib post-install-ext-comm post-install-man

install-bin: pre-install-bin do-install-bin post-install-bin
pre-install-bin:: install-prereq
do-install-bin:
	$(MINIRUBY) $(srcdir)/instruby.rb --make="$(MAKE)" $(INSTRUBY_ARGS) --install=bin
post-install-bin::
	@$(NULLCMD)

install-lib: pre-install-lib do-install-lib post-install-lib
pre-install-lib:: install-prereq
do-install-lib:
	$(MINIRUBY) $(srcdir)/instruby.rb --make="$(MAKE)" $(INSTRUBY_ARGS) --install=lib
post-install-lib::
	@$(NULLCMD)

install-ext-comm: pre-install-ext-comm do-install-ext-comm post-install-ext-comm
pre-install-ext-comm:: install-prereq
do-install-ext-comm:
	$(MINIRUBY) $(srcdir)/instruby.rb --make="$(MAKE)" $(INSTRUBY_ARGS) --install=ext-comm
post-install-ext-comm::
	@$(NULLCMD)

install-ext-arch: pre-install-ext-arch do-install-ext-arch post-install-ext-arch
pre-install-ext-arch:: install-prereq
do-install-ext-arch:
	$(MINIRUBY) $(srcdir)/instruby.rb --make="$(MAKE)" $(INSTRUBY_ARGS) --install=ext-arch
post-install-ext-arch::
	@$(NULLCMD)

install-man: pre-install-man do-install-man post-install-man
pre-install-man:: install-prereq
do-install-man:
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
dont-install-nodoc: 
	$(MINIRUBY) $(srcdir)/instruby.rb -n --make="$(MAKE)" $(INSTRUBY_ARGS) --mantype="$(MANTYPE)"
post-no-install-nodoc:: post-no-install-local post-no-install-ext

what-where-local: no-install-local
no-install-local: pre-no-install-local dont-install-local post-no-install-local
pre-no-install-local:: pre-no-install-bin pre-no-install-lib pre-no-install-man
dont-install-local:
	$(MINIRUBY) $(srcdir)/instruby.rb -n --make="$(MAKE)" $(INSTRUBY_ARGS) --install=local --mantype="$(MANTYPE)"
post-no-install-local:: post-no-install-bin post-no-install-lib post-no-install-man

what-where-ext: no-install-ext
no-install-ext: pre-no-install-ext dont-install-ext post-no-install-ext
pre-no-install-ext:: pre-no-install-ext-arch pre-no-install-ext-comm
dont-install-ext:
	$(MINIRUBY) $(srcdir)/instruby.rb -n --make="$(MAKE)" $(INSTRUBY_ARGS) --install=ext
post-no-install-ext:: post-no-install-ext-arch post-no-install-ext-comm

what-where-arch: no-install-arch
no-install-arch: pre-no-install-arch dont-install-arch post-no-install-arch
pre-no-install-arch:: pre-no-install-bin pre-no-install-ext-arch
dont-install-arch:
	$(MINIRUBY) $(srcdir)/instruby.rb -n --make="$(MAKE)" $(INSTRUBY_ARGS) --install=bin --install=ext-arch
post-no-install-arch:: post-no-install-lib post-no-install-man post-no-install-ext-arch

what-where-comm: no-install-comm
no-install-comm: pre-no-install-comm dont-install-comm post-no-install-comm
pre-no-install-comm:: pre-no-install-lib pre-no-install-ext-comm pre-no-install-man
dont-install-comm:
	$(MINIRUBY) $(srcdir)/instruby.rb -n --make="$(MAKE)" $(INSTRUBY_ARGS) --install=lib --install=ext-comm --install=man
post-no-install-comm:: post-no-install-lib post-no-install-ext-comm post-no-install-man

what-where-bin: no-install-bin
no-install-bin: pre-no-install-bin dont-install-bin post-no-install-bin
pre-no-install-bin:: install-prereq
dont-install-bin:
	$(MINIRUBY) $(srcdir)/instruby.rb -n --make="$(MAKE)" $(INSTRUBY_ARGS) --install=bin
post-no-install-bin::
	@$(NULLCMD)

what-where-lib: no-install-lib
no-install-lib: pre-no-install-lib dont-install-lib post-no-install-lib
pre-no-install-lib:: install-prereq
dont-install-lib:
	$(MINIRUBY) $(srcdir)/instruby.rb -n --make="$(MAKE)" $(INSTRUBY_ARGS) --install=lib
post-no-install-lib::
	@$(NULLCMD)

what-where-ext-comm: no-install-ext-comm
no-install-ext-comm: pre-no-install-ext-comm dont-install-ext-comm post-no-install-ext-comm
pre-no-install-ext-comm:: install-prereq
dont-install-ext-comm:
	$(MINIRUBY) $(srcdir)/instruby.rb -n --make="$(MAKE)" $(INSTRUBY_ARGS) --install=ext-comm
post-no-install-ext-comm::
	@$(NULLCMD)

what-where-ext-arch: no-install-ext-arch
no-install-ext-arch: pre-no-install-ext-arch dont-install-ext-arch post-no-install-ext-arch
pre-no-install-ext-arch:: install-prereq
dont-install-ext-arch:
	$(MINIRUBY) $(srcdir)/instruby.rb -n --make="$(MAKE)" $(INSTRUBY_ARGS) --install=ext-arch
post-no-install-ext-arch::
	@$(NULLCMD)

what-where-man: no-install-man
no-install-man: pre-no-install-man dont-install-man post-no-install-man
pre-no-install-man:: install-prereq
dont-install-man:
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
nodoc: PHONY

what-where-doc: no-install-doc
no-install-doc: pre-no-install-doc dont-install-doc post-no-install-doc
pre-no-install-doc:: install-prereq
dont-install-doc::
	$(MINIRUBY) $(srcdir)/instruby.rb -n --make="$(MAKE)" $(INSTRUBY_ARGS) --install=rdoc --rdoc-output="$(RDOCOUT)"
post-no-install-doc::
	@$(NULLCMD)

CLEAR_INSTALLED_LIST = clear-installed-list

install-prereq: $(CLEAR_INSTALLED_LIST)

clear-installed-list:
	@exit > $(INSTALLED_LIST)

clean: clean-ext clean-local
clean-local::
	@$(RM) $(OBJS) $(MINIOBJS) $(MAINOBJ) $(LIBRUBY_A) $(LIBRUBY_SO) $(LIBRUBY) $(LIBRUBY_ALIASES)
	@$(RM) $(PROGRAM) $(WPROGRAM) miniruby$(EXEEXT) dmyext.$(OBJEXT) $(ARCHFILE) .*.time
	@$(RM) y.tab.c y.output
clean-ext::

distclean: distclean-ext distclean-local
distclean-local:: clean-local
	@$(RM) $(MKFILES) config.h rbconfig.rb
	@$(RM) config.cache config.log config.status $(PRELUDES)
	@$(RM) *~ *.bak *.stackdump core *.core gmon.out $(PREP)
distclean-ext::

realclean:: realclean-ext realclean-local
realclean-local:: distclean-local
	@$(RM) parse.c lex.c
realclean-ext::

check: test test-all
check-ruby: test test-ruby

test-knownbug: $(PROGRAM) PHONY
	        $(RUNRUBY) $(srcdir)/KNOWNBUGS.rb

test: miniruby$(EXEEXT) $(RBCONFIG) $(PROGRAM) PHONY
	@$(MINIRUBY) $(srcdir)/rubytest.rb

test-all:
	$(RUNRUBY) "$(srcdir)/test/runner.rb" --basedir="$(TESTSDIR)" --runner=$(TESTUI) $(TESTS)

test-ruby:
	$(RUNRUBY) "$(srcdir)/test/runner.rb" --basedir="$(TESTSDIR)" --runner=$(TESTUI) ruby

extconf:
	$(MAKEDIRS) "$(EXTCONFDIR)"
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
ia64.$(OBJEXT): {$(VPATH)}ia64.s
	$(CC) $(CFLAGS) -c $<

# when I use -I., there is confliction at "OpenFile" 
# so, set . into environment varible "include"
win32.$(OBJEXT): {$(VPATH)}win32.c

###

RUBY_H_INCLUDES = {$(VPATH)}ruby.h {$(VPATH)}config.h {$(VPATH)}defines.h \
		  {$(VPATH)}intern.h {$(VPATH)}missing.h

array.$(OBJEXT): {$(VPATH)}array.c $(RUBY_H_INCLUDES) \
  {$(VPATH)}util.h {$(VPATH)}st.h
bignum.$(OBJEXT): {$(VPATH)}bignum.c $(RUBY_H_INCLUDES) \
  {$(VPATH)}rubysig.h
class.$(OBJEXT): {$(VPATH)}class.c $(RUBY_H_INCLUDES) \
  {$(VPATH)}rubysig.h {$(VPATH)}node.h {$(VPATH)}st.h
compar.$(OBJEXT): {$(VPATH)}compar.c $(RUBY_H_INCLUDES)
dir.$(OBJEXT): {$(VPATH)}dir.c $(RUBY_H_INCLUDES) \
  {$(VPATH)}util.h
dln.$(OBJEXT): {$(VPATH)}dln.c $(RUBY_H_INCLUDES) \
  {$(VPATH)}dln.h
dmydln.$(OBJEXT): {$(VPATH)}dmydln.c dln.$(OBJEXT)
dmyext.$(OBJEXT): {$(VPATH)}dmyext.c
enum.$(OBJEXT): {$(VPATH)}enum.c $(RUBY_H_INCLUDES) \
  {$(VPATH)}node.h {$(VPATH)}util.h
enumerator.$(OBJEXT): {$(VPATH)}enumerator.c $(RUBY_H_INCLUDES)
error.$(OBJEXT): {$(VPATH)}error.c $(RUBY_H_INCLUDES) \
  {$(VPATH)}env.h {$(VPATH)}st.h
eval.$(OBJEXT): {$(VPATH)}eval.c $(RUBY_H_INCLUDES) \
  {$(VPATH)}node.h {$(VPATH)}env.h {$(VPATH)}util.h \
  {$(VPATH)}rubysig.h {$(VPATH)}st.h {$(VPATH)}dln.h
file.$(OBJEXT): {$(VPATH)}file.c $(RUBY_H_INCLUDES) \
  {$(VPATH)}rubyio.h {$(VPATH)}rubysig.h {$(VPATH)}util.h \
  {$(VPATH)}dln.h
gc.$(OBJEXT): {$(VPATH)}gc.c $(RUBY_H_INCLUDES) \
  {$(VPATH)}rubysig.h {$(VPATH)}st.h {$(VPATH)}node.h \
  {$(VPATH)}env.h {$(VPATH)}re.h {$(VPATH)}regex.h
hash.$(OBJEXT): {$(VPATH)}hash.c $(RUBY_H_INCLUDES) \
  {$(VPATH)}st.h {$(VPATH)}util.h {$(VPATH)}rubysig.h
inits.$(OBJEXT): {$(VPATH)}inits.c $(RUBY_H_INCLUDES)
io.$(OBJEXT): {$(VPATH)}io.c $(RUBY_H_INCLUDES) \
  {$(VPATH)}rubyio.h {$(VPATH)}rubysig.h  {$(VPATH)}util.h \
  {$(VPATH)}env.h
main.$(OBJEXT): {$(VPATH)}main.c $(RUBY_H_INCLUDES)
marshal.$(OBJEXT): {$(VPATH)}marshal.c $(RUBY_H_INCLUDES) \
  {$(VPATH)}rubyio.h {$(VPATH)}st.h {$(VPATH)}util.h
math.$(OBJEXT): {$(VPATH)}math.c $(RUBY_H_INCLUDES)
numeric.$(OBJEXT): {$(VPATH)}numeric.c $(RUBY_H_INCLUDES) \
  {$(VPATH)}env.h
object.$(OBJEXT): {$(VPATH)}object.c $(RUBY_H_INCLUDES) \
  {$(VPATH)}st.h {$(VPATH)}util.h
pack.$(OBJEXT): {$(VPATH)}pack.c $(RUBY_H_INCLUDES)
parse.$(OBJEXT): {$(VPATH)}parse.c $(RUBY_H_INCLUDES) \
  {$(VPATH)}env.h {$(VPATH)}node.h {$(VPATH)}st.h \
  {$(VPATH)}regex.h {$(VPATH)}util.h {$(VPATH)}lex.c
prec.$(OBJEXT): {$(VPATH)}prec.c $(RUBY_H_INCLUDES)
process.$(OBJEXT): {$(VPATH)}process.c $(RUBY_H_INCLUDES) \
  {$(VPATH)}rubysig.h {$(VPATH)}st.h
random.$(OBJEXT): {$(VPATH)}random.c $(RUBY_H_INCLUDES)
range.$(OBJEXT): {$(VPATH)}range.c $(RUBY_H_INCLUDES)
re.$(OBJEXT): {$(VPATH)}re.c $(RUBY_H_INCLUDES) \
  {$(VPATH)}re.h {$(VPATH)}regex.h
regex.$(OBJEXT): {$(VPATH)}regex.c config.h {$(VPATH)}regex.h
ruby.$(OBJEXT): {$(VPATH)}ruby.c $(RUBY_H_INCLUDES) \
  {$(VPATH)}dln.h {$(VPATH)}node.h {$(VPATH)}util.h
signal.$(OBJEXT): {$(VPATH)}signal.c $(RUBY_H_INCLUDES) \
  {$(VPATH)}rubysig.h
sprintf.$(OBJEXT): {$(VPATH)}sprintf.c $(RUBY_H_INCLUDES)
st.$(OBJEXT): {$(VPATH)}st.c config.h {$(VPATH)}st.h
string.$(OBJEXT): {$(VPATH)}string.c $(RUBY_H_INCLUDES) \
  {$(VPATH)}re.h {$(VPATH)}regex.h
struct.$(OBJEXT): {$(VPATH)}struct.c $(RUBY_H_INCLUDES)
time.$(OBJEXT): {$(VPATH)}time.c $(RUBY_H_INCLUDES)
util.$(OBJEXT): {$(VPATH)}util.c $(RUBY_H_INCLUDES) \
  {$(VPATH)}util.h
variable.$(OBJEXT): {$(VPATH)}variable.c $(RUBY_H_INCLUDES) \
  {$(VPATH)}env.h {$(VPATH)}node.h {$(VPATH)}st.h {$(VPATH)}util.h
version.$(OBJEXT): {$(VPATH)}version.c $(RUBY_H_INCLUDES) \
  {$(VPATH)}version.h {$(VPATH)}revision.h

srcs: {$(VPATH)}parse.c {$(VPATH)}lex.c

incs: $(srcdir)/revision.h $(REVISION_H)

prelude.c: $(srcdir)/compile_prelude.rb $(RBCONFIG) $(PRELUDE_SCRIPTS) $(PREP)
	$(COMPILE_PRELUDE) $(PRELUDE_SCRIPTS) $@

miniprelude.$(OBJEXT): {$(VPATH)}miniprelude.c $(RUBY_H_INCLUDES)
prelude.$(OBJEXT): {$(VPATH)}prelude.c $(RUBY_H_INCLUDES)

prereq: incs srcs preludes

preludes: {$(VPATH)}miniprelude.c

dist: $(PROGRAM)
	$(RUNRUBY) $(srcdir)/distruby.rb

$(srcdir)/revision.h:
	@exit > $@

$(REVISION_H): $(srcdir)/version.h $(srcdir)/ChangeLog revision.h.tmp $(REVISION_FORCE)

revision.h.tmp: $(REVISION_FORCE)
	@exit > "$@"
	@set LC_ALL=C
	-@($(CHDIR) "$(srcdir)" && $(SET_LC_MESSAGES) $(VCS) info | \
	sed -n \
	  -e "/^URL:/{" \
	  -e   "/\/trunk$$/!s|.*/\([^/][^/]*\)$$|#define RUBY_BRANCH_NAME \"\1\"|p" \
	  -e "}" \
	  -e "s/.*Rev:/#define RUBY_REVISION/p") > "$@"
-IF-NO-STRING-LITERAL-CONCATENATION-::
	@{ \
	echo '#include "$@"'; \
	echo '#include "ruby.h"'; \
	echo '#include "version.h"'; \
	echo '%define_RUBY_DESCRIPTION RUBY_DESCRIPTION'; \
	echo '%define_RUBY_COPYRIGHT RUBY_COPYRIGHT'; \
	} | $(CPP) -I. -I$(srcdir) - | \
	sed '/^%/!d;s//#/;s/_/ /;s/" *"//g' >> "$@"
