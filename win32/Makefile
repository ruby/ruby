SHELL = $(COMPSEC)

#### Start of system configuration section. ####

srcdir = .
VPATH = .:./missing

CC = cl
YACC = byacc
RANLIB = 
AR = 
INSTALL = ginstall -c
INSTALL_PROGRAM = $(INSTALL)
INSTALL_DATA = $(INSTALL) -m 644
PURIFY =


CFLAGS = -nologo -DNT=1 -Ox -I. -I./missing
LDFLAGS =  $(CFLAGS) -Fm
#CFLAGS = -nologo -DNT=1 -Zi -MD 
#LDFLAGS =  $(CFLAGS) -Fm -MD
LIBS =  $(EXTLIBS)  advapi32.lib wsock32.lib
MISSING = crypt.obj setenv.obj vsnprintf.obj alloca.obj nt.obj

prefix = 
binprefix = 
exec_prefix = 
bindir = 
libdir = 

STACK = 0x200000
ORGLIBPATH = $(LIB)
#MISCLIBS = win32\sdbm.lib

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
		fnmatch.obj \
		gc.obj \
		glob.obj \
		hash.obj \
		inits.obj \
		io.obj \
		math.obj \
		marshal.obj \
		numeric.obj \
		object.obj \
		pack.obj \
		parse.obj \
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

all:            miniruby.exe ext/Setup $(MISCLIBS)
		cd ext
		set LIB=..\..\win32;$(ORGLIBPATH)
		..\miniruby .\extmk.rb  static
#		..\miniruby .\extmk.rb
		cd ..

miniruby.exe:   $(OBJS) $(MAINOBJ) $(EXTOBJS) 
		@echo $(EXTOBJS)
		@echo $(LIBS)
		@rm -f miniruby.exe
		$(PURIFY) $(CC) $(LDFLAGS) $(MAINOBJ) $(OBJS) $(EXTOBJS) $(LIBS) -o miniruby.exe

ruby.exe:       $(LIBRUBY) $(MAINOBJ) $(EXTOBJS) rubymw.dll 
		@rm -f ruby.exe
#               $(PURIFY) $(CC) $(LDFLAGS) $(MAINOBJ) $(EXTOBJS) $(LIBRUBY) $(LIBS) -o ruby.exe
		$(CC) $(LDFLAGS) $(MAINOBJ) -o ruby.exe rubymw.lib -link /STACK:$(STACK)

rubymw.dll:       $(LIBRUBY) $(EXTOBJS) 
		set LIB=.\win32;$(ORGLIBPATH)
		@rm -f rubymw.dll
		$(PURIFY) $(CC) $(LDFLAGS) $(MAINOBJ) $(EXTOBJS) $(LIBRUBY) $(LIBS) -o rubymw.dll  -link /DLL /DEF:ruby.def
		@mv rubymw.map rubydll.map

$(LIBRUBY):     $(OBJS)
		lib /OUT:$(LIBRUBY) $(OBJS)

install:;       $(INSTALL_PROGRAM) ruby.exe $(bindir)/ruby.exe
		@-strip $(bindir)/ruby
		@test -d $(libdir) || mkdir $(libdir)
		cd ext; ../miniruby ./extmk.rb install
		@for rb in `grep '^lib/' MANIFEST`; do \
		  $(INSTALL_DATA) $$rb $(libdir); \
		done

clean:;         @rm -f $(OBJS) $(LIBRUBY) main.obj dmyext.obj *.pdb *.map *.exp
		@rm -f ext/extinit.c ext/extinit.obj
		cd ext
		..\miniruby .\extmk.rb clean
		cd ..

realclean:      clean
		@rm -f Makefile ext/extmk.rb
		@rm -f config.cache config.h config.log config.status
		@rm -f core ruby miniruby *~

test:;          @-./ruby sample/test.rb > ./ruby_test 2>&1; \
		 if grep '^end of test' ./ruby_test > /dev/null; then \
		   echo "test succeeded"; \
		 else \
		   grep '^sample/test.rb' ./ruby_test; \
		   grep '^not' ./ruby_test; \
		   echo "test failed";\
		 fi;\
		 rm -f ./ruby_test

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

setenv.obj: missing/setenv.c
	$(CC) -I. $(CFLAGS) $(CPPFLAGS) -c missing/setenv.c

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

vsnprintf.obj: missing/vsnprintf.c
	$(CC) $(CFLAGS) $(CPPFLAGS) -c missing/vsnprintf.c

# when I use -I., there is confliction at "OpenFile" 
# so, set . into environment varible "include"
nt.obj: missing/nt.c
	@set include=$(INCLUDE);.
	$(CC) $(CFLAGS) $(CPPFLAGS) -c missing/nt.c

parse.c: parse.y
	$(YACC) $(YFLAGS) parse.y
	sed -e "s!^extern char \*getenv();!/* & */!" y.tab.c > parse.c
	@rm y.tab.c

win32\sdbm.lib : win32\sdbm.c win32\sdbm.h
	cd win32
	$(CC) $(CFLAGS) $(CPPFLAGS) -DMSDOS -c sdbm.c
	lib /OUT:sdbm.lib sdbm.obj
	copy sdbm.h ndbm.h
	cd ..

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
fnmatch.obj: fnmatch.c config.h fnmatch.h
gc.obj: gc.c ruby.h config.h defines.h env.h rubysig.h st.h node.h re.h regex.h
glob.obj: glob.c config.h fnmatch.h
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
