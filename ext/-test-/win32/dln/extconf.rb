if /mswin|mingw/ =~ RUBY_PLATFORM
  $objs = ["dlntest.o"]

  target_prefix = "-test-/win32/"
  create_makefile(target_prefix+"dln")
  m = File.read("Makefile")
  m.sub!(/^OBJS =.*/) {$&+" dlntest.#{$LIBEXT}"}
  open("Makefile", "wb") do |mf|
    mf.puts m, "\n"
    sodir = $extout ? "$(RUBYARCHDIR)/" : ''
    mf.print "#{sodir}$(DLLIB): dlntest.#{$LIBEXT}"
    mf.puts
    mf.puts "dlntest.#{$LIBEXT}: $(topdir)/dlntest.dll"
    mf.puts
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
