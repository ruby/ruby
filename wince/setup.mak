# -*- makefile -*-

!if "$(srcdir)" != ""
WIN32DIR = $(srcdir)/win32
!elseif "$(WIN32DIR)" == "win32"
srcdir = .
!elseif "$(WIN32DIR)" == "$(WIN32DIR:/win32=)/win32"
srcdir = $(WIN32DIR:/win32=)
!else
srcdir = $(WIN32DIR)/..
!endif
OS = mswin32
RT = msvcrt
INCLUDE = !include
APPEND = echo>>$(MAKEFILE)
!ifdef MAKEFILE
MAKE = $(MAKE) -f $(MAKEFILE)
!else
MAKEFILE = Makefile
!endif
ARCH = PROCESSOR_ARCHITECTURE
CPU = PROCESSOR_LEVEL
CPP = cl -nologo -EP

all: -prologue- -generic- -epilogue-
i386-$(OS): -prologue- -i386- -epilogue-
i486-$(OS): -prologue- -i486- -epilogue-
i586-$(OS): -prologue- -i586- -epilogue-
i686-$(OS): -prologue- -i686- -epilogue-
alpha-$(OS): -prologue- -alpha- -epilogue-

# CE
mips-hpc2k-wince: -prologue- -mips- -hpc2k- -epilogue-
mips-ppc-wince: -prologue- -mips- -ppc- -epilogue-
mips-hpcpro-wince: -prologue- -mips- -hpcpro- -epilogue-
arm-hpc2k-wince: -prologue- -arm- -hpc2k- -epilogue-
arm-ppc-wince: -prologue- -arm- -ppc- -epilogue-
arm-hpcpro-wince: -prologue- -arm- -hpcpro- -epilogue-
sh3-ppc-wince: -prologue- -sh3- -ppc- -epilogue-
sh3-hpcpro-wince: -prologue- -sh3- -hpcpro2- -epilogue-
sh4-hpcpro-wince: -prologue- -sh4- -hpcpro2- -epilogue-

-prologue-: nul
	@type << > $(MAKEFILE)
### Makefile for ruby $(OS) ###
srcdir = $(srcdir:\=/)
<<
	@$(CPP) -I$(srcdir) <<"Creating $(MAKEFILE)" >> $(MAKEFILE)
#include "version.h"
MAJOR = RUBY_VERSION_MAJOR
MINOR = RUBY_VERSION_MINOR
TEENY = RUBY_VERSION_TEENY
<<

-generic-: nul
!if defined($(ARCH)) || defined($(CPU))
	@type << >>$(MAKEFILE)
!if defined($(ARCH))
$(ARCH) = $(PROCESSOR_ARCHITECTURE)
!endif
!if defined($(CPU))
$(CPU) = $(PROCESSOR_LEVEL)
!endif

<<
!endif

-alpha-: nul
	@$(APPEND) $(ARCH) = alpha
-ix86-: nul
	@$(APPEND) $(ARCH) = x86

-i386-: -ix86-
	@$(APPEND) $(CPU) = 3
-i486-: -ix86-
	@$(APPEND) $(CPU) = 4
-i586-: -ix86-
	@$(APPEND) $(CPU) = 5
-i686-: -ix86-
	@$(APPEND) $(CPU) = 6

# CE
-mips- -arm- -sh3- -sh4-::
	@$(APPEND) $(ARCH) = $(@:-=)
-mips- -arm-::
	@$(APPEND) CC = cl$(@:-=)
-sh3- -sh4-::
	@$(APPEND) CC = shcl

-arm-::
	@$(APPEND) CECPUDEF = -DARM -D_ARM_
-mips-::
	@$(APPEND) CECPUDEF = -DMIPS -D_MIPS_
-sh3-::
	@$(APPEND) CECPUDEF = -DSHx -DSH3 -D_SH3_
-sh4-::
	@$(APPEND) CECPUDEF = -DSHx -DSH4 -D_SH4_

-hpc2k-: -hpc2000-
-ppc-: "-MS Pocket PC-"
-hpcpro2-: "-MS HPC Pro-"
-hpcpro-: "-MS HPC Pro--"

-mswin32-:
	@type << >>$(MAKEFILE)
OS = mswin32
RT = msvcrt
<<

-mswince-:
	@type << >>$(MAKEFILE)
!ifdef CE_TOOLS_DIR
CE_TOOLS_DIR = $(CE_TOOLS_DIR)
!endif
!ifdef EMBEDDED_TOOLS_DIR
EMBEDDED_TOOLS_DIR = $(EMBEDDED_TOOLS_DIR)
!endif

OS = mswince
RT = $$(OS)
SUBSYSTEM = windowsce
<<

-mswince-3.00 -mswince-2.11: -mswince-
	@type << >>$(MAKEFILE)
SUBSYSVERSION = $(@:-mswince-=)
PATH = $$(EMBEDDED_TOOLS_DIR)/common/evc/bin;$$(EMBEDDED_TOOLS_DIR)/EVC/WCE$$(SUBSYSVERSION:.=)/bin
<<

-hpc2000- "-MS Pocket PC-": -mswince-3.00
"-MS HPC Pro-" "-MS HPC Pro--": -mswince-2.11

#-hpc2000- -"MS Pocket PC"- "-MS HPC Pro-":
#	@type << >>$(MAKEFILE)
#INCLUDE = $$(CE_TOOLS_DIR)/wce$$(SUBSYSVERSION:.=)/$(@:-=)/include
#LIB = $$(CE_TOOLS_DIR)/wce$$(SUBSYSVERSION:.=)/$(@:-=)/lib/$$(PROCESSOR_ARCHITECTURE)
#<<

-hpc2000-:
	@type << >>$(MAKEFILE)
INCLUDE = $$(CE_TOOLS_DIR)/wce$$(SUBSYSVERSION:.=)/$(@:-=)/include
LIB = $$(CE_TOOLS_DIR)/wce$$(SUBSYSVERSION:.=)/$(@:-=)/lib/$$(PROCESSOR_ARCHITECTURE)
<<

"-MS Pocket PC-":
	@type << >>$(MAKEFILE)
INCLUDE = $$(CE_TOOLS_DIR)/wce$$(SUBSYSVERSION:.=)/MS Pocket PC/include
LIB = $$(CE_TOOLS_DIR)/wce$$(SUBSYSVERSION:.=)/MS Pocket PC/lib/$$(PROCESSOR_ARCHITECTURE)
<<


"-MS HPC Pro--":
	@type << >>$(MAKEFILE)
INCLUDE = $$(CE_TOOLS_DIR)/wce$$(SUBSYSVERSION:.=)/$(@:-=)/include
LIB = $$(CE_TOOLS_DIR)/wce$$(SUBSYSVERSION:.=)/$(@:-=)/lib
<<

-epilogue-: nul
	@type << >>$(MAKEFILE)
!ifdef RUBY_INSTALL_NAME
RUBY_INSTALL_NAME = $(RUBY_INSTALL_NAME)
!else ifdef RUBY_SUFFIX
RUBY_INSTALL_NAME = ruby$(RUBY_SUFFIX)
!endif
!ifdef RUBY_SO_NAME
RUBY_SO_NAME = $(RUBY_SO_NAME)
!else
# RUBY_SO_NAME = $$(RT)-$$(RUBY_INSTALL_NAME)$$(MAJOR)$$(MINOR)
!endif
# prefix = /usr
# CFLAGS = -nologo $$(DEBUGFLAGS) $$(OPTFLAGS) $$(PROCESSOR_FLAG)
CPPFLAGS = -I. -I$$(srcdir) -I$$(srcdir)/missing -I$$(srcdir)/wince \
           $$(CECPUDEF) -DUNDER_CE -D_WIN32_WCE=$$(SUBSYSVERSION:.=) \
           -DFILENAME_MAX=MAX_PATH -DTLS_OUT_OF_INDEXES=0xFFFFFFFF \
           -DBUFSIZ=512 -D_UNICODE -DUNICODE -DUNDER_CE
# STACK = 0x10000,0x1000
# LDFLAGS = $$(CFLAGS) -Fm
# XLDFLAGS = 
# RFLAGS = -r
# EXTLIBS =

$(INCLUDE) $$(srcdir)/wince/Makefile.sub
<<
	@echo type `$(MAKE)' to make ruby for $(OS).
