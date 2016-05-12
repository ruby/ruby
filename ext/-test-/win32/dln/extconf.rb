# frozen_string_literal: false
if $mingw or $mswin
  dlntestlib = "dlntest.#{$LIBEXT}"
  $LOCAL_LIBS << " #{dlntestlib}"
  $srcs = ["dlntest.c"]
  $objs = ["dlntest.o"]
  testdll = "$(topdir)/dlntest.dll"
  $cleanfiles << testdll
  $cleanfiles << "dlntest.#{$LIBEXT}"
  config_string('cleanobjs') {|t| $cleanfiles.concat(t.gsub(/\$\*/, 'dlntest').split)}

  create_makefile("-test-/win32/dln") do |m|
    m << "\n""DLNTESTLIB = #{dlntestlib}\n"
    if $mingw
      m << "\n"
      m << "$(topdir)/dlntest.dll: DEFFILE := $(srcdir)/libdlntest.def\n"
      m << "$(topdir)/dlntest.dll: DLDFLAGS += -Wl,--out-implib,$(DLNTESTLIB)\n"
    end
    m
  end
  m = File.read("Makefile")
  m.sub!(/(.*)\$\(DLNTEST_LDSHARED\)$/) do
    pre = $1
    link_so = LINK_SO.gsub(/^/) {pre}
    link_so.sub!(/\$\(LOCAL_LIBS\)/, '')
    link_so.gsub!(/-\$\(arch\)/, '')
    link_so.gsub!(/:.so=/, ':.dll=')
    link_so.sub!(/\$\(OBJS\)/, "libdlntest.#{$OBJEXT}")
    link_so.sub!(/\$\(DEFFILE\)/, "$(srcdir)/libdlntest.def")
    link_so
  end and File.binwrite("Makefile", m)
  FileUtils.rm_f(RbConfig.expand(testdll.dup))
end
