
!IF "$(CFG)" == ""
CFG=MIPS
!MESSAGE CFG not specified. Use MIPS.
!ENDIF 

!IF "$(CESubsystem)" == ""
#CESubsystem=windowsce,2.0
CESubsystem=windowsce,3.0
#!MESSAGE CESubsystem not specified. Use windowsce,2.11.
!MESSAGE CESubsystem not specified. Use windowsce,3.0.
!ENDIF 

!IF "$(CEVersion)" == ""
#CEVersion=200
CEVersion=300
#!MESSAGE CEVersion not specified. Use 211.
!MESSAGE CEVersion not specified. Use 300.
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

ALL : "$(OUTDIR)\mswince_ruby17.dll"


CLEAN :
	-@erase "$(INTDIR)\acosh.obj"
	-@erase "$(INTDIR)\array.obj"
	-@erase "$(INTDIR)\bignum.obj"
	-@erase "$(INTDIR)\class.obj"
	-@erase "$(INTDIR)\compar.obj"
	-@erase "$(INTDIR)\crypt.obj"
	-@erase "$(INTDIR)\dir.obj"
	-@erase "$(INTDIR)\dln.obj"
	-@erase "$(INTDIR)\dmyext.obj"
	-@erase "$(INTDIR)\enum.obj"
	-@erase "$(INTDIR)\error.obj"
	-@erase "$(INTDIR)\eval.obj"
	-@erase "$(INTDIR)\file.obj"
	-@erase "$(INTDIR)\gc.obj"
	-@erase "$(INTDIR)\hash.obj"
	-@erase "$(INTDIR)\hypot.obj"
	-@erase "$(INTDIR)\inits.obj"
	-@erase "$(INTDIR)\io.obj"
	-@erase "$(INTDIR)\isinf.obj"
	-@erase "$(INTDIR)\isnan.obj"
	-@erase "$(INTDIR)\marshal.obj"
	-@erase "$(INTDIR)\math.obj"
	-@erase "$(INTDIR)\numeric.obj"
	-@erase "$(INTDIR)\object.obj"
	-@erase "$(INTDIR)\pack.obj"
	-@erase "$(INTDIR)\prec.obj"
	-@erase "$(INTDIR)\process.obj"
	-@erase "$(INTDIR)\random.obj"
	-@erase "$(INTDIR)\range.obj"
	-@erase "$(INTDIR)\re.obj"
	-@erase "$(INTDIR)\regex.obj"
	-@erase "$(INTDIR)\ruby.obj"
	-@erase "$(INTDIR)\signal.obj"
	-@erase "$(INTDIR)\sprintf.obj"
	-@erase "$(INTDIR)\st.obj"
	-@erase "$(INTDIR)\strftime.obj"
	-@erase "$(INTDIR)\string.obj"
	-@erase "$(INTDIR)\struct.obj"
	-@erase "$(INTDIR)\time.obj"
	-@erase "$(INTDIR)\util.obj"
	-@erase "$(INTDIR)\variable.obj"
	-@erase "$(INTDIR)\version.obj"
	-@erase "$(INTDIR)\win32.obj"
	-@erase "$(OUTDIR)\mswince_ruby17.dll"
	-@erase "$(OUTDIR)\mswince_ruby17.exp"
	-@erase "$(OUTDIR)\mswince_ruby17.lib"
	-@erase "$(OUTDIR)\wce\direct.obj"
	-@erase "$(OUTDIR)\wce\errno.obj"
	-@erase "$(OUTDIR)\wce\io.obj"
	-@erase "$(OUTDIR)\wce\parse.obj"
	-@erase "$(OUTDIR)\wce\process.obj"
	-@erase "$(OUTDIR)\wce\signal.obj"
	-@erase "$(OUTDIR)\wce\stat.obj"
	-@erase "$(OUTDIR)\wce\stdio.obj"
	-@erase "$(OUTDIR)\wce\stdlib.obj"
	-@erase "$(OUTDIR)\wce\string.obj"
	-@erase "$(OUTDIR)\wce\time.obj"
	-@erase "$(OUTDIR)\wce\timeb.obj"
	-@erase "$(OUTDIR)\wce\utime.obj"
	-@erase "$(OUTDIR)\wce\wince.obj"
	-@erase "$(OUTDIR)\wce\winsock2.obj"

"$(OUTDIR)" :
    if not exist "$(OUTDIR)/$(NULL)" mkdir "$(OUTDIR)"
    if not exist "$(OUTDIR)/wce"     mkdir "$(OUTDIR)/wce"
	if not exist ".\parse.c" byacc ../parse.y
	if not exist ".\parse.c" sed -e "s!^extern char \*getenv();!/* & */!;s/^\(#.*\)y\.tab/\1parse/" y.tab.c > ".\parse.c"
	if exist "y.tab.c"	     @del y.tab.c 

RSC=rc.exe
CPP=clmips.exe
CPP_PROJ=/nologo /W1 /I ".." /I "..\missing" /I "." /D _WIN32_WCE=$(CEVersion) /D "$(CePlatform)" /D "MIPS" /D "_MIPS_" /D UNDER_CE=$(CEVersion) /D "UNICODE" /D "_UNICODE" /D "NDEBUG" /D "_USRDLL" /D "MSWINCE_RUBY17_EXPORTS" /D BUFSIZ=512 /D FILENAME_MAX=260 /D TLS_OUT_OF_INDEXES=0xFFFFFFFF /Fp"$(INTDIR)\mswince_ruby17.pch" /YX /Fo"$(INTDIR)\\" /Oxs /M$(CECrtMT) /c 

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
BSC32_FLAGS=/nologo /o"$(OUTDIR)\mswince_ruby17.bsc" 
BSC32_SBRS= \
	
LINK32=link.exe
LINK32_FLAGS=commctrl.lib coredll.lib winsock.lib /nologo /base:"0x00100000" /stack:0x10000,0x1000 /entry:"_DllMainCRTStartup" /dll /incremental:no /pdb:"$(OUTDIR)\mswince_ruby17.pdb" /nodefaultlib:"$(CENoDefaultLib)" /def:".\mswince-ruby17.def" /out:"$(OUTDIR)\mswince_ruby17.dll" /implib:"$(OUTDIR)\mswince_ruby17.lib" /subsystem:$(CESubsystem) /MACHINE:MIPS 
DEF_FILE= \
	".\mswince-ruby17.def"
LINK32_OBJS= \
	"$(INTDIR)\array.obj" \
	"$(INTDIR)\bignum.obj" \
	"$(INTDIR)\class.obj" \
	"$(INTDIR)\compar.obj" \
	"$(INTDIR)\dir.obj" \
	"$(INTDIR)\dln.obj" \
	"$(INTDIR)\dmyext.obj" \
	"$(INTDIR)\enum.obj" \
	"$(INTDIR)\error.obj" \
	"$(INTDIR)\eval.obj" \
	"$(INTDIR)\file.obj" \
	"$(INTDIR)\gc.obj" \
	"$(INTDIR)\hash.obj" \
	"$(INTDIR)\inits.obj" \
	"$(INTDIR)\io.obj" \
	"$(INTDIR)\marshal.obj" \
	"$(INTDIR)\math.obj" \
	"$(INTDIR)\numeric.obj" \
	"$(INTDIR)\object.obj" \
	"$(INTDIR)\pack.obj" \
	"$(INTDIR)\prec.obj" \
	"$(INTDIR)\process.obj" \
	"$(INTDIR)\random.obj" \
	"$(INTDIR)\range.obj" \
	"$(INTDIR)\re.obj" \
	"$(INTDIR)\regex.obj" \
	"$(INTDIR)\ruby.obj" \
	"$(INTDIR)\signal.obj" \
	"$(INTDIR)\sprintf.obj" \
	"$(INTDIR)\st.obj" \
	"$(INTDIR)\string.obj" \
	"$(INTDIR)\struct.obj" \
	"$(INTDIR)\time.obj" \
	"$(INTDIR)\util.obj" \
	"$(INTDIR)\variable.obj" \
	"$(INTDIR)\version.obj" \
	"$(INTDIR)\win32.obj" \
	"$(INTDIR)\acosh.obj" \
	"$(INTDIR)\crypt.obj" \
	"$(INTDIR)\hypot.obj" \
	"$(INTDIR)\isinf.obj" \
	"$(INTDIR)\isnan.obj" \
	"$(INTDIR)\strftime.obj" \
	"$(INTDIR)\wce\direct.obj" \
	"$(INTDIR)\wce\errno.obj" \
	"$(INTDIR)\wce\io.obj" \
	"$(INTDIR)\wce\process.obj" \
	"$(INTDIR)\wce\signal.obj" \
	"$(INTDIR)\wce\stat.obj" \
	"$(INTDIR)\wce\stdio.obj" \
	"$(INTDIR)\wce\stdlib.obj" \
	"$(INTDIR)\wce\string.obj" \
	"$(INTDIR)\wce\time.obj" \
	"$(INTDIR)\wce\timeb.obj" \
	"$(INTDIR)\wce\utime.obj" \
	"$(INTDIR)\wce\wince.obj" \
	"$(INTDIR)\wce\winsock2.obj" \
	"$(INTDIR)\wce\parse.obj"

"$(OUTDIR)\mswince_ruby17.dll" : "$(OUTDIR)" $(DEF_FILE) $(LINK32_OBJS)
    $(LINK32) @<<
  $(LINK32_FLAGS) $(LINK32_OBJS)
<<

!ELSEIF  "$(CFG)" == "SH4"

OUTDIR=.\SH4Rel
INTDIR=.\SH4Rel
# Begin Custom Macros
OutDir=.\SH4Rel
# End Custom Macros

ALL : "$(OUTDIR)\mswince_ruby17.dll"


CLEAN :
	-@erase "$(INTDIR)\acosh.obj"
	-@erase "$(INTDIR)\array.obj"
	-@erase "$(INTDIR)\bignum.obj"
	-@erase "$(INTDIR)\class.obj"
	-@erase "$(INTDIR)\compar.obj"
	-@erase "$(INTDIR)\crypt.obj"
	-@erase "$(INTDIR)\dir.obj"
	-@erase "$(INTDIR)\dln.obj"
	-@erase "$(INTDIR)\dmyext.obj"
	-@erase "$(INTDIR)\enum.obj"
	-@erase "$(INTDIR)\error.obj"
	-@erase "$(INTDIR)\eval.obj"
	-@erase "$(INTDIR)\file.obj"
	-@erase "$(INTDIR)\gc.obj"
	-@erase "$(INTDIR)\hash.obj"
	-@erase "$(INTDIR)\hypot.obj"
	-@erase "$(INTDIR)\inits.obj"
	-@erase "$(INTDIR)\io.obj"
	-@erase "$(INTDIR)\isinf.obj"
	-@erase "$(INTDIR)\isnan.obj"
	-@erase "$(INTDIR)\marshal.obj"
	-@erase "$(INTDIR)\math.obj"
	-@erase "$(INTDIR)\numeric.obj"
	-@erase "$(INTDIR)\object.obj"
	-@erase "$(INTDIR)\pack.obj"
	-@erase "$(INTDIR)\prec.obj"
	-@erase "$(INTDIR)\process.obj"
	-@erase "$(INTDIR)\random.obj"
	-@erase "$(INTDIR)\range.obj"
	-@erase "$(INTDIR)\re.obj"
	-@erase "$(INTDIR)\regex.obj"
	-@erase "$(INTDIR)\ruby.obj"
	-@erase "$(INTDIR)\signal.obj"
	-@erase "$(INTDIR)\sprintf.obj"
	-@erase "$(INTDIR)\st.obj"
	-@erase "$(INTDIR)\strftime.obj"
	-@erase "$(INTDIR)\string.obj"
	-@erase "$(INTDIR)\struct.obj"
	-@erase "$(INTDIR)\time.obj"
	-@erase "$(INTDIR)\util.obj"
	-@erase "$(INTDIR)\variable.obj"
	-@erase "$(INTDIR)\version.obj"
	-@erase "$(INTDIR)\win32.obj"
	-@erase "$(OUTDIR)\mswince_ruby17.dll"
	-@erase "$(OUTDIR)\mswince_ruby17.exp"
	-@erase "$(OUTDIR)\mswince_ruby17.lib"
	-@erase "$(INTDIR)\wce\direct.obj"
	-@erase "$(INTDIR)\wce\errno.obj"
	-@erase "$(INTDIR)\wce\io.obj"
	-@erase "$(INTDIR)\wce\parse.obj"
	-@erase "$(INTDIR)\wce\process.obj"
	-@erase "$(INTDIR)\wce\signal.obj"
	-@erase "$(INTDIR)\wce\stat.obj"
	-@erase "$(INTDIR)\wce\stdio.obj"
	-@erase "$(INTDIR)\wce\stdlib.obj"
	-@erase "$(INTDIR)\wce\string.obj"
	-@erase "$(INTDIR)\wce\time.obj"
	-@erase "$(INTDIR)\wce\timeb.obj"
	-@erase "$(INTDIR)\wce\utime.obj"
	-@erase "$(INTDIR)\wce\wince.obj"
	-@erase "$(INTDIR)\wce\winsock2.obj"

"$(OUTDIR)" :
    if not exist "$(OUTDIR)/$(NULL)" mkdir "$(OUTDIR)"
    if not exist "$(OUTDIR)/wce"     mkdir "$(OUTDIR)/wce"
	if not exist ".\parse.c" byacc ../parse.y
	if not exist ".\parse.c" sed -e "s!^extern char \*getenv();!/* & */!;s/^\(#.*\)y\.tab/\1parse/" y.tab.c > ".\parse.c"
	if exist "y.tab.c"	     @del y.tab.c 

RSC=rc.exe
CPP=shcl.exe
CPP_PROJ=/nologo /W1 /I ".." /I "..\missing" /I "." /D _WIN32_WCE=$(CEVersion) /D "$(CePlatform)" /D "SHx" /D "SH4" /D "_SH4_" /D UNDER_CE=$(CEVersion) /D "UNICODE" /D "_UNICODE" /D "NDEBUG" /D "_USRDLL" /D "MSWINCE_RUBY17_EXPORTS" /D BUFSIZ=512 /D FILENAME_MAX=260 /D TLS_OUT_OF_INDEXES=0xFFFFFFFF /Fp"$(INTDIR)\mswince_ruby17.pch" /YX /Fo"$(INTDIR)\\" /Qsh4 /Oxs /M$(CECrtMT) /c 

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
BSC32_FLAGS=/nologo /o"$(OUTDIR)\mswince_ruby17.bsc" 
BSC32_SBRS= \
	
LINK32=link.exe
LINK32_FLAGS=commctrl.lib coredll.lib winsock.lib /nologo /base:"0x00100000" /stack:0x10000,0x1000 /entry:"_DllMainCRTStartup" /dll /incremental:no /pdb:"$(OUTDIR)\mswince_ruby17.pdb" /nodefaultlib:"$(CENoDefaultLib)" /def:".\mswince-ruby17.def" /out:"$(OUTDIR)\mswince_ruby17.dll" /implib:"$(OUTDIR)\mswince_ruby17.lib" /subsystem:$(CESubsystem) /MACHINE:SH4 
DEF_FILE= \
	".\mswince-ruby17.def"
LINK32_OBJS= \
	"$(INTDIR)\array.obj" \
	"$(INTDIR)\bignum.obj" \
	"$(INTDIR)\class.obj" \
	"$(INTDIR)\compar.obj" \
	"$(INTDIR)\dir.obj" \
	"$(INTDIR)\dln.obj" \
	"$(INTDIR)\dmyext.obj" \
	"$(INTDIR)\enum.obj" \
	"$(INTDIR)\error.obj" \
	"$(INTDIR)\eval.obj" \
	"$(INTDIR)\file.obj" \
	"$(INTDIR)\gc.obj" \
	"$(INTDIR)\hash.obj" \
	"$(INTDIR)\inits.obj" \
	"$(INTDIR)\io.obj" \
	"$(INTDIR)\marshal.obj" \
	"$(INTDIR)\math.obj" \
	"$(INTDIR)\numeric.obj" \
	"$(INTDIR)\object.obj" \
	"$(INTDIR)\pack.obj" \
	"$(INTDIR)\prec.obj" \
	"$(INTDIR)\process.obj" \
	"$(INTDIR)\random.obj" \
	"$(INTDIR)\range.obj" \
	"$(INTDIR)\re.obj" \
	"$(INTDIR)\regex.obj" \
	"$(INTDIR)\ruby.obj" \
	"$(INTDIR)\signal.obj" \
	"$(INTDIR)\sprintf.obj" \
	"$(INTDIR)\st.obj" \
	"$(INTDIR)\string.obj" \
	"$(INTDIR)\struct.obj" \
	"$(INTDIR)\time.obj" \
	"$(INTDIR)\util.obj" \
	"$(INTDIR)\variable.obj" \
	"$(INTDIR)\version.obj" \
	"$(INTDIR)\win32.obj" \
	"$(INTDIR)\acosh.obj" \
	"$(INTDIR)\crypt.obj" \
	"$(INTDIR)\hypot.obj" \
	"$(INTDIR)\isinf.obj" \
	"$(INTDIR)\isnan.obj" \
	"$(INTDIR)\strftime.obj" \
	"$(INTDIR)\wce\direct.obj" \
	"$(INTDIR)\wce\errno.obj" \
	"$(INTDIR)\wce\io.obj" \
	"$(INTDIR)\wce\process.obj" \
	"$(INTDIR)\wce\signal.obj" \
	"$(INTDIR)\wce\stat.obj" \
	"$(INTDIR)\wce\stdio.obj" \
	"$(INTDIR)\wce\stdlib.obj" \
	"$(INTDIR)\wce\string.obj" \
	"$(INTDIR)\wce\time.obj" \
	"$(INTDIR)\wce\timeb.obj" \
	"$(INTDIR)\wce\utime.obj" \
	"$(INTDIR)\wce\wince.obj" \
	"$(INTDIR)\wce\winsock2.obj" \
	"$(INTDIR)\wce\parse.obj"

"$(OUTDIR)\mswince_ruby17.dll" : "$(OUTDIR)" $(DEF_FILE) $(LINK32_OBJS)
    $(LINK32) @<<
  $(LINK32_FLAGS) $(LINK32_OBJS)
<<

!ELSEIF  "$(CFG)" == "SH3"

OUTDIR=.\SH3Rel
INTDIR=.\SH3Rel
# Begin Custom Macros
OutDir=.\SH3Rel
# End Custom Macros

ALL : "$(OUTDIR)\mswince_ruby17.dll"


CLEAN :
	-@erase "$(INTDIR)\acosh.obj"
	-@erase "$(INTDIR)\array.obj"
	-@erase "$(INTDIR)\bignum.obj"
	-@erase "$(INTDIR)\class.obj"
	-@erase "$(INTDIR)\compar.obj"
	-@erase "$(INTDIR)\crypt.obj"
	-@erase "$(INTDIR)\dir.obj"
	-@erase "$(INTDIR)\dln.obj"
	-@erase "$(INTDIR)\dmyext.obj"
	-@erase "$(INTDIR)\enum.obj"
	-@erase "$(INTDIR)\error.obj"
	-@erase "$(INTDIR)\eval.obj"
	-@erase "$(INTDIR)\file.obj"
	-@erase "$(INTDIR)\gc.obj"
	-@erase "$(INTDIR)\hash.obj"
	-@erase "$(INTDIR)\hypot.obj"
	-@erase "$(INTDIR)\inits.obj"
	-@erase "$(INTDIR)\io.obj"
	-@erase "$(INTDIR)\isinf.obj"
	-@erase "$(INTDIR)\isnan.obj"
	-@erase "$(INTDIR)\marshal.obj"
	-@erase "$(INTDIR)\math.obj"
	-@erase "$(INTDIR)\numeric.obj"
	-@erase "$(INTDIR)\object.obj"
	-@erase "$(INTDIR)\pack.obj"
	-@erase "$(INTDIR)\prec.obj"
	-@erase "$(INTDIR)\process.obj"
	-@erase "$(INTDIR)\random.obj"
	-@erase "$(INTDIR)\range.obj"
	-@erase "$(INTDIR)\re.obj"
	-@erase "$(INTDIR)\regex.obj"
	-@erase "$(INTDIR)\ruby.obj"
	-@erase "$(INTDIR)\signal.obj"
	-@erase "$(INTDIR)\sprintf.obj"
	-@erase "$(INTDIR)\st.obj"
	-@erase "$(INTDIR)\strftime.obj"
	-@erase "$(INTDIR)\string.obj"
	-@erase "$(INTDIR)\struct.obj"
	-@erase "$(INTDIR)\time.obj"
	-@erase "$(INTDIR)\util.obj"
	-@erase "$(INTDIR)\variable.obj"
	-@erase "$(INTDIR)\version.obj"
	-@erase "$(INTDIR)\win32.obj"
	-@erase "$(OUTDIR)\mswince_ruby17.dll"
	-@erase "$(OUTDIR)\mswince_ruby17.exp"
	-@erase "$(OUTDIR)\mswince_ruby17.lib"
	-@erase "$(INTDIR)\wce\direct.obj"
	-@erase "$(INTDIR)\wce\errno.obj"
	-@erase "$(INTDIR)\wce\io.obj"
	-@erase "$(INTDIR)\wce\parse.obj"
	-@erase "$(INTDIR)\wce\process.obj"
	-@erase "$(INTDIR)\wce\signal.obj"
	-@erase "$(INTDIR)\wce\stat.obj"
	-@erase "$(INTDIR)\wce\stdio.obj"
	-@erase "$(INTDIR)\wce\stdlib.obj"
	-@erase "$(INTDIR)\wce\string.obj"
	-@erase "$(INTDIR)\wce\time.obj"
	-@erase "$(INTDIR)\wce\timeb.obj"
	-@erase "$(INTDIR)\wce\utime.obj"
	-@erase "$(INTDIR)\wce\wince.obj"
	-@erase "$(INTDIR)\wce\winsock2.obj"

"$(OUTDIR)" :
    if not exist "$(OUTDIR)/$(NULL)" mkdir "$(OUTDIR)"
    if not exist "$(OUTDIR)/wce"     mkdir "$(OUTDIR)/wce"
	if not exist ".\parse.c" byacc ../parse.y
	if not exist ".\parse.c" sed -e "s!^extern char \*getenv();!/* & */!;s/^\(#.*\)y\.tab/\1parse/" y.tab.c > ".\parse.c"
	if exist "y.tab.c"	     @del y.tab.c 

RSC=rc.exe
CPP=shcl.exe
CPP_PROJ=/nologo /W1 /I ".." /I "..\missing" /I "." /D _WIN32_WCE=$(CEVersion) /D "$(CePlatform)" /D "SHx" /D "SH3" /D "_SH3_" /D UNDER_CE=$(CEVersion) /D "UNICODE" /D "_UNICODE" /D "NDEBUG" /D "_USRDLL" /D "MSWINCE_RUBY17_EXPORTS" /D BUFSIZ=512 /D FILENAME_MAX=260 /D TLS_OUT_OF_INDEXES=0xFFFFFFFF /Fp"$(INTDIR)\mswince_ruby17.pch" /YX /Fo"$(INTDIR)\\" /Oxs /M$(CECrtMT) /c 

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
BSC32_FLAGS=/nologo /o"$(OUTDIR)\mswince_ruby17.bsc" 
BSC32_SBRS= \
	
LINK32=link.exe
LINK32_FLAGS=commctrl.lib coredll.lib winsock.lib /nologo /base:"0x00100000" /stack:0x10000,0x1000 /entry:"_DllMainCRTStartup" /dll /incremental:no /pdb:"$(OUTDIR)\mswince_ruby17.pdb" /nodefaultlib:"$(CENoDefaultLib)" /def:".\mswince-ruby17.def" /out:"$(OUTDIR)\mswince_ruby17.dll" /implib:"$(OUTDIR)\mswince_ruby17.lib" /subsystem:$(CESubsystem) /MACHINE:SH3 
DEF_FILE= \
	".\mswince-ruby17.def"
LINK32_OBJS= \
	"$(INTDIR)\array.obj" \
	"$(INTDIR)\bignum.obj" \
	"$(INTDIR)\class.obj" \
	"$(INTDIR)\compar.obj" \
	"$(INTDIR)\dir.obj" \
	"$(INTDIR)\dln.obj" \
	"$(INTDIR)\dmyext.obj" \
	"$(INTDIR)\enum.obj" \
	"$(INTDIR)\error.obj" \
	"$(INTDIR)\eval.obj" \
	"$(INTDIR)\file.obj" \
	"$(INTDIR)\gc.obj" \
	"$(INTDIR)\hash.obj" \
	"$(INTDIR)\inits.obj" \
	"$(INTDIR)\io.obj" \
	"$(INTDIR)\marshal.obj" \
	"$(INTDIR)\math.obj" \
	"$(INTDIR)\numeric.obj" \
	"$(INTDIR)\object.obj" \
	"$(INTDIR)\pack.obj" \
	"$(INTDIR)\prec.obj" \
	"$(INTDIR)\process.obj" \
	"$(INTDIR)\random.obj" \
	"$(INTDIR)\range.obj" \
	"$(INTDIR)\re.obj" \
	"$(INTDIR)\regex.obj" \
	"$(INTDIR)\ruby.obj" \
	"$(INTDIR)\signal.obj" \
	"$(INTDIR)\sprintf.obj" \
	"$(INTDIR)\st.obj" \
	"$(INTDIR)\string.obj" \
	"$(INTDIR)\struct.obj" \
	"$(INTDIR)\time.obj" \
	"$(INTDIR)\util.obj" \
	"$(INTDIR)\variable.obj" \
	"$(INTDIR)\version.obj" \
	"$(INTDIR)\win32.obj" \
	"$(INTDIR)\acosh.obj" \
	"$(INTDIR)\crypt.obj" \
	"$(INTDIR)\hypot.obj" \
	"$(INTDIR)\isinf.obj" \
	"$(INTDIR)\isnan.obj" \
	"$(INTDIR)\strftime.obj" \
	"$(INTDIR)\wce\direct.obj" \
	"$(INTDIR)\wce\errno.obj" \
	"$(INTDIR)\wce\io.obj" \
	"$(INTDIR)\wce\process.obj" \
	"$(INTDIR)\wce\signal.obj" \
	"$(INTDIR)\wce\stat.obj" \
	"$(INTDIR)\wce\stdio.obj" \
	"$(INTDIR)\wce\stdlib.obj" \
	"$(INTDIR)\wce\string.obj" \
	"$(INTDIR)\wce\time.obj" \
	"$(INTDIR)\wce\timeb.obj" \
	"$(INTDIR)\wce\utime.obj" \
	"$(INTDIR)\wce\wince.obj" \
	"$(INTDIR)\wce\winsock2.obj" \
	"$(INTDIR)\wce\parse.obj"

"$(OUTDIR)\mswince_ruby17.dll" : "$(OUTDIR)" $(DEF_FILE) $(LINK32_OBJS)
    $(LINK32) @<<
  $(LINK32_FLAGS) $(LINK32_OBJS)
<<

!ELSEIF  "$(CFG)" == "ARM"

OUTDIR=.\ARMRel
INTDIR=.\ARMRel
# Begin Custom Macros
OutDir=.\ARMRel
# End Custom Macros

ALL : "$(OUTDIR)\mswince_ruby17.dll"


CLEAN :
	-@erase "$(INTDIR)\acosh.obj"
	-@erase "$(INTDIR)\array.obj"
	-@erase "$(INTDIR)\bignum.obj"
	-@erase "$(INTDIR)\class.obj"
	-@erase "$(INTDIR)\compar.obj"
	-@erase "$(INTDIR)\crypt.obj"
	-@erase "$(INTDIR)\dir.obj"
	-@erase "$(INTDIR)\dln.obj"
	-@erase "$(INTDIR)\dmyext.obj"
	-@erase "$(INTDIR)\enum.obj"
	-@erase "$(INTDIR)\error.obj"
	-@erase "$(INTDIR)\eval.obj"
	-@erase "$(INTDIR)\file.obj"
	-@erase "$(INTDIR)\gc.obj"
	-@erase "$(INTDIR)\hash.obj"
	-@erase "$(INTDIR)\hypot.obj"
	-@erase "$(INTDIR)\inits.obj"
	-@erase "$(INTDIR)\io.obj"
	-@erase "$(INTDIR)\isinf.obj"
	-@erase "$(INTDIR)\isnan.obj"
	-@erase "$(INTDIR)\marshal.obj"
	-@erase "$(INTDIR)\math.obj"
	-@erase "$(INTDIR)\numeric.obj"
	-@erase "$(INTDIR)\object.obj"
	-@erase "$(INTDIR)\pack.obj"
	-@erase "$(INTDIR)\prec.obj"
	-@erase "$(INTDIR)\process.obj"
	-@erase "$(INTDIR)\random.obj"
	-@erase "$(INTDIR)\range.obj"
	-@erase "$(INTDIR)\re.obj"
	-@erase "$(INTDIR)\regex.obj"
	-@erase "$(INTDIR)\ruby.obj"
	-@erase "$(INTDIR)\signal.obj"
	-@erase "$(INTDIR)\sprintf.obj"
	-@erase "$(INTDIR)\st.obj"
	-@erase "$(INTDIR)\strftime.obj"
	-@erase "$(INTDIR)\string.obj"
	-@erase "$(INTDIR)\struct.obj"
	-@erase "$(INTDIR)\time.obj"
	-@erase "$(INTDIR)\util.obj"
	-@erase "$(INTDIR)\variable.obj"
	-@erase "$(INTDIR)\version.obj"
	-@erase "$(INTDIR)\win32.obj"
	-@erase "$(OUTDIR)\mswince_ruby17.dll"
	-@erase "$(OUTDIR)\mswince_ruby17.exp"
	-@erase "$(OUTDIR)\mswince_ruby17.lib"
	-@erase "$(INTDIR)\wce\direct.obj"
	-@erase "$(INTDIR)\wce\errno.obj"
	-@erase "$(INTDIR)\wce\io.obj"
	-@erase "$(INTDIR)\wce\parse.obj"
	-@erase "$(INTDIR)\wce\process.obj"
	-@erase "$(INTDIR)\wce\signal.obj"
	-@erase "$(INTDIR)\wce\stat.obj"
	-@erase "$(INTDIR)\wce\stdio.obj"
	-@erase "$(INTDIR)\wce\stdlib.obj"
	-@erase "$(INTDIR)\wce\string.obj"
	-@erase "$(INTDIR)\wce\time.obj"
	-@erase "$(INTDIR)\wce\timeb.obj"
	-@erase "$(INTDIR)\wce\utime.obj"
	-@erase "$(INTDIR)\wce\wince.obj"
	-@erase "$(INTDIR)\wce\winsock2.obj"

"$(OUTDIR)" :
    if not exist "$(OUTDIR)/$(NULL)" mkdir "$(OUTDIR)"
    if not exist "$(OUTDIR)/wce"     mkdir "$(OUTDIR)/wce"
	if not exist ".\parse.c" byacc ../parse.y
	if not exist ".\parse.c" sed -e "s!^extern char \*getenv();!/* & */!;s/^\(#.*\)y\.tab/\1parse/" y.tab.c > ".\parse.c"
	if exist "y.tab.c"	     @del y.tab.c 

RSC=rc.exe
CPP=clarm.exe
CPP_PROJ=/nologo /W1 /I ".." /I "..\missing" /I "." /D _WIN32_WCE=$(CEVersion) /D "$(CePlatform)" /D "ARM" /D "_ARM_" /D UNDER_CE=$(CEVersion) /D "UNICODE" /D "_UNICODE" /D "NDEBUG" /D "_USRDLL" /D "MSWINCE_RUBY17_EXPORTS" /D BUFSIZ=512 /D FILENAME_MAX=260 /D TLS_OUT_OF_INDEXES=0xFFFFFFFF /Fp"$(INTDIR)\mswince_ruby17.pch" /YX /Fo"$(INTDIR)\\" /Oxs /M$(CECrtMT) /c 

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
BSC32_FLAGS=/nologo /o"$(OUTDIR)\mswince_ruby17.bsc" 
BSC32_SBRS= \
	
LINK32=link.exe
LINK32_FLAGS=commctrl.lib coredll.lib winsock.lib /nologo /base:"0x00100000" /stack:0x10000,0x1000 /entry:"_DllMainCRTStartup" /dll /incremental:no /pdb:"$(OUTDIR)\mswince_ruby17.pdb" /nodefaultlib:"$(CENoDefaultLib)" /def:".\mswince-ruby17.def" /out:"$(OUTDIR)\mswince_ruby17.dll" /implib:"$(OUTDIR)\mswince_ruby17.lib" /subsystem:$(CESubsystem) /align:"4096" /MACHINE:ARM 
DEF_FILE= \
	".\mswince-ruby17.def"
LINK32_OBJS= \
	"$(INTDIR)\array.obj" \
	"$(INTDIR)\bignum.obj" \
	"$(INTDIR)\class.obj" \
	"$(INTDIR)\compar.obj" \
	"$(INTDIR)\dir.obj" \
	"$(INTDIR)\dln.obj" \
	"$(INTDIR)\dmyext.obj" \
	"$(INTDIR)\enum.obj" \
	"$(INTDIR)\error.obj" \
	"$(INTDIR)\eval.obj" \
	"$(INTDIR)\file.obj" \
	"$(INTDIR)\gc.obj" \
	"$(INTDIR)\hash.obj" \
	"$(INTDIR)\inits.obj" \
	"$(INTDIR)\io.obj" \
	"$(INTDIR)\marshal.obj" \
	"$(INTDIR)\math.obj" \
	"$(INTDIR)\numeric.obj" \
	"$(INTDIR)\object.obj" \
	"$(INTDIR)\pack.obj" \
	"$(INTDIR)\prec.obj" \
	"$(INTDIR)\process.obj" \
	"$(INTDIR)\random.obj" \
	"$(INTDIR)\range.obj" \
	"$(INTDIR)\re.obj" \
	"$(INTDIR)\regex.obj" \
	"$(INTDIR)\ruby.obj" \
	"$(INTDIR)\signal.obj" \
	"$(INTDIR)\sprintf.obj" \
	"$(INTDIR)\st.obj" \
	"$(INTDIR)\string.obj" \
	"$(INTDIR)\struct.obj" \
	"$(INTDIR)\time.obj" \
	"$(INTDIR)\util.obj" \
	"$(INTDIR)\variable.obj" \
	"$(INTDIR)\version.obj" \
	"$(INTDIR)\win32.obj" \
	"$(INTDIR)\acosh.obj" \
	"$(INTDIR)\crypt.obj" \
	"$(INTDIR)\hypot.obj" \
	"$(INTDIR)\isinf.obj" \
	"$(INTDIR)\isnan.obj" \
	"$(INTDIR)\strftime.obj" \
	"$(INTDIR)\wce\direct.obj" \
	"$(INTDIR)\wce\errno.obj" \
	"$(INTDIR)\wce\io.obj" \
	"$(INTDIR)\wce\process.obj" \
	"$(INTDIR)\wce\signal.obj" \
	"$(INTDIR)\wce\stat.obj" \
	"$(INTDIR)\wce\stdio.obj" \
	"$(INTDIR)\wce\stdlib.obj" \
	"$(INTDIR)\wce\string.obj" \
	"$(INTDIR)\wce\time.obj" \
	"$(INTDIR)\wce\timeb.obj" \
	"$(INTDIR)\wce\utime.obj" \
	"$(INTDIR)\wce\wince.obj" \
	"$(INTDIR)\wce\winsock2.obj" \
	"$(INTDIR)\wce\parse.obj"

"$(OUTDIR)\mswince_ruby17.dll" : "$(OUTDIR)" $(DEF_FILE) $(LINK32_OBJS)
    $(LINK32) @<<
  $(LINK32_FLAGS) $(LINK32_OBJS)
<<

!ENDIF 



..\array.c : \
	"..\defines.h"\
	"..\intern.h"\
	"..\missing.h"\
	"..\ruby.h"\
	"..\st.h"\
	"..\vms\vms.h"\
	"..\win32\win32.h"\
	".\config.h"\

..\bignum.c : \
	"..\defines.h"\
	"..\intern.h"\
	"..\missing.h"\
	"..\ruby.h"\
	"..\vms\vms.h"\
	"..\win32\win32.h"\
	".\config.h"\

..\class.c : \
	"..\defines.h"\
	"..\intern.h"\
	"..\missing.h"\
	"..\node.h"\
	"..\ruby.h"\
	"..\rubysig.h"\
	"..\st.h"\
	"..\vms\vms.h"\
	"..\win32\win32.h"\
	".\config.h"\

..\compar.c : \
	"..\defines.h"\
	"..\intern.h"\
	"..\missing.h"\
	"..\ruby.h"\
	"..\vms\vms.h"\
	"..\win32\win32.h"\
	".\config.h"\

..\dir.c : \
	"..\defines.h"\
	"..\intern.h"\
	"..\missing.h"\
	"..\ruby.h"\
	"..\vms\vms.h"\
	"..\win32\dir.h"\
	"..\win32\win32.h"\
	".\config.h"\

..\dln.c : \
	"..\defines.h"\
	"..\dln.h"\
	"..\intern.h"\
	"..\missing.h"\
	"..\missing\file.h"\
	"..\ruby.h"\
	"..\st.h"\
	"..\vms\vms.h"\
	"..\win32\win32.h"\
	".\config.h"\

..\enum.c : \
	"..\defines.h"\
	"..\intern.h"\
	"..\missing.h"\
	"..\node.h"\
	"..\ruby.h"\
	"..\vms\vms.h"\
	"..\win32\win32.h"\
	".\config.h"\

..\error.c : \
	"..\defines.h"\
	"..\env.h"\
	"..\intern.h"\
	"..\missing.h"\
	"..\ruby.h"\
	"..\st.h"\
	"..\vms\vms.h"\
	"..\win32\win32.h"\
	".\config.h"\

..\eval.c : \
	"..\defines.h"\
	"..\dln.h"\
	"..\env.h"\
	"..\intern.h"\
	"..\missing.h"\
	"..\node.h"\
	"..\ruby.h"\
	"..\rubysig.h"\
	"..\st.h"\
	"..\vms\vms.h"\
	"..\win32\win32.h"\
	".\config.h"\

..\file.c : \
	"..\defines.h"\
	"..\dln.h"\
	"..\intern.h"\
	"..\missing.h"\
	"..\missing\file.h"\
	"..\ruby.h"\
	"..\rubyio.h"\
	"..\rubysig.h"\
	"..\vms\vms.h"\
	"..\win32\win32.h"\
	".\config.h"\

..\gc.c : \
	"..\defines.h"\
	"..\env.h"\
	"..\intern.h"\
	"..\missing.h"\
	"..\node.h"\
	"..\re.h"\
	"..\regex.h"\
	"..\ruby.h"\
	"..\rubysig.h"\
	"..\st.h"\
	"..\vms\vms.h"\
	"..\win32\win32.h"\
	".\config.h"\

..\hash.c : \
	"..\defines.h"\
	"..\intern.h"\
	"..\missing.h"\
	"..\ruby.h"\
	"..\rubysig.h"\
	"..\st.h"\
	"..\vms\vms.h"\
	"..\win32\win32.h"\
	".\config.h"\

..\inits.c : \
	"..\defines.h"\
	"..\intern.h"\
	"..\missing.h"\
	"..\ruby.h"\
	"..\vms\vms.h"\
	"..\win32\win32.h"\
	".\config.h"\

..\io.c : \
	"..\defines.h"\
	"..\env.h"\
	"..\intern.h"\
	"..\missing.h"\
	"..\ruby.h"\
	"..\rubyio.h"\
	"..\rubysig.h"\
	"..\vms\vms.h"\
	"..\win32\win32.h"\
	".\config.h"\

..\marshal.c : \
	"..\defines.h"\
	"..\intern.h"\
	"..\missing.h"\
	"..\ruby.h"\
	"..\rubyio.h"\
	"..\st.h"\
	"..\vms\vms.h"\
	"..\win32\win32.h"\
	".\config.h"\

..\math.c : \
	"..\defines.h"\
	"..\intern.h"\
	"..\missing.h"\
	"..\ruby.h"\
	"..\vms\vms.h"\
	"..\win32\win32.h"\
	".\config.h"\

..\numeric.c : \
	"..\defines.h"\
	"..\intern.h"\
	"..\missing.h"\
	"..\ruby.h"\
	"..\vms\vms.h"\
	"..\win32\win32.h"\
	".\config.h"\

..\object.c : \
	"..\defines.h"\
	"..\intern.h"\
	"..\missing.h"\
	"..\ruby.h"\
	"..\st.h"\
	"..\vms\vms.h"\
	"..\win32\win32.h"\
	".\config.h"\

..\pack.c : \
	"..\defines.h"\
	"..\intern.h"\
	"..\missing.h"\
	"..\ruby.h"\
	"..\vms\vms.h"\
	"..\win32\win32.h"\
	".\config.h"\

..\prec.c : \
	"..\defines.h"\
	"..\intern.h"\
	"..\missing.h"\
	"..\ruby.h"\
	"..\vms\vms.h"\
	"..\win32\win32.h"\
	".\config.h"\

..\process.c : \
	"..\defines.h"\
	"..\intern.h"\
	"..\missing.h"\
	"..\ruby.h"\
	"..\rubysig.h"\
	"..\st.h"\
	"..\vms\vms.h"\
	"..\win32\win32.h"\
	".\config.h"\

..\random.c : \
	"..\defines.h"\
	"..\intern.h"\
	"..\missing.h"\
	"..\ruby.h"\
	"..\vms\vms.h"\
	"..\win32\win32.h"\
	".\config.h"\

..\range.c : \
	"..\defines.h"\
	"..\intern.h"\
	"..\missing.h"\
	"..\ruby.h"\
	"..\vms\vms.h"\
	"..\win32\win32.h"\
	".\config.h"\

..\re.c : \
	"..\defines.h"\
	"..\intern.h"\
	"..\missing.h"\
	"..\re.h"\
	"..\regex.h"\
	"..\ruby.h"\
	"..\vms\vms.h"\
	"..\win32\win32.h"\
	".\config.h"\

..\regex.c : \
	"..\defines.h"\
	"..\regex.h"\
	"..\vms\vms.h"\
	"..\win32\win32.h"\
	".\config.h"\

..\ruby.c : \
	"..\defines.h"\
	"..\dln.h"\
	"..\intern.h"\
	"..\missing.h"\
	"..\node.h"\
	"..\ruby.h"\
	"..\vms\vms.h"\
	"..\win32\win32.h"\
	".\config.h"\

..\signal.c : \
	"..\defines.h"\
	"..\intern.h"\
	"..\missing.h"\
	"..\ruby.h"\
	"..\rubysig.h"\
	"..\vms\vms.h"\
	"..\win32\win32.h"\
	".\config.h"\

..\sprintf.c : \
	"..\defines.h"\
	"..\intern.h"\
	"..\missing.h"\
	"..\ruby.h"\
	"..\vms\vms.h"\
	"..\win32\win32.h"\
	".\config.h"\

..\st.c : \
	"..\st.h"\
	".\config.h"\

..\string.c : \
	"..\defines.h"\
	"..\intern.h"\
	"..\missing.h"\
	"..\re.h"\
	"..\regex.h"\
	"..\ruby.h"\
	"..\vms\vms.h"\
	"..\win32\win32.h"\
	".\config.h"\

..\struct.c : \
	"..\defines.h"\
	"..\intern.h"\
	"..\missing.h"\
	"..\ruby.h"\
	"..\vms\vms.h"\
	"..\win32\win32.h"\
	".\config.h"\

..\time.c : \
	"..\defines.h"\
	"..\intern.h"\
	"..\missing.h"\
	"..\ruby.h"\
	"..\vms\vms.h"\
	"..\win32\win32.h"\
	".\config.h"\

..\util.c : \
	"..\defines.h"\
	"..\intern.h"\
	"..\missing.h"\
	"..\missing\file.h"\
	"..\ruby.h"\
	"..\vms\vms.h"\
	"..\win32\win32.h"\
	".\config.h"\

..\variable.c : \
	"..\defines.h"\
	"..\env.h"\
	"..\intern.h"\
	"..\missing.h"\
	"..\node.h"\
	"..\ruby.h"\
	"..\st.h"\
	"..\vms\vms.h"\
	"..\win32\win32.h"\
	".\config.h"\

..\version.c : \
	"..\defines.h"\
	"..\intern.h"\
	"..\missing.h"\
	"..\ruby.h"\
	"..\vms\vms.h"\
	"..\win32\win32.h"\
	".\config.h"\

..\win32\win32.c : \
	"..\defines.h"\
	"..\intern.h"\
	"..\missing.h"\
	"..\ruby.h"\
	"..\rubysig.h"\
	"..\vms\vms.h"\
	"..\win32\dir.h"\
	"..\win32\win32.h"\
	".\config.h"\
	".\wince.h"\

..\missing\isinf.c : \
	".\config.h"\

..\missing\strftime.c : \
	".\config.h"\

.\direct.c : \
	".\wince.h"\

.\io.c : \
	".\wince.h"\

.\sys\stat.c : \
	".\wince.h"\

.\stdio.c : \
	".\wince.h"\

.\sys\utime.c : \
	".\wince.h"\

.\wince.c : \
	".\wince.h"\

.\winsock2.c : \
	".\wince.h"\

..\ruby\wince\parse.c : \
	"..\defines.h"\
	"..\env.h"\
	"..\intern.h"\
	"..\lex.c"\
	"..\missing.h"\
	"..\node.h"\
	"..\regex.h"\
	"..\ruby.h"\
	"..\st.h"\
	"..\vms\vms.h"\
	"..\win32\win32.h"\
	".\config.h"\



SOURCE=..\array.c

"$(INTDIR)\array.obj" : $(SOURCE) "$(INTDIR)"
	$(CPP) $(CPP_PROJ) $(SOURCE)

SOURCE=..\bignum.c

"$(INTDIR)\bignum.obj" : $(SOURCE) "$(INTDIR)"
	$(CPP) $(CPP_PROJ) $(SOURCE)

SOURCE=..\class.c

"$(INTDIR)\class.obj" : $(SOURCE) "$(INTDIR)"
	$(CPP) $(CPP_PROJ) $(SOURCE)

SOURCE=..\compar.c

"$(INTDIR)\compar.obj" : $(SOURCE) "$(INTDIR)"
	$(CPP) $(CPP_PROJ) $(SOURCE)

SOURCE=..\dir.c

"$(INTDIR)\dir.obj" : $(SOURCE) "$(INTDIR)"
	$(CPP) $(CPP_PROJ) $(SOURCE)

SOURCE=..\dln.c

"$(INTDIR)\dln.obj" : $(SOURCE) "$(INTDIR)"
	$(CPP) $(CPP_PROJ) $(SOURCE)

SOURCE=..\dmyext.c

"$(INTDIR)\dmyext.obj" : $(SOURCE) "$(INTDIR)"
	$(CPP) $(CPP_PROJ) $(SOURCE)

SOURCE=..\enum.c

"$(INTDIR)\enum.obj" : $(SOURCE) "$(INTDIR)"
	$(CPP) $(CPP_PROJ) $(SOURCE)

SOURCE=..\error.c

"$(INTDIR)\error.obj" : $(SOURCE) "$(INTDIR)"
	$(CPP) $(CPP_PROJ) $(SOURCE)

SOURCE=..\eval.c

"$(INTDIR)\eval.obj" : $(SOURCE) "$(INTDIR)"
	$(CPP) $(CPP_PROJ) $(SOURCE)

SOURCE=..\file.c

"$(INTDIR)\file.obj" : $(SOURCE) "$(INTDIR)"
	$(CPP) $(CPP_PROJ) $(SOURCE)

SOURCE=..\gc.c

"$(INTDIR)\gc.obj" : $(SOURCE) "$(INTDIR)"
	$(CPP) $(CPP_PROJ) $(SOURCE)

SOURCE=..\hash.c

"$(INTDIR)\hash.obj" : $(SOURCE) "$(INTDIR)"
	$(CPP) $(CPP_PROJ) $(SOURCE)

SOURCE=..\inits.c

"$(INTDIR)\inits.obj" : $(SOURCE) "$(INTDIR)"
	$(CPP) $(CPP_PROJ) $(SOURCE)

SOURCE=..\io.c

"$(INTDIR)\io.obj" : $(SOURCE) "$(INTDIR)"
	$(CPP) $(CPP_PROJ) $(SOURCE)

SOURCE=..\marshal.c

"$(INTDIR)\marshal.obj" : $(SOURCE) "$(INTDIR)"
	$(CPP) $(CPP_PROJ) $(SOURCE) 

SOURCE=..\math.c

"$(INTDIR)\math.obj" : $(SOURCE) "$(INTDIR)"
	$(CPP) $(CPP_PROJ) $(SOURCE)

SOURCE=..\numeric.c

"$(INTDIR)\numeric.obj" : $(SOURCE) "$(INTDIR)"
	$(CPP) $(CPP_PROJ) $(SOURCE)

SOURCE=..\object.c

"$(INTDIR)\object.obj" : $(SOURCE) "$(INTDIR)"
	$(CPP) $(CPP_PROJ) $(SOURCE)

SOURCE=..\pack.c

"$(INTDIR)\pack.obj" : $(SOURCE) "$(INTDIR)"
	$(CPP) $(CPP_PROJ) $(SOURCE)

SOURCE=..\prec.c

"$(INTDIR)\prec.obj" : $(SOURCE) "$(INTDIR)"
	$(CPP) $(CPP_PROJ) $(SOURCE)

SOURCE=..\process.c

"$(INTDIR)\process.obj" : $(SOURCE) "$(INTDIR)"
	$(CPP) $(CPP_PROJ) $(SOURCE)

SOURCE=..\random.c

"$(INTDIR)\random.obj" : $(SOURCE) "$(INTDIR)"
	$(CPP) $(CPP_PROJ) $(SOURCE)

SOURCE=..\range.c

"$(INTDIR)\range.obj" : $(SOURCE) "$(INTDIR)"
	$(CPP) $(CPP_PROJ) $(SOURCE)

SOURCE=..\re.c

"$(INTDIR)\re.obj" : $(SOURCE) "$(INTDIR)"
	$(CPP) $(CPP_PROJ) $(SOURCE)

SOURCE=..\regex.c

"$(INTDIR)\regex.obj" : $(SOURCE) "$(INTDIR)"
	$(CPP) $(CPP_PROJ) $(SOURCE)

SOURCE=..\ruby.c

"$(INTDIR)\ruby.obj" : $(SOURCE) "$(INTDIR)"
	$(CPP) $(CPP_PROJ) $(SOURCE)

SOURCE=..\signal.c

"$(INTDIR)\signal.obj" : $(SOURCE) "$(INTDIR)"
	$(CPP) $(CPP_PROJ) $(SOURCE)

SOURCE=..\sprintf.c

"$(INTDIR)\sprintf.obj" : $(SOURCE) "$(INTDIR)"
	$(CPP) $(CPP_PROJ) $(SOURCE)

SOURCE=..\st.c

"$(INTDIR)\st.obj" : $(SOURCE) "$(INTDIR)"
	$(CPP) $(CPP_PROJ) $(SOURCE)

SOURCE=..\string.c

"$(INTDIR)\string.obj" : $(SOURCE) "$(INTDIR)"
	$(CPP) $(CPP_PROJ) $(SOURCE)

SOURCE=..\struct.c

"$(INTDIR)\struct.obj" : $(SOURCE) "$(INTDIR)"
	$(CPP) $(CPP_PROJ) $(SOURCE)

SOURCE=..\time.c

"$(INTDIR)\time.obj" : $(SOURCE) "$(INTDIR)"
	$(CPP) $(CPP_PROJ) $(SOURCE)

SOURCE=..\util.c

"$(INTDIR)\util.obj" : $(SOURCE) "$(INTDIR)"
	$(CPP) $(CPP_PROJ) $(SOURCE)

SOURCE=..\variable.c

"$(INTDIR)\variable.obj" : $(SOURCE) "$(INTDIR)"
	$(CPP) $(CPP_PROJ) $(SOURCE)

SOURCE=..\version.c

"$(INTDIR)\version.obj" : $(SOURCE) "$(INTDIR)"
	$(CPP) $(CPP_PROJ) $(SOURCE)

SOURCE=..\win32\win32.c

"$(INTDIR)\win32.obj" : $(SOURCE) "$(INTDIR)"
	$(CPP) $(CPP_PROJ) $(SOURCE)

SOURCE=..\missing\acosh.c

"$(INTDIR)\acosh.obj" : $(SOURCE) "$(INTDIR)"
	$(CPP) $(CPP_PROJ) $(SOURCE)

SOURCE=..\missing\crypt.c

"$(INTDIR)\crypt.obj" : $(SOURCE) "$(INTDIR)"
	$(CPP) $(CPP_PROJ) $(SOURCE)

SOURCE=..\missing\hypot.c

"$(INTDIR)\hypot.obj" : $(SOURCE) "$(INTDIR)"
	$(CPP) $(CPP_PROJ) $(SOURCE)

SOURCE=..\missing\isinf.c

"$(INTDIR)\isinf.obj" : $(SOURCE) "$(INTDIR)"
	$(CPP) $(CPP_PROJ) $(SOURCE)

SOURCE=..\missing\isnan.c

"$(INTDIR)\isnan.obj" : $(SOURCE) "$(INTDIR)"
	$(CPP) $(CPP_PROJ) $(SOURCE)

SOURCE=..\missing\strftime.c

"$(INTDIR)\strftime.obj" : $(SOURCE) "$(INTDIR)"
	$(CPP) $(CPP_PROJ) $(SOURCE)


!IF  "$(CFG)" == "MIPS"

CPP_PROJ=/nologo /W1 /I ".." /I "..\missing" /I "." /D _WIN32_WCE=$(CEVersion) /D "$(CePlatform)" /D "MIPS" /D "_MIPS_" /D UNDER_CE=$(CEVersion) /D "UNICODE" /D "_UNICODE" /D "NDEBUG" /D "_USRDLL" /D "MSWINCE_RUBY17_EXPORTS" /D BUFSIZ=512 /D FILENAME_MAX=260 /D TLS_OUT_OF_INDEXES=0xFFFFFFFF /Fp"$(INTDIR)\mswince_ruby17.pch" /YX /Fo"$(INTDIR)\wce\\" /Oxs /M$(CECrtMT) /c 

!ELSEIF  "$(CFG)" == "SH4"

CPP_PROJ=/nologo /W1 /I ".." /I "..\missing" /I "." /D _WIN32_WCE=$(CEVersion) /D "$(CePlatform)" /D "SHx" /D "SH4" /D "_SH4_" /D UNDER_CE=$(CEVersion) /D "UNICODE" /D "_UNICODE" /D "NDEBUG" /D "_USRDLL" /D "MSWINCE_RUBY17_EXPORTS" /D BUFSIZ=512 /D FILENAME_MAX=260 /D TLS_OUT_OF_INDEXES=0xFFFFFFFF /Fp"$(INTDIR)\mswince_ruby17.pch" /YX /Fo"$(INTDIR)\wce\\" /Qsh4 /Oxs /M$(CECrtMT) /c 

!ELSEIF  "$(CFG)" == "SH3"

CPP_PROJ=/nologo /W1 /I ".." /I "..\missing" /I "." /D _WIN32_WCE=$(CEVersion) /D "$(CePlatform)" /D "SHx" /D "SH3" /D "_SH3_" /D UNDER_CE=$(CEVersion) /D "UNICODE" /D "_UNICODE" /D "NDEBUG" /D "_USRDLL" /D "MSWINCE_RUBY17_EXPORTS" /D BUFSIZ=512 /D FILENAME_MAX=260 /D TLS_OUT_OF_INDEXES=0xFFFFFFFF /Fp"$(INTDIR)\mswince_ruby17.pch" /YX /Fo"$(INTDIR)\wce\\" /Oxs /M$(CECrtMT) /c 

!ELSEIF  "$(CFG)" == "ARM"

CPP_PROJ=/nologo /W1 /I ".." /I "..\missing" /I "." /D _WIN32_WCE=$(CEVersion) /D "$(CePlatform)" /D "ARM" /D "_ARM_" /D UNDER_CE=$(CEVersion) /D "UNICODE" /D "_UNICODE" /D "NDEBUG" /D "_USRDLL" /D "MSWINCE_RUBY17_EXPORTS" /D BUFSIZ=512 /D FILENAME_MAX=260 /D TLS_OUT_OF_INDEXES=0xFFFFFFFF /Fp"$(INTDIR)\mswince_ruby17.pch" /YX /Fo"$(INTDIR)\wce\\" /Oxs /M$(CECrtMT) /c 

!ENDIF

SOURCE=.\direct.c

"$(INTDIR)\wce\direct.obj" : $(SOURCE) "$(INTDIR)"
	$(CPP) $(CPP_PROJ) $(SOURCE)

SOURCE=.\errno.c

"$(INTDIR)\wce\errno.obj" : $(SOURCE) "$(INTDIR)"
	$(CPP) $(CPP_PROJ) $(SOURCE)

SOURCE=.\io.c

"$(INTDIR)\wce\io.obj" : $(SOURCE) "$(INTDIR)"
	$(CPP) $(CPP_PROJ) $(SOURCE)

SOURCE=.\process.c

"$(INTDIR)\wce\process.obj" : $(SOURCE) "$(INTDIR)"
	$(CPP) $(CPP_PROJ) $(SOURCE)

SOURCE=.\signal.c

"$(INTDIR)\wce\signal.obj" : $(SOURCE) "$(INTDIR)"
	$(CPP) $(CPP_PROJ) $(SOURCE)

SOURCE=.\sys\stat.c

"$(INTDIR)\wce\stat.obj" : $(SOURCE) "$(INTDIR)"
	$(CPP) $(CPP_PROJ) $(SOURCE)

SOURCE=.\stdio.c

"$(INTDIR)\wce\stdio.obj" : $(SOURCE) "$(INTDIR)"
	$(CPP) $(CPP_PROJ) $(SOURCE)

SOURCE=.\stdlib.c

"$(INTDIR)\wce\stdlib.obj" : $(SOURCE) "$(INTDIR)"
	$(CPP) $(CPP_PROJ) $(SOURCE)

SOURCE=.\string.c

"$(INTDIR)\wce\string.obj" : $(SOURCE) "$(INTDIR)"
	$(CPP) $(CPP_PROJ) $(SOURCE)

SOURCE=.\time.c

"$(INTDIR)\wce\time.obj" : $(SOURCE) "$(INTDIR)"
	$(CPP) $(CPP_PROJ) $(SOURCE)

SOURCE=.\sys\timeb.c

"$(INTDIR)\wce\timeb.obj" : $(SOURCE) "$(INTDIR)"
	$(CPP) $(CPP_PROJ) $(SOURCE)

SOURCE=.\sys\utime.c

"$(INTDIR)\wce\utime.obj" : $(SOURCE) "$(INTDIR)"
	$(CPP) $(CPP_PROJ) $(SOURCE)

SOURCE=.\wince.c

"$(INTDIR)\wce\wince.obj" : $(SOURCE) "$(INTDIR)"
	$(CPP) $(CPP_PROJ) $(SOURCE)

SOURCE=.\winsock2.c

"$(INTDIR)\wce\winsock2.obj" : $(SOURCE) "$(INTDIR)"
	$(CPP) $(CPP_PROJ) $(SOURCE)

SOURCE=.\parse.c

"$(INTDIR)\wce\parse.obj" : $(SOURCE) "$(INTDIR)"
	$(CPP) $(CPP_PROJ) $(SOURCE)
