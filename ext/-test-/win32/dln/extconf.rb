if $mingw or $mswin
  $objs = ["dlntest.o"]
  testdll = "$(topdir)/dlntest.dll"
  $cleanfiles << testdll
  $cleanfiles << "dlntest.#{$LIBEXT}"
  config_string('cleanobjs') {|t| $cleanfiles.concat(t.gsub(/\$\*/, 'dlntest').split)}

  create_makefile("-test-/win32/dln")
  m = File.read("Makefile")
  dlntestlib = "dlntest.#{$LIBEXT}"
  m.sub!(/^OBJS =.*/) {"#{$&} #{dlntestlib}"}
  FileUtils.rm_f(RbConfig.expand(testdll.dup))
  open("Makefile", "wb") do |mf|
    mf.puts m, "\n"
    sodir = $extout ? "$(RUBYARCHDIR)/" : ''
    mf.print "#{sodir}$(DLLIB): #{dlntestlib}"
    mf.puts
    mf.puts "#{dlntestlib}: $(topdir)/dlntest.dll"
    mf.puts
    if $mingw
      mf.puts "$(topdir)/dlntest.dll: DEFFILE := $(srcdir)/libdlntest.def"
      mf.puts "$(topdir)/dlntest.dll: DLDFLAGS += -Wl,--out-implib,#{dlntestlib}"
    end
    mf.puts depend_rules("$(topdir)/dlntest.dll: libdlntest.o libdlntest.def")
    mf.puts "\t$(ECHO) linking shared-object $(@F)\n"
    mf.print "\t-$(Q)$(RM) $@\n"
    mf.print "\t-$(Q)$(MAKEDIRS) $(@D)\n" if $extout
    link_so = LINK_SO.gsub(/^/, "\t$(Q) ")
    link_so.sub!(/\$\(LOCAL_LIBS\)/, '')
    link_so.gsub!(/-\$\(arch\)/, '')
    link_so.gsub!(/:.so=/, ':.dll=')
    link_so.sub!(/\$\(OBJS\)/, "libdlntest.#{$OBJEXT}")
    link_so.sub!(/\$\(DEFFILE\)/, "$(srcdir)/libdlntest.def")
    mf.puts link_so
    mf.puts
  end
end
