class File
  sep = ("\\" if RUBY_PLATFORM =~ /mswin|bccwin|mingw/)
  if sep != ALT_SEPARATOR
    remove_const :ALT_SEPARATOR
    ALT_SEPARATOR = sep
  end
end

$:.unshift(builddir)
posthook = proc do
  mkconfig = RbConfig::MAKEFILE_CONFIG
  extout = File.expand_path(mkconfig["EXTOUT"], builddir)
  $arch_hdrdir = "#{extout}/include/$(arch)"
  $ruby = baseruby
  untrace_var(:$ruby, posthook)
end
prehook = proc do |extmk|
  unless extmk
    config = RbConfig::CONFIG
    mkconfig = RbConfig::MAKEFILE_CONFIG
    mkconfig["top_srcdir"] = $top_srcdir = top_srcdir
    mkconfig["rubyhdrdir"] = "$(top_srcdir)/include"
    mkconfig["rubyarchhdrdir"] = "$(builddir)/$(EXTOUT)/include/$(arch)"
    mkconfig["builddir"] = config["builddir"] = builddir
    config["rubyhdrdir"] = File.join(mkconfig["top_srcdir"], "include")
    config["rubyarchhdrdir"] = File.join(builddir, config["EXTOUT"], "include", config["arch"])
    mkconfig["libdirname"] = "builddir"
    trace_var(:$ruby, posthook)
  end
  untrace_var(:$extmk, prehook)
end
trace_var(:$extmk, prehook)
