#!./miniruby -s

# This script, which is run when ruby is built, generates rbconfig.rb by
# parsing information from config.status.  rbconfig.rb contains build
# information for ruby (compiler flags, paths, etc.) and is used e.g. by
# mkmf to build compatible native extensions.

# avoid warnings with -d.
$install_name ||= nil
$so_name ||= nil
$unicode_version ||= nil
arch = $arch or raise "missing -arch"
version = $version or raise "missing -version"

srcdir = File.expand_path('../..', __FILE__)
$:.unshift(".")

require "fileutils"
mkconfig = File.basename($0)

fast = {'prefix'=>true, 'ruby_install_name'=>true, 'INSTALL'=>true, 'EXEEXT'=>true}

win32 = /mswin/ =~ arch
universal = /universal.*darwin/ =~ arch
v_fast = []
v_others = []
vars = {}
continued_name = nil
continued_line = nil
install_name = nil
so_name = nil
File.foreach "config.status" do |line|
  next if /^#/ =~ line
  name = nil
  case line
  when /^s([%,])@(\w+)@\1(?:\|\#_!!_\#\|)?(.*)\1/
    name = $2
    val = $3.gsub(/\\(?=,)/, '')
  when /^S\["(\w+)"\]\s*=\s*"(.*)"\s*(\\)?$/
    name = $1
    val = $2
    if $3
      continued_line = [val]
      continued_name = name
      next
    end
  when /^"(.*)"\s*(\\)?$/
    next if !continued_line
    continued_line << $1
    next if $2
    continued_line.each {|s| s.sub!(/\\n\z/, "\n")}
    val = continued_line.join
    name = continued_name
    continued_line = nil
  when /^(?:ac_given_)?INSTALL=(.*)/
    v_fast << "  CONFIG[\"INSTALL\"] = " + $1 + "\n"
  end

  if name
    case name
    when /^(?:ac_.*|configure_input|(?:top_)?srcdir|\w+OBJS)$/; next
    when /^(?:X|(?:MINI|RUN|(?:HAVE_)?BASE|BOOTSTRAP|BTEST)RUBY(?:_COMMAND)?$)/; next
    when /^INSTALLDOC|TARGET$/; next
    when /^DTRACE/; next
    when /^(?:MAJOR|MINOR|TEENY)$/; vars[name] = val; next
    when /^LIBRUBY_D?LD/; next
    when /^RUBY_INSTALL_NAME$/; next vars[name] = (install_name = val).dup if $install_name
    when /^RUBY_SO_NAME$/; next vars[name] = (so_name = val).dup if $so_name
    when /^arch$/; if val.empty? then val = arch else arch = val end
    when /^sitearch$/; val = '$(arch)' if val.empty?
    when /^DESTDIR$/; next
    end
    case val
    when /^\$\(ac_\w+\)$/; next
    when /^\$\{ac_\w+\}$/; next
    when /^\$ac_\w+$/; next
    end
    if /^program_transform_name$/ =~ name
      val.sub!(/\As(\\?\W)(?:\^|\${1,2})\1\1(;|\z)/, '')
      if val.empty?
        $install_name ||= "ruby"
        next
      end
      unless $install_name
        $install_name = "ruby"
        val.gsub!(/\$\$/, '$')
        val.scan(%r[\G[\s;]*(/(?:\\.|[^/])*/)?([sy])(\\?\W)((?:(?!\3)(?:\\.|.))*)\3((?:(?!\3)(?:\\.|.))*)\3([gi]*)]) do
          |addr, cmd, sep, pat, rep, opt|
          if addr
            Regexp.new(addr[/\A\/(.*)\/\z/, 1]) =~ $install_name or next
          end
          case cmd
          when 's'
            pat = Regexp.new(pat, opt.include?('i'))
            if opt.include?('g')
              $install_name.gsub!(pat, rep)
            else
              $install_name.sub!(pat, rep)
            end
          when 'y'
            $install_name.tr!(Regexp.quote(pat), rep)
          end
        end
      end
    end
    eq = win32 && vars[name] ? '<< "\n"' : '='
    vars[name] = val
    if name == "configure_args"
      val.gsub!(/--with-out-ext/, "--without-ext")
    end
    val = val.gsub(/\$(?:\$|\{?(\w+)\}?)/) {$1 ? "$(#{$1})" : $&}.dump
    case name
    when /^prefix$/
      val = "(TOPDIR || DESTDIR + #{val})"
    when /^ARCH_FLAG$/
      val = "arch_flag || #{val}" if universal
    when /^UNIVERSAL_ARCHNAMES$/
      universal, val = val, 'universal' if universal
    when /^arch$/
      if universal
        val.sub!(/universal/, %q[#{arch && universal[/(?:\A|\s)#{Regexp.quote(arch)}=(\S+)/, 1] || '\&'}])
      end
    when /^oldincludedir$/
      val = '"$(SDKROOT)"'+val if /darwin/ =~ arch
    end
    v = "  CONFIG[\"#{name}\"] #{eq} #{val}\n"
    if fast[name]
      v_fast << v
    else
      v_others << v
    end
    case name
    when "RUBY_PROGRAM_VERSION"
      version = val[/\A"(.*)"\z/, 1]
    end
  end
#  break if /^CEOF/
end

drive = File::PATH_SEPARATOR == ';'

def vars.expand(val, config = self)
  newval = val.gsub(/\$\$|\$\(([^()]+)\)|\$\{([^{}]+)\}/) {
    var = $&
    if !(v = $1 || $2)
      '$'
    elsif key = config[v = v[/\A[^:]+(?=(?::(.*?)=(.*))?\z)/]]
      pat, sub = $1, $2
      config[v] = false
      config[v] = expand(key, config)
      key = key.gsub(/#{Regexp.quote(pat)}(?=\s|\z)/n) {sub} if pat
      key
    else
      var
    end
  }
  val.replace(newval) unless newval == val
  val
end
prefix = vars.expand(vars["prefix"] ||= "")
rubyarchdir = vars.expand(vars["rubyarchdir"] ||= "")
relative_archdir = rubyarchdir.rindex(prefix, 0) ? rubyarchdir[prefix.size..-1] : rubyarchdir
puts %[\
# encoding: ascii-8bit
# frozen-string-literal: false
#
# The module storing Ruby interpreter configurations on building.
#
# This file was created by #{mkconfig} when ruby was built.  It contains
# build information for ruby which is used e.g. by mkmf to build
# compatible native extensions.  Any changes made to this file will be
# lost the next time ruby is built.

module RbConfig
  RUBY_VERSION.start_with?("#{version[/^[0-9]+\.[0-9]+\./] || version}") or
    raise "ruby lib version (#{version}) doesn't match executable version (\#{RUBY_VERSION})"

]
print "  # Ruby installed directory.\n"
print "  TOPDIR = File.dirname(__FILE__).chomp!(#{relative_archdir.dump})\n"
print "  # DESTDIR on make install.\n"
print "  DESTDIR = ", (drive ? "TOPDIR && TOPDIR[/\\A[a-z]:/i] || " : ""), "'' unless defined? DESTDIR\n"
print <<'ARCH' if universal
  arch_flag = ENV['ARCHFLAGS'] || ((e = ENV['RC_ARCHS']) && e.split.uniq.map {|a| "-arch #{a}"}.join(' '))
  arch = arch_flag && arch_flag[/\A\s*-arch\s+(\S+)\s*\z/, 1]
ARCH
print "  universal = #{universal}\n" if universal
print "  # The hash configurations stored.\n"
print "  CONFIG = {}\n"
print "  CONFIG[\"DESTDIR\"] = DESTDIR\n"

versions = {}
IO.foreach(File.join(srcdir, "version.h")) do |l|
  m = /^\s*#\s*define\s+RUBY_(PATCHLEVEL)\s+(-?\d+)/.match(l)
  if m
    versions[m[1]] = m[2]
    break if versions.size == 4
    next
  end
  m = /^\s*#\s*define\s+RUBY_VERSION\s+\W?([.\d]+)/.match(l)
  if m
    versions['MAJOR'], versions['MINOR'], versions['TEENY'] = m[1].split('.')
    break if versions.size == 4
    next
  end
end
%w[MAJOR MINOR TEENY PATCHLEVEL].each do |v|
  print "  CONFIG[#{v.dump}] = #{versions[v].dump}\n"
end

dest = drive ? %r'= "(?!\$[\(\{])(?i:[a-z]:)' : %r'= "(?!\$[\(\{])'
v_disabled = {}
v_others.collect! do |x|
  if /^\s*CONFIG\["((?!abs_|old)[a-z]+(?:_prefix|dir))"\]/ === x
    name = $1
    if /= "no"$/ =~ x
      v_disabled[name] = true
      v_others.delete(name)
      next
    end
    x.sub(dest, '= "$(DESTDIR)')
  else
    x
  end
end
v_others.compact!

if $install_name
  if install_name and vars.expand("$(RUBY_INSTALL_NAME)") == $install_name
    $install_name = install_name
  end
  v_fast << "  CONFIG[\"ruby_install_name\"] = \"" + $install_name + "\"\n"
  v_fast << "  CONFIG[\"RUBY_INSTALL_NAME\"] = \"" + $install_name + "\"\n"
end
if $so_name
  if so_name and vars.expand("$(RUBY_SO_NAME)") == $so_name
    $so_name = so_name
  end
  v_fast << "  CONFIG[\"RUBY_SO_NAME\"] = \"" + $so_name + "\"\n"
end

print(*v_fast)
print(*v_others)
print <<EOS if $unicode_version
  CONFIG["UNICODE_VERSION"] = #{$unicode_version.dump}
EOS
print <<EOS if /darwin/ =~ arch
  CONFIG["SDKROOT"] = "\#{ENV['SDKROOT']}" # don't run xcrun every time, usually useless.
EOS
print <<EOS
  CONFIG["archdir"] = "$(rubyarchdir)"
  CONFIG["topdir"] = File.dirname(__FILE__)
  # Almost same with CONFIG. MAKEFILE_CONFIG has other variable
  # reference like below.
  #
  #   MAKEFILE_CONFIG["bindir"] = "$(exec_prefix)/bin"
  #
  # The values of this constant is used for creating Makefile.
  #
  #   require 'rbconfig'
  #
  #   print <<-END_OF_MAKEFILE
  #   prefix = \#{Config::MAKEFILE_CONFIG['prefix']}
  #   exec_prefix = \#{Config::MAKEFILE_CONFIG['exec_prefix']}
  #   bindir = \#{Config::MAKEFILE_CONFIG['bindir']}
  #   END_OF_MAKEFILE
  #
  #   => prefix = /usr/local
  #      exec_prefix = $(prefix)
  #      bindir = $(exec_prefix)/bin  MAKEFILE_CONFIG = {}
  #
  # RbConfig.expand is used for resolving references like above in rbconfig.
  #
  #   require 'rbconfig'
  #   p Config.expand(Config::MAKEFILE_CONFIG["bindir"])
  #   # => "/usr/local/bin"
  MAKEFILE_CONFIG = {}
  CONFIG.each{|k,v| MAKEFILE_CONFIG[k] = v.dup}

  # call-seq:
  #
  #   RbConfig.expand(val)         -> string
  #   RbConfig.expand(val, config) -> string
  #
  # expands variable with given +val+ value.
  #
  #   RbConfig.expand("$(bindir)") # => /home/foobar/all-ruby/ruby19x/bin
  def RbConfig::expand(val, config = CONFIG)
    newval = val.gsub(/\\$\\$|\\$\\(([^()]+)\\)|\\$\\{([^{}]+)\\}/) {
      var = $&
      if !(v = $1 || $2)
	'$'
      elsif key = config[v = v[/\\A[^:]+(?=(?::(.*?)=(.*))?\\z)/]]
	pat, sub = $1, $2
	config[v] = false
	config[v] = RbConfig::expand(key, config)
	key = key.gsub(/\#{Regexp.quote(pat)}(?=\\s|\\z)/n) {sub} if pat
	key
      else
	var
      end
    }
    val.replace(newval) unless newval == val
    val
  end
  CONFIG.each_value do |val|
    RbConfig::expand(val)
  end

  # call-seq:
  #
  #   RbConfig.ruby -> path
  #
  # returns the absolute pathname of the ruby command.
  def RbConfig.ruby
    File.join(
      RbConfig::CONFIG["bindir"],
      RbConfig::CONFIG["ruby_install_name"] + RbConfig::CONFIG["EXEEXT"]
    )
  end
end
CROSS_COMPILING = nil unless defined? CROSS_COMPILING
EOS

# vi:set sw=2:
