# Generated automatically from Makefile.in by configure.
# Main Makefile for GNU m4.
# Copyright (C) 1992 Free Software Foundation, Inc.

# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2, or (at your option)
# any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

SHELL = /bin/sh

#### Start of system configuration section. ####

srcdir = .
VPATH = .

CC = gcc -traditional
DBM = -fpcc-struct-return
YACC = bison -y
INSTALL = /usr/bin/install -c
INSTALL_PROGRAM = $(INSTALL)
INSTALL_DATA = $(INSTALL) -m 644
MAKEINFO = makeinfo

CFLAGS = -g
LDFLAGS = -static $(CFLAGS)
LIBS =  -lm -ldbm
DEFS =  -DHAVE_UNISTD_H=1 -DHAVE_SYSCALL_H=1 -DHAVE_A_OUT_H=1 -DDIRENT=1 -DGETGROUPS_T=int -DRETSIGTYPE=void -DHAVE_STRTOL=1 -DHAVE_STRDUP=1 -DHAVE_KILLPG=1 -DHAVE_MKDIR=1 -DHAVE_STRFTIME=1 -DHAVE_PUTENV=1 -DHAVE_ALLOCA_H=1 -DPW_AGE=1 -DPW_COMMENT=1

prefix = /usr/local
binprefix = 
exec_prefix = $(prefix)
bindir = $(exec_prefix)/bin
infodir = $(prefix)/info

#### End of system configuration section. ####

.c.o:
	$(CC) -c $(CFLAGS) $(CPPFLAGS) $(DEFS) -I$(srcdir) -I$(srcdir)/lib $<

HDRS          = defines.h \
		dln.h \
		ident.h \
		io.h \
		node.h \
		re.h \
		regex.h \
		ruby.h \
		st.h \
		version.h

SRCS          = array.c \
		autoexec.c \
		class.c \
		compar.c \
		dbm.c \
		dict.c \
		dir.c \
		dln.c \
		enum.c \
		error.c \
		etc.c \
		eval.c \
		file.c \
		gc.c \
		inits.c \
		io.c \
		math.c \
		methods.c \
		missing.c \
		numeric.c \
		object.c \
		pack.c \
		parse.y \
		process.c \
		random.c \
		range.c \
		re.c \
		regex.c \
		ruby.c \
		socket.c \
		sprintf.c \
		st.c \
		string.c \
		struct.c \
		time.c \
		variable.c \
		version.c

OBJS	      = array.o \
		autoexec.o \
		class.o \
		compar.o \
		dbm.o \
		dict.o \
		dir.o \
		dln.o \
		enum.o \
		error.o \
		etc.o \
		eval.o \
		file.o \
		gc.o \
		inits.o \
		io.o \
		math.o \
		methods.o \
		missing.o \
		numeric.o \
		object.o \
		pack.o \
		parse.o \
		process.o \
		random.o \
		range.o \
		re.o \
		regex.o \
		ruby.o \
		socket.o \
		sprintf.o \
		st.o \
		string.o \
		struct.o \
		time.o \
		variable.o \
		version.o

DISTFILES = README NEWS TODO THANKS COPYING INSTALL \
ChangeLog Makefile.in configure.in \
$(HDRS) $(SRCS) configure

PROGRAM	      = ruby

all:		$(PROGRAM)

$(PROGRAM):     $(OBJS)
		@echo -n "Loading $(PROGRAM) ... "
		@rm -f $(PROGRAM)
		@$(CC) $(LDFLAGS) $(OBJS) $(LIBS) -o $(PROGRAM)
		@echo "done"

install: $(PROGMAM)
	$(INSTALL_PROGRAM) $(PROGRAM) $(bindir)/$(PROGRAM)

clean:;		@rm -f $(OBJS)

realclean:;	@rm -f $(OBJS)
		@rm -f core ruby *~

dbm.o:dbm.c
	$(CC) -c $(DBM) $(CFLAGS) $(CPPFLAGS) $(DEFS) -I$(srcdir) -I$(srcdir)/lib dbm.c

# Prevent GNU make v3 from overflowing arg limit on SysV.
.NOEXPORT:
###
array.o : array.c ruby.h defines.h 
autoexec.o : autoexec.c ruby.h defines.h 
class.o : class.c ruby.h defines.h node.h st.h 
compar.o : compar.c ruby.h defines.h 
dbm.o : dbm.c ruby.h defines.h 
dict.o : dict.c ruby.h defines.h st.h 
dir.o : dir.c ruby.h defines.h 
dln.o : dln.c defines.h dln.h 
enum.o : enum.c ruby.h defines.h 
error.o : error.c ruby.h defines.h 
etc.o : etc.c ruby.h defines.h 
eval.o : eval.c ruby.h defines.h node.h ident.h st.h 
file.o : file.c ruby.h defines.h io.h 
gc.o : gc.c ruby.h defines.h st.h 
inits.o : inits.c 
io.o : io.c ruby.h defines.h io.h 
math.o : math.c ruby.h defines.h 
methods.o : methods.c ruby.h defines.h node.h 
missing.o : missing.c ruby.h defines.h missing/memmove.c missing/strerror.c \
  missing/strtoul.c missing/strftime.c missing/getopt.h missing/getopt.c missing/getopt1.c 
numeric.o : numeric.c ruby.h defines.h 
object.o : object.c ruby.h defines.h 
pack.o : pack.c ruby.h defines.h 
process.o : process.c ruby.h defines.h st.h 
random.o : random.c ruby.h defines.h 
range.o : range.c ruby.h defines.h 
re.o : re.c ruby.h defines.h re.h regex.h 
regex.o : regex.c regex.h 
ruby.o : ruby.c ruby.h defines.h re.h regex.h missing/getopt.h 
socket.o : socket.c ruby.h defines.h io.h 
sprintf.o : sprintf.c ruby.h defines.h 
st.o : st.c st.h 
string.o : string.c ruby.h defines.h re.h regex.h 
struct.o : struct.c ruby.h defines.h 
time.o : time.c ruby.h defines.h 
variable.o : variable.c ruby.h defines.h st.h ident.h 
version.o : version.c ruby.h defines.h \
  version.h
