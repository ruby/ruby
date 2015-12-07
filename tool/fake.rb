class File
  sep = ("\\" if RUBY_PLATFORM =~ /mswin|bccwin|mingw/)
  if sep != ALT_SEPARATOR
    remove_const :ALT_SEPARATOR
    ALT_SEPARATOR = sep
  end
end

static = !!(defined?($static) && $static)
$:.unshift(builddir)
posthook = proc do
  config = RbConfig::CONFIG
  mkconfig = RbConfig::MAKEFILE_CONFIG
  extout = File.expand_path(mkconfig["EXTOUT"], builddir)
  [
    ["top_srcdir", $top_srcdir],
    ["topdir", $topdir],
  ].each do |var, val|
    next unless val
    mkconfig[var] = config[var] = val
    t = /\A#{Regexp.quote(val)}(?=\/)/
    $hdrdir.sub!(t) {"$(#{var})"}
    mkconfig.keys.grep(/dir\z/) do |k|
      mkconfig[k] = "$(#{var})#$'" if t =~ mkconfig[k]
    end
  end
  if $extmk
    $ruby = "$(topdir)/miniruby -I'$(topdir)' -I'$(top_srcdir)/lib' -I'$(extout)/$(arch)' -I'$(extout)/common'"
  else
    $ruby = baseruby
  end
  $static = static
  untrace_var(:$ruby, posthook)
end
prehook = proc do |extmk|
  pat = %r[(?:\A(?:\w:|//[^/]+)|\G)/[^/]*]
  dir = builddir.scan(pat)
  pwd = Dir.pwd.scan(pat)
  if dir[0] == pwd[0]
    while dir[0] and dir[0] == pwd[0]
      dir.shift
      pwd.shift
    end
    builddir = File.join((pwd.empty? ? ["."] : [".."]*pwd.size) + dir)
    builddir = "." if builddir.empty?
  end
  join = proc {|*args| File.join(*args).sub!(/\A(?:\.\/)*/, '')}
  $topdir ||= builddir
  $top_srcdir ||= (File.identical?(top_srcdir, dir = join[$topdir, srcdir]) ?
                     dir : top_srcdir)
  $extout = '$(topdir)/.ext'
  $extout_prefix = '$(extout)$(target_prefix)/'
  config = RbConfig::CONFIG
  mkconfig = RbConfig::MAKEFILE_CONFIG
  mkconfig["builddir"] = config["builddir"] = builddir
  mkconfig["top_srcdir"] = $top_srcdir if $top_srcdir
  config["top_srcdir"] = File.expand_path($top_srcdir ||= top_srcdir)
  config["rubyhdrdir"] = join[$top_srcdir, "include"]
  config["rubyarchhdrdir"] = join[builddir, config["EXTOUT"], "include", config["arch"]]
  mkconfig["libdirname"] = "builddir"
  trace_var(:$ruby, posthook)
  untrace_var(:$extmk, prehook)
end
trace_var(:$extmk, prehook)
