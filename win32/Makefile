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
#CFLAGS = -nologo -DNT=1 -Zi -MD
#LDFLAGS = $(CFLAGS) -Fm -MD
XLDFLAGS = 
EXTLIBS = 
LIBS = advapi32.lib wsock32.lib $(EXTLIBS)
MISSING = crypt.obj alloca.obj win32.obj fnmatch.obj isinf.obj isnan.obj
LDSHARED = 
DLDFLAGS = 
SOLIBS = 

RUBY_INSTALL_NAME=ruby
EXEEXT = .exe
PROGRAM=$(RUBY_INSTALL_NAME)$(EXEEXT)

STACK = 0x200000
ORGLIBPATH = $(LIB)

#### End of system configuration section. ####


LIBRUBY       = libruby.lib

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
		math.obj \
		marshal.obj \
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

all:		miniruby$(EXEEXT) rbconfig.rb ext/Setup $(MISCLIBS)
		set LIB=..\..\win32;$(ORGLIBPATH)
		@.\miniruby$(EXEEXT) -Xext extmk.rb static

miniruby$(EXEEXT):	$(OBJS) $(MAINOBJ) $(EXTOBJS) 
		@echo $(EXTOBJS)
		@echo $(LIBS)
		@rm -f miniruby$(EXEEXT)
		$(PURIFY) $(CC) $(LDFLAGS) $(MAINOBJ) $(EXTOBJS) $(OBJS) $(LIBS) -o $@

$(PROGRAM):     $(LIBRUBY) $(MAINOBJ) rubymw.dll
		@rm -f $(PROGRAM)
		$(CC) $(LDFLAGS) $(MAINOBJ) -o $(PROGRAM) rubymw.lib -link /STACK:$(STACK)

rubymw.dll:       $(LIBRUBY) $(EXTOBJS) 
		set LIB=.\win32;$(ORGLIBPATH)
		@rm -f rubymw.dll
		$(CC) $(LDFLAGS) $(MAINOBJ) $(EXTOBJS) $(LIBRUBY) $(LIBS) -o rubymw.dll  -link /DLL /DEF:ruby.def
		@mv rubymw.map rubydll.map

$(LIBRUBY):     $(OBJS)
		lib /OUT:$(LIBRUBY) $(OBJS)

install:	rbconfig.rb
		.\miniruby.exe $(srcdir)/instruby.rb $(DESTDIR)

clean:;		@rm -f $(OBJS) $(LIBRUBY) rbconfig.rb
		@rm -f ext/extinit.c ext/extinit.obj ext/vc*.pdb *.obj
		@.\miniruby$(EXEEXT) -Xext extmk.rb clean

distclean:	clean
		@rm -f Makefile ext/extmk.rb config.h
		@rm -f ext/config.cache config.cache config.log config.status
		@rm -f *~ core *.core gmon.out y.tab.c y.output ruby.imp
		@rm -f *.map rubymw.* ruby.def
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

alloca.obj: missing/alloca.c
	$(CC) -I. $(CFLAGS) $(CPPFLAGS) -c missing/alloca.c

crypt.obj: missing/crypt.c
	$(CC) -I. $(CFLAGS) $(CPPFLAGS) -c missing/crypt.c

dup2.obj: missing/dup2.c
	$(CC) -I. $(CFLAGS) $(CPPFLAGS) -c missing/dup2.c

flock.obj: missing/flock.c
	$(CC) -I. $(CFLAGS) $(CPPFLAGS) -c missing/flock.c

memmove.obj: missing/memmove.c
	$(CC) $(CFLAGS) $(CPPFLAGS) -c missing/memmove.c

mkdir.obj: missing/mkdir.c
	$(CC) $(CFLAGS) $(CPPFLAGS) -c missing/mkdir.c

strerror.obj: missing/strerror.c
	$(CC) $(CFLAGS) $(CPPFLAGS) -c missing/strerror.c

strdup.obj: missing/strdup.c
	$(CC) $(CFLAGS) $(CPPFLAGS) -c missing/strdup.c

strftime.obj: missing/strftime.c
	$(CC) -I. $(CFLAGS) $(CPPFLAGS) -c missing/strftime.c

strstr.obj: missing/strstr.c
	$(CC) $(CFLAGS) $(CPPFLAGS) -c missing/strstr.c

strtol.obj: missing/strtol.c
	$(CC) $(CFLAGS) $(CPPFLAGS) -c missing/strtol.c

strtoul.obj: missing/strtoul.c
	$(CC) $(CFLAGS) $(CPPFLAGS) -c missing/strtoul.c

fnmatch.obj: missing/fnmatch.c
	$(CC) $(CFLAGS) $(CPPFLAGS) -c missing/fnmatch.c

isinf.obj: missing/isinf.c
	$(CC) $(CFLAGS) $(CPPFLAGS) -c missing/isinf.c

isnan.obj: missing/isnan.c
	$(CC) $(CFLAGS) $(CPPFLAGS) -c missing/isnan.c

# when I use -I., there is confliction at "OpenFile" 
# so, set . into environment varible "include"
win32.obj: win32/win32.c
	@set include=$(INCLUDE);.
	$(CC) $(CFLAGS) $(CPPFLAGS) -c win32/win32.c

parse.c: parse.y
	$(YACC) $(YFLAGS) parse.y
	sed -e "s!^extern char \*getenv();!/* & */!" y.tab.c > parse.c
	@rm y.tab.c

# Prevent GNU make v3 from overflowing arg limit on SysV.
.NOEXPORT:
###
parse.obj : parse.y ruby.h defines.h config.h env.h node.h st.h regex.h 
###
array.obj: array.c ruby.h config.h defines.h
bignum.obj: bignum.c ruby.h config.h defines.h
class.obj: class.c ruby.h config.h defines.h node.h st.h
compar.obj: compar.c ruby.h config.h defines.h
dir.obj: dir.c ruby.h config.h defines.h
dln.obj: dln.c config.h defines.h dln.h st.h
dmyext.obj: dmyext.c
enum.obj: enum.c ruby.h config.h defines.h
error.obj: error.c ruby.h config.h defines.h env.h
eval.obj: eval.c ruby.h config.h defines.h env.h node.h rubysig.h st.h dln.h
file.obj: file.c ruby.h config.h defines.h rubyio.h rubysig.h
gc.obj: gc.c ruby.h config.h defines.h env.h rubysig.h st.h node.h re.h regex.h
hash.obj: hash.c ruby.h config.h defines.h st.h
inits.obj: inits.c ruby.h config.h defines.h
io.obj: io.c ruby.h config.h defines.h rubyio.h rubysig.h
main.obj: main.c
math.obj: math.c ruby.h config.h defines.h
numeric.obj: numeric.c ruby.h config.h defines.h
object.obj: object.c ruby.h config.h defines.h st.h
pack.obj: pack.c ruby.h config.h defines.h
process.obj: process.c ruby.h config.h defines.h rubysig.h st.h
random.obj: random.c ruby.h config.h defines.h
range.obj: range.c ruby.h config.h defines.h
re.obj: re.c ruby.h config.h defines.h re.h regex.h
regex.obj: regex.c config.h defines.h regex.h util.h
ruby.obj: ruby.c ruby.h config.h defines.h re.h regex.h dln.h
signal.obj: signal.c ruby.h config.h defines.h rubysig.h
sprintf.obj: sprintf.c ruby.h config.h defines.h
st.obj: st.c config.h st.h
string.obj: string.c ruby.h config.h defines.h re.h regex.h
struct.obj: struct.c ruby.h config.h defines.h
time.obj: time.c ruby.h config.h defines.h
util.obj: util.c defines.h config.h util.h
variable.obj: variable.c ruby.h config.h defines.h env.h st.h
version.obj: version.c ruby.h config.h defines.h version.h
director.obj : director.c dir.h
prec.obj: prec.c ruby.h config.h defines.h
