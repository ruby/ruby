SHELL = $(COMPSEC)

#### Start of system configuration section. ####

srcdir = .
VPATH = .:./missing

CC = cl
YACC = byacc
PURIFY =
AUTOCONF = autoconf


prefix = 
CFLAGS = -nologo -DNT=1 -Ox -I. -I./missing
LDFLAGS = $(CFLAGS) -Fm
#CFLAGS = -nologo -DNT=1 -Zi -I. -I./missing
#LDFLAGS = $(CFLAGS) -Fm
XLDFLAGS = 
#EXTLIBS = 
LIBS = user32.lib advapi32.lib wsock32.lib $(EXTLIBS)
MISSING = crypt.obj alloca.obj win32.obj isinf.obj isnan.obj
LDSHARED = 
DLDFLAGS = 
SOLIBS = 

RUBY_INSTALL_NAME=ruby
EXEEXT = .exe
PROGRAM=$(RUBY_INSTALL_NAME)$(EXEEXT)

STACK = 0x2000000
ORGLIBPATH = $(LIB)

#### End of system configuration section. ####

LIBRUBY_A     = libruby.lib
LIBRUBY_SO    = rubymw.dll
LIBRUBY       = $(LIBRUBY_SO)
LIBRUBYARG    = rubymw.lib

EXTOBJS       = dmyext.obj

MAINOBJ       = main.obj

OBJS          = array.obj \
		bignum.obj \
		class.obj \
		compar.obj \
		dir.obj \
		dln.obj \
		enum.obj \
		error.obj \
		eval.obj \
		file.obj \
		gc.obj \
		hash.obj \
		inits.obj \
		io.obj \
		marshal.obj \
		math.obj \
		numeric.obj \
		object.obj \
		pack.obj \
		parse.obj \
		prec.obj \
		process.obj \
		random.obj \
		range.obj \
		re.obj \
		regex.obj \
		ruby.obj \
		signal.obj \
		sprintf.obj \
		st.obj \
		string.obj \
		struct.obj \
		time.obj \
		util.obj \
		variable.obj \
		version.obj \
		$(MISSING)

all:		miniruby$(EXEEXT) rbconfig.rb ext/extmk.rb ext/Setup rubymw.lib $(MISCLIBS)
		set LIB=..\..\win32;$(ORGLIBPATH)
		@.\miniruby$(EXEEXT) -Xext extmk.rb

ext/extmk.rb:	ext/extmk.rb.in rbconfig.rb
		@echo Creating ext/extmk.rb
		@.\miniruby$(EXEEXT) -Xext mswin32_extmk.rb

miniruby$(EXEEXT):	$(OBJS) $(MAINOBJ) $(EXTOBJS) 
		@echo $(EXTOBJS)
		@echo $(LIBS)
		$(PURIFY) $(CC) $(LDFLAGS) $(MAINOBJ) $(EXTOBJS) $(OBJS) $(LIBS) -o $@

$(PROGRAM):	$(LIBRUBY) $(MAINOBJ) $(LIBRUBY_SO)
		$(PURIFY) $(CC) $(LDFLAGS) $(XLDFLAGS) $(MAINOBJ) -o $@ $(LIBRUBYARG) -link /STACK:$(STACK)

$(LIBRUBY_A):	$(OBJS) dmyext.obj
		lib -nologo /OUT:$@ $(OBJS) dmyext.obj

rubymw.lib:	ruby.def
		lib -nologo /OUT:$@ /DEF:ruby.def

$(LIBRUBY_SO):	$(LIBRUBY_A) $(EXTOBJS) ruby.def
		set LIB=.\win32;$(ORGLIBPATH)
		$(CC) $(LDFLAGS) $(MAINOBJ) $(EXTOBJS) $(LIBRUBY_A) $(LIBS) -o $@ -link /DLL /DEF:ruby.def

install:	rbconfig.rb
		.\miniruby.exe $(srcdir)/instruby.rb $(DESTDIR)

clean:;		@rm -f $(OBJS) $(LIBRUBY_A) $(MAINOBJ) rbconfig.rb
		@rm -f ext/extinit.c ext/extinit.obj ext/vc*.pdb *.obj
		@-.\miniruby$(EXEEXT) -Xext extmk.rb clean

distclean:	clean
		@rm -f Makefile ext/extmk.rb config.h
		@rm -f ext/config.cache config.cache config.log config.status
		@rm -f *~ core *.core gmon.out y.tab.c y.output ruby.imp
		@rm -f *.map *.pdb *.ilk rubymw.* ruby.def
		@rm -f $(PROGRAM) miniruby$(EXEEXT)

realclean:	distclean
		@rm -f parse.c
		@rm -f lex.c

test:		miniruby$(EXEEXT)
		@.\miniruby$(EXEEXT) $(srcdir)/rubytest.rb

rbconfig.rb:	miniruby$(EXEEXT)
		@.\miniruby$(EXEEXT) $(srcdir)/mkconfig.rb rbconfig.rb

config.status:	$(srcdir)/configure
#		$(SHELL) ./config.status --recheck

.c.obj:
	$(CC) $(CFLAGS) $(CPPFLAGS) -c $<

parse.c: parse.y
	$(YACC) $(YFLAGS) parse.y
	sed -e "s!^extern char \*getenv();!/* & */!" y.tab.c > parse.c
	@rm y.tab.c

alloca.obj: missing/alloca.c
	$(CC) -I. $(CFLAGS) $(CPPFLAGS) -c missing/alloca.c

crypt.obj: missing/crypt.c
	$(CC) -I. $(CFLAGS) $(CPPFLAGS) -c missing/crypt.c

dup2.obj: missing/dup2.c
	$(CC) -I. $(CFLAGS) $(CPPFLAGS) -c missing/dup2.c

finite.obj: missing/finite.c
	$(CC) -I. $(CFLAGS) $(CPPFLAGS) -c missing/finite.c

flock.obj: missing/flock.c
	$(CC) -I. $(CFLAGS) $(CPPFLAGS) -c missing/flock.c

isinf.obj: missing/isinf.c
	$(CC) -I. $(CFLAGS) $(CPPFLAGS) -c missing/isinf.c

isnan.obj: missing/isnan.c
	$(CC) -I. $(CFLAGS) $(CPPFLAGS) -c missing/isnan.c

memcmp.obj: missing/memcmp.c
	$(CC) $(CFLAGS) $(CPPFLAGS) -c missing/memcmp.c

memmove.obj: missing/memmove.c
	$(CC) $(CFLAGS) $(CPPFLAGS) -c missing/memmove.c

mkdir.obj: missing/mkdir.c
	$(CC) $(CFLAGS) $(CPPFLAGS) -c missing/mkdir.c

vsnprintf.obj: missing/vsnprintf.c
	$(CC) $(CFLAGS) $(CPPFLAGS) -c missing/vsnprintf.c

strcasecmp.obj: missing/strcasecmp.c
	$(CC) $(CFLAGS) $(CPPFLAGS) -c missing/strcasecmp.c

strncasecmp.obj: missing/strncasecmp.c
	$(CC) $(CFLAGS) $(CPPFLAGS) -c missing/strncasecmp.c

strchr.obj: missing/strchr.c
	$(CC) $(CFLAGS) $(CPPFLAGS) -c missing/strchr.c

strdup.obj: missing/strdup.c
	$(CC) $(CFLAGS) $(CPPFLAGS) -c missing/strdup.c

strerror.obj: missing/strerror.c
	$(CC) $(CFLAGS) $(CPPFLAGS) -c missing/strerror.c

strftime.obj: missing/strftime.c
	$(CC) -I. $(CFLAGS) $(CPPFLAGS) -c missing/strftime.c

strstr.obj: missing/strstr.c
	$(CC) $(CFLAGS) $(CPPFLAGS) -c missing/strstr.c

strtod.obj: missing/strtod.c
	$(CC) $(CFLAGS) $(CPPFLAGS) -c missing/strtod.c

strtol.obj: missing/strtol.c
	$(CC) $(CFLAGS) $(CPPFLAGS) -c missing/strtol.c

strtoul.obj: missing/strtoul.c
	$(CC) $(CFLAGS) $(CPPFLAGS) -c missing/strtoul.c

nt.obj: missing/nt.c
	$(CC) $(CFLAGS) $(CPPFLAGS) -c missing/nt.c

x68.obj: missing/x68.c
	$(CC) $(CFLAGS) $(CPPFLAGS) -c missing/x68.c

os2.obj: missing/os2.c
	$(CC) $(CFLAGS) $(CPPFLAGS) -c missing/os2.c

dl_os2.obj: missing/dl_os2.c
	$(CC) $(CFLAGS) $(CPPFLAGS) -c missing/dl_os2.c

# when I use -I., there is confliction at "OpenFile" 
# so, set . into environment varible "include"
win32.obj: win32/win32.c
	@set include=$(INCLUDE);.
	$(CC) $(CFLAGS) $(CPPFLAGS) -c win32/win32.c

# Prevent GNU make v3 from overflowing arg limit on SysV.
.NOEXPORT:
###
parse.obj: parse.y ruby.h config.h defines.h intern.h env.h node.h st.h regex.h util.h lex.c
###
array.obj: array.c ruby.h config.h defines.h intern.h
bignum.obj: bignum.c ruby.h config.h defines.h intern.h
class.obj: class.c ruby.h config.h defines.h intern.h node.h st.h
compar.obj: compar.c ruby.h config.h defines.h intern.h
dir.obj: dir.c ruby.h config.h defines.h intern.h
dln.obj: dln.c config.h defines.h dln.h
dmyext.obj: dmyext.c
enum.obj: enum.c ruby.h config.h defines.h intern.h
error.obj: error.c ruby.h config.h defines.h intern.h env.h
eval.obj: eval.c ruby.h config.h defines.h intern.h node.h env.h rubysig.h st.h dln.h
file.obj: file.c ruby.h config.h defines.h intern.h rubyio.h rubysig.h
gc.obj: gc.c ruby.h config.h defines.h intern.h rubysig.h st.h node.h env.h re.h regex.h
hash.obj: hash.c ruby.h config.h defines.h intern.h st.h rubysig.h util.h
inits.obj: inits.c ruby.h config.h defines.h intern.h
io.obj: io.c ruby.h config.h defines.h intern.h rubyio.h rubysig.h env.h
main.obj: main.c ruby.h config.h defines.h intern.h
marshal.obj: marshal.c ruby.h config.h defines.h intern.h rubyio.h st.h
prec.obj: prec.c ruby.h config.h defines.h intern.h
math.obj: math.c ruby.h config.h defines.h intern.h
numeric.obj: numeric.c ruby.h config.h defines.h intern.h
object.obj: object.c ruby.h config.h defines.h intern.h st.h
pack.obj: pack.c ruby.h config.h defines.h intern.h
process.obj: process.c ruby.h config.h defines.h intern.h rubysig.h st.h
random.obj: random.c ruby.h config.h defines.h intern.h
range.obj: range.c ruby.h config.h defines.h intern.h
re.obj: re.c ruby.h config.h defines.h intern.h re.h regex.h
regex.obj: regex.c config.h regex.h util.h
ruby.obj: ruby.c ruby.h config.h defines.h intern.h dln.h util.h
signal.obj: signal.c ruby.h config.h defines.h intern.h rubysig.h
sprintf.obj: sprintf.c ruby.h config.h defines.h intern.h
st.obj: st.c config.h st.h
string.obj: string.c ruby.h config.h defines.h intern.h re.h regex.h
struct.obj: struct.c ruby.h config.h defines.h intern.h
time.obj: time.c ruby.h config.h defines.h intern.h
util.obj: util.c ruby.h config.h defines.h intern.h util.h
variable.obj: variable.c ruby.h config.h defines.h intern.h env.h node.h st.h
version.obj: version.c ruby.h config.h defines.h intern.h version.h
