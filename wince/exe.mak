
!IF "$(CFG)" == ""
CFG=MIPS
!MESSAGE CFG not specified. use MIPS. 
!ENDIF 

!IF "$(CESubsystem)" == ""
#CESubsystem=windowsce,2.0
CESubsystem=windowsce,3.0
#!MESSAGE CESubsystem not specified. use windowsce,2.11.
!MESSAGE CESubsystem not specified. use windowsce,3.0.
!ENDIF 

!IF "$(CEVersion)" == ""
#CEVersion=200
CEVersion=300
#!MESSAGE CEVersion not specified. use 211.
!MESSAGE CEVersion not specified. use 300.
!ENDIF 

!IF $(CEVersion) < 201
CECrt=L
CECrtDebug=Ld
CECrtMT=T
CECrtMTDebug=Td
CENoDefaultLib=corelibc.lib
CEx86Corelibc= 
!ELSE 
CECrt=C
CECrtDebug=C
CECrtMT=C
CECrtMTDebug=C
CENoDefaultLib=libc.lib /nodefaultlib:libcd.lib /nodefaultlib:libcmt.lib /nodefaultlib:libcmtd.lib /nodefaultlib:msvcrt.lib /nodefaultlib:msvcrtd.lib
CEx86Corelibc=corelibc.lib
!ENDIF 

!IF "$(CE_PLATFORM)"==""
CePlatform=WIN32_PLATFORM_UNKNOWN
!ELSE 
CePlatform=$(CE_PLATFORM)
!ENDIF 

!IF "$(OS)" == "Windows_NT"
NULL=
!ELSE 
NULL=nul
!ENDIF 

!IF  "$(CFG)" == "MIPS"

OUTDIR=.\MIPSRel
INTDIR=.\MIPSRel
# Begin Custom Macros
OutDir=.\MIPSRel
# End Custom Macros

ALL : "$(OUTDIR)\ruby.exe"


CLEAN :
	-@erase "$(INTDIR)\main.obj"
	-@erase "$(INTDIR)\wincemain.obj"
	-@erase "$(OUTDIR)\ruby.exe"

"$(OUTDIR)" :
    if not exist "$(OUTDIR)/$(NULL)" mkdir "$(OUTDIR)"

RSC=rc.exe
CPP=clmips.exe
CPP_PROJ=/nologo /W3 /I "." /D _WIN32_WCE=$(CEVersion) /D "$(CePlatform)" /D "MIPS" /D "_MIPS_" /D UNDER_CE=$(CEVersion) /D "UNICODE" /D "_UNICODE" /D "NDEBUG" /Fp"$(INTDIR)\ruby.pch" /YX /Fo"$(INTDIR)\\" /Oxs /M$(CECrtMT) /c 

.c{$(INTDIR)}.obj::
   $(CPP) @<<
   $(CPP_PROJ) $< 
<<

.cpp{$(INTDIR)}.obj::
   $(CPP) @<<
   $(CPP_PROJ) $< 
<<

.cxx{$(INTDIR)}.obj::
   $(CPP) @<<
   $(CPP_PROJ) $< 
<<

.c{$(INTDIR)}.sbr::
   $(CPP) @<<
   $(CPP_PROJ) $< 
<<

.cpp{$(INTDIR)}.sbr::
   $(CPP) @<<
   $(CPP_PROJ) $< 
<<

.cxx{$(INTDIR)}.sbr::
   $(CPP) @<<
   $(CPP_PROJ) $< 
<<

MTL=midl.exe
MTL_PROJ=/nologo /D "NDEBUG" /mktyplib203 /o "NUL" /win32 
BSC32=bscmake.exe
BSC32_FLAGS=/nologo /o"$(OUTDIR)\ruby.bsc" 
BSC32_SBRS= \
	
LINK32=link.exe
LINK32_FLAGS=commctrl.lib coredll.lib mswince_ruby17.lib /nologo /base:"0x00010000" /stack:0x10000,0x1000 /entry:"WinMainCRTStartup" /incremental:no /pdb:"$(OUTDIR)\ruby.pdb" /nodefaultlib:"$(CENoDefaultLib)" /out:"$(OUTDIR)\ruby.exe" /libpath:"$(OUTDIR)" /subsystem:$(CESubsystem) /MACHINE:MIPS 
LINK32_OBJS= \
	"$(INTDIR)\main.obj" \
	"$(INTDIR)\wincemain.obj"

"$(OUTDIR)\ruby.exe" : "$(OUTDIR)" $(DEF_FILE) $(LINK32_OBJS)
    $(LINK32) @<<
  $(LINK32_FLAGS) $(LINK32_OBJS)
<<

!ELSEIF  "$(CFG)" == "SH4"

OUTDIR=.\SH4Rel
INTDIR=.\SH4Rel
# Begin Custom Macros
OutDir=.\SH4Rel
# End Custom Macros

ALL : "$(OUTDIR)\ruby.exe"


CLEAN :
	-@erase "$(INTDIR)\main.obj"
	-@erase "$(INTDIR)\wincemain.obj"
	-@erase "$(OUTDIR)\ruby.exe"

"$(OUTDIR)" :
    if not exist "$(OUTDIR)/$(NULL)" mkdir "$(OUTDIR)"

RSC=rc.exe
CPP=shcl.exe
CPP_PROJ=/nologo /W3 /I "." /D _WIN32_WCE=$(CEVersion) /D "$(CePlatform)" /D "SHx" /D "SH4" /D "_SH4_" /D UNDER_CE=$(CEVersion) /D "UNICODE" /D "_UNICODE" /D "NDEBUG" /Fp"$(INTDIR)\ruby.pch" /YX /Fo"$(INTDIR)\\" /Qsh4 /Oxs /M$(CECrtMT) /c 

.c{$(INTDIR)}.obj::
   $(CPP) @<<
   $(CPP_PROJ) $< 
<<

.cpp{$(INTDIR)}.obj::
   $(CPP) @<<
   $(CPP_PROJ) $< 
<<

.cxx{$(INTDIR)}.obj::
   $(CPP) @<<
   $(CPP_PROJ) $< 
<<

.c{$(INTDIR)}.sbr::
   $(CPP) @<<
   $(CPP_PROJ) $< 
<<

.cpp{$(INTDIR)}.sbr::
   $(CPP) @<<
   $(CPP_PROJ) $< 
<<

.cxx{$(INTDIR)}.sbr::
   $(CPP) @<<
   $(CPP_PROJ) $< 
<<

MTL=midl.exe
MTL_PROJ=/nologo /D "NDEBUG" /mktyplib203 /o "NUL" /win32 
BSC32=bscmake.exe
BSC32_FLAGS=/nologo /o"$(OUTDIR)\ruby.bsc" 
BSC32_SBRS= \
	
LINK32=link.exe
LINK32_FLAGS=commctrl.lib coredll.lib mswince_ruby17.lib /nologo /base:"0x00010000" /stack:0x10000,0x1000 /entry:"WinMainCRTStartup" /incremental:no /pdb:"$(OUTDIR)\ruby.pdb" /nodefaultlib:"$(CENoDefaultLib)" /out:"$(OUTDIR)\ruby.exe"  /libpath:"$(OUTDIR)" /subsystem:$(CESubsystem) /MACHINE:SH4 
LINK32_OBJS= \
	"$(INTDIR)\main.obj" \
	"$(INTDIR)\wincemain.obj"

"$(OUTDIR)\ruby.exe" : "$(OUTDIR)" $(DEF_FILE) $(LINK32_OBJS)
    $(LINK32) @<<
  $(LINK32_FLAGS) $(LINK32_OBJS)
<<

!ELSEIF  "$(CFG)" == "SH3"

OUTDIR=.\SH3Rel
INTDIR=.\SH3Rel
# Begin Custom Macros
OutDir=.\SH3Rel
# End Custom Macros

ALL : "$(OUTDIR)\ruby.exe"


CLEAN :
	-@erase "$(INTDIR)\main.obj"
	-@erase "$(INTDIR)\wincemain.obj"
	-@erase "$(OUTDIR)\ruby.exe"

"$(OUTDIR)" :
    if not exist "$(OUTDIR)/$(NULL)" mkdir "$(OUTDIR)"

RSC=rc.exe
CPP=shcl.exe
CPP_PROJ=/nologo /W3 /I "." /D _WIN32_WCE=$(CEVersion) /D "$(CePlatform)" /D "SHx" /D "SH3" /D "_SH3_" /D UNDER_CE=$(CEVersion) /D "UNICODE" /D "_UNICODE" /D "NDEBUG" /Fp"$(INTDIR)\ruby.pch" /YX /Fo"$(INTDIR)\\" /Oxs /M$(CECrtMT) /c 

.c{$(INTDIR)}.obj::
   $(CPP) @<<
   $(CPP_PROJ) $< 
<<

.cpp{$(INTDIR)}.obj::
   $(CPP) @<<
   $(CPP_PROJ) $< 
<<

.cxx{$(INTDIR)}.obj::
   $(CPP) @<<
   $(CPP_PROJ) $< 
<<

.c{$(INTDIR)}.sbr::
   $(CPP) @<<
   $(CPP_PROJ) $< 
<<

.cpp{$(INTDIR)}.sbr::
   $(CPP) @<<
   $(CPP_PROJ) $< 
<<

.cxx{$(INTDIR)}.sbr::
   $(CPP) @<<
   $(CPP_PROJ) $< 
<<

MTL=midl.exe
MTL_PROJ=/nologo /D "NDEBUG" /mktyplib203 /o "NUL" /win32 
BSC32=bscmake.exe
BSC32_FLAGS=/nologo /o"$(OUTDIR)\ruby.bsc" 
BSC32_SBRS= \
	
LINK32=link.exe
LINK32_FLAGS=commctrl.lib coredll.lib mswince_ruby17.lib /nologo /base:"0x00010000" /stack:0x10000,0x1000 /entry:"WinMainCRTStartup" /incremental:no /pdb:"$(OUTDIR)\ruby.pdb" /nodefaultlib:"$(CENoDefaultLib)" /out:"$(OUTDIR)\ruby.exe" /libpath:"$(OUTDIR)" /subsystem:$(CESubsystem) /MACHINE:SH3 
LINK32_OBJS= \
	"$(INTDIR)\main.obj" \
	"$(INTDIR)\wincemain.obj"

"$(OUTDIR)\ruby.exe" : "$(OUTDIR)" $(DEF_FILE) $(LINK32_OBJS)
    $(LINK32) @<<
  $(LINK32_FLAGS) $(LINK32_OBJS)
<<

!ELSEIF  "$(CFG)" == ARM"

OUTDIR=.\ARMRel
INTDIR=.\ARMRel
# Begin Custom Macros
OutDir=.\ARMRel
# End Custom Macros

ALL : "$(OUTDIR)\ruby.exe"


CLEAN :
	-@erase "$(INTDIR)\main.obj"
	-@erase "$(INTDIR)\wincemain.obj"
	-@erase "$(OUTDIR)\ruby.exe"

"$(OUTDIR)" :
    if not exist "$(OUTDIR)/$(NULL)" mkdir "$(OUTDIR)"

RSC=rc.exe
CPP=clarm.exe
CPP_PROJ=/nologo /W3 /I "C:\_develops\eMVT\ruby17\ruby\wince" /D _WIN32_WCE=$(CEVersion) /D "$(CePlatform)" /D "ARM" /D "_ARM_" /D UNDER_CE=$(CEVersion) /D "UNICODE" /D "_UNICODE" /D "NDEBUG" /Fp"$(INTDIR)\ruby.pch" /YX /Fo"$(INTDIR)\\" /Oxs /M$(CECrtMT) /c 

.c{$(INTDIR)}.obj::
   $(CPP) @<<
   $(CPP_PROJ) $< 
<<

.cpp{$(INTDIR)}.obj::
   $(CPP) @<<
   $(CPP_PROJ) $< 
<<

.cxx{$(INTDIR)}.obj::
   $(CPP) @<<
   $(CPP_PROJ) $< 
<<

.c{$(INTDIR)}.sbr::
   $(CPP) @<<
   $(CPP_PROJ) $< 
<<

.cpp{$(INTDIR)}.sbr::
   $(CPP) @<<
   $(CPP_PROJ) $< 
<<

.cxx{$(INTDIR)}.sbr::
   $(CPP) @<<
   $(CPP_PROJ) $< 
<<

MTL=midl.exe
MTL_PROJ=/nologo /D "NDEBUG" /mktyplib203 /o "NUL" /win32 
BSC32=bscmake.exe
BSC32_FLAGS=/nologo /o"$(OUTDIR)\ruby.bsc" 
BSC32_SBRS= \
	
LINK32=link.exe
LINK32_FLAGS=commctrl.lib coredll.lib mswince_ruby17.lib /nologo /base:"0x00010000" /stack:0x10000,0x1000 /entry:"WinMainCRTStartup" /incremental:no /pdb:"$(OUTDIR)\ruby.pdb" /nodefaultlib:"$(CENoDefaultLib)" /out:"$(OUTDIR)\ruby.exe" /libpath:"$(OUTDIR)" /subsystem:$(CESubsystem) /align:"4096" /MACHINE:ARM 
LINK32_OBJS= \
	"$(INTDIR)\main.obj" \
	"$(INTDIR)\wincemain.obj"

"$(OUTDIR)\ruby.exe" : "$(OUTDIR)" $(DEF_FILE) $(LINK32_OBJS)
    $(LINK32) @<<
  $(LINK32_FLAGS) $(LINK32_OBJS)
<<

!ENDIF


..\main.c : \
	"..\defines.h"\
	"..\intern.h"\
	"..\missing.h"\
	"..\ruby.h"\
	"..\vms\vms.h"\
	"..\win32\win32.h"\

.\wincemain.c : \
	".\wince.h"\


SOURCE=..\main.c

"$(INTDIR)\main.obj" : $(SOURCE) "$(INTDIR)"
	$(CPP) $(CPP_PROJ) $(SOURCE)

SOURCE=.\wincemain.c

"$(INTDIR)\wincemain.obj" : $(SOURCE) "$(INTDIR)"
	$(CPP) $(CPP_PROJ) $(SOURCE)

