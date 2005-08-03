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
!ifndef prefix
prefix = /usr
!endif
OS = mswince
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
sh3-hpcpro-wince: -prologue- -sh3- -hpcpro- -epilogue-
sh4-hpcpro-wince: -prologue- -sh4- -hpcpro- -epilogue-
armv4-.net41-wince: -prologue- -armv4- -.net41- -epilogue-
armv4t-.net41-wince: -prologue- -armv4t- -.net41- -epilogue-
armv4i-sig3-wince: -prologue- -armv4i- -sig3- -epilogue-

-prologue-: nul
	@type << > $(MAKEFILE)
### Makefile for ruby $(OS) ###
srcdir = $(srcdir:\=/)
prefix = $(prefix:\=/)
EXTSTATIC = $(EXTSTATIC)
!if defined(RDOCTARGET)
RDOCTARGET = $(RDOCTARGET)
!endif
!if defined(EXTOUT)
EXTOUT = $(EXTOUT)
!endif
<<
	@$(CPP) -I$(srcdir) -DRUBY_EXTERN="//" <<"Creating $(MAKEFILE)" >> $(MAKEFILE)
#include "version.h"
MAJOR = RUBY_VERSION_MAJOR
MINOR = RUBY_VERSION_MINOR
TEENY = RUBY_VERSION_TEENY
MSC_VER = _MSC_VER
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
-armv4- -armv4i-::
	@$(APPEND) CC = clarm
	@$(APPEND) ARCHFOLDER = $(@:-=)
-armv4t-::
	@$(APPEND) CC = clthumb
	@$(APPEND) ARCHFOLDER = $(@:-=)

-arm-::
	@$(APPEND) CECPUDEF = -DARM -D_ARM_
-mips-::
	@$(APPEND) CECPUDEF = -DMIPS -D_MIPS_
-sh3-::
	@$(APPEND) CECPUDEF = -DSHx -DSH3 -D_SH3_
-sh4-::
	@$(APPEND) CECPUDEF = -DSHx -DSH4 -D_SH4_
	@$(APPEND) QSH4  = -Qsh4
-armv4-::
	@$(APPEND) CECPUDEF = -DARM -D_ARM_ -DARMV4
	@$(APPEND) $(ARCH) = ARM
-armv4t- -armv4i-::
	@$(APPEND) CECPUDEF = -DARM -D_ARM_ -DARMV4T -DTHUMB -D_THUMB_
	@$(APPEND) $(ARCH) = THUMB


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
<<

-mswince4-:
	@type << >>$(MAKEFILE)
!ifdef CE_TOOLS4_DIR
CE_TOOLS4_DIR = $(CE_TOOLS4_DIR)
!endif
!ifdef EMBEDDED_TOOLS4_DIR
EMBEDDED_TOOLS4_DIR = $(EMBEDDED_TOOLS4_DIR)
!endif

OS = mswince
RT = $$(OS)
<<


-mswince-3.00 -mswince-2.11: -mswince-
	@type << >>$(MAKEFILE)
SUBSYSVERSION = $(@:-mswince-=)
PATH = $$(EMBEDDED_TOOLS_DIR)/common/evc/bin;$$(EMBEDDED_TOOLS_DIR)/EVC/WCE$$(SUBSYSVERSION:.=)/bin
<<

-mswince-4.10: -mswince4-
	@type << >>$(MAKEFILE)
SUBSYSVERSION = $(@:-mswince-=)
EXTLIBS = ws2.lib
PATH = $$(EMBEDDED_TOOLS4_DIR)/common/evc/bin;$$(EMBEDDED_TOOLS4_DIR)/EVC/WCE$$(SUBSYSVERSION:.=)/bin
<<

-hpc2000- "-MS Pocket PC-": -mswince-3.00
"-MS HPC Pro-" "-MS HPC Pro--": -mswince-2.11
-.net41- -sig3-: -mswince-4.10

-hpc2000-:
	@type << >>$(MAKEFILE)
SUBSYSTEM = windowsce,3.0
INCLUDE = $$(CE_TOOLS_DIR)/wce$$(SUBSYSVERSION:.=)/$(@:-=)/include
LIB = $$(CE_TOOLS_DIR)/wce$$(SUBSYSVERSION:.=)/$(@:-=)/lib/$$(PROCESSOR_ARCHITECTURE)
<<

"-MS Pocket PC-":
	@type << >>$(MAKEFILE)
SUBSYSTEM = windowsce,3.0
INCLUDE = $$(CE_TOOLS_DIR)/wce$$(SUBSYSVERSION:.=)/MS Pocket PC/include
LIB = $$(CE_TOOLS_DIR)/wce$$(SUBSYSVERSION:.=)/MS Pocket PC/lib/$$(PROCESSOR_ARCHITECTURE)
<<


"-MS HPC Pro--":
	@type << >>$(MAKEFILE)
SUBSYSTEM = windowsce,2.11
INCLUDE = $$(CE_TOOLS_DIR)/wce$$(SUBSYSVERSION:.=)/MS HPC Pro/include
LIB = $$(CE_TOOLS_DIR)/wce$$(SUBSYSVERSION:.=)/MS HPC Pro/lib/$$(PROCESSOR_ARCHITECTURE)
<<

-.net41-:
	@type << >>$(MAKEFILE)
SUBSYSTEM = windowsce,4.1
INCLUDE = $$(CE_TOOLS4_DIR)/wce400/STANDARDSDK/include/$$(ARCHFOLDER)
LIB = $$(CE_TOOLS4_DIR)/wce400/STANDARDSDK/lib/$$(ARCHFOLDER)
<<

-sig3-:
	@type << >>$(MAKEFILE)
SUBSYSTEM = windowsce,4.1
INCLUDE = $$(CE_TOOLS4_DIR)/wce410/sigmarionIII SDK/include/$$(ARCHFOLDER)
LIB = $$(CE_TOOLS4_DIR)/wce410/sigmarionIII SDK/lib/$$(ARCHFOLDER)
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
# CFLAGS = -nologo $$(DEBUGFLAGS) $$(OPTFLAGS) $$(PROCESSOR_FLAG)
CPPFLAGS = -I. -I$$(srcdir) -I$$(srcdir)/missing -I$$(srcdir)/wince \
           $$(CECPUDEF) -DUNDER_CE -D_WIN32_WCE=$$(SUBSYSVERSION:.=) \
           -DFILENAME_MAX=MAX_PATH -DTLS_OUT_OF_INDEXES=0xFFFFFFFF \
           -DBUFSIZ=512 -D_UNICODE -DUNICODE $$(QSH4)
# STACK = 0x10000,0x1000
# LDFLAGS = $$(CFLAGS) -Fm
# XLDFLAGS = 
# RFLAGS = -r
# EXTLIBS =

$(INCLUDE) $$(srcdir)/wince/Makefile.sub
<<
	@$(srcdir:/=\)\win32\rm.bat config.h config.status
	@echo type `$(MAKE)' to make ruby for $(OS).
