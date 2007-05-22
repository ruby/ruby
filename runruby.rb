#!./miniruby

pure = true
while arg = ARGV[0]
  break ARGV.shift if arg == '--'
  /\A--([-\w]+)(?:=(.*))?\z/ =~ arg or break
  arg, value = $1, $2
  re = Regexp.new('\A'+arg.gsub(/\w+\b/, '\&\\w*')+'\z', "i")
  case
  when re =~ "srcdir"
    srcdir = value
  when re =~ "archdir"
    archdir = value
  when re =~ "extout"
    extout = value
  when re =~ "pure"
    pure = (value != "no")
  when re =~ "debugger"
    debugger = value ? (value.split unless value == "no") : %w"gdb --args"
  else
    break
  end
  ARGV.shift
end

srcdir ||= File.dirname(__FILE__)
archdir ||= '.'

abs_archdir = File.expand_path(archdir)
$:.unshift(abs_archdir)

require 'rbconfig'
config = RbConfig::CONFIG

ruby = File.join(archdir, config["RUBY_INSTALL_NAME"]+config['EXEEXT'])
unless File.exist?(ruby)
  abort "#{ruby} is not found.\nTry `make' first, then `make test', please.\n"
end

libs = [abs_archdir]
if extout
  abs_extout = File.expand_path(extout)
  libs << File.expand_path("common", abs_extout) << File.expand_path(RUBY_PLATFORM, abs_extout)
end
libs << File.expand_path("lib", srcdir)
config["bindir"] = abs_archdir
ENV["RUBY"] = File.expand_path(ruby)
ENV["PATH"] = [abs_archdir, ENV["PATH"]].compact.join(File::PATH_SEPARATOR)

if pure
  libs << File.expand_path("ext", srcdir) << "-"
elsif e = ENV["RUBYLIB"]
  libs |= e.split(File::PATH_SEPARATOR)
end
ENV["RUBYLIB"] = $:.replace(libs).join(File::PATH_SEPARATOR)

libruby_so = File.join(abs_archdir, config['LIBRUBY_SO'])
if File.file?(libruby_so)
  if e = config['LIBPATHENV'] and !e.empty?
    ENV[e] = [abs_archdir, ENV[e]].compact.join(File::PATH_SEPARATOR)
  end
  if /linux/ =~ RUBY_PLATFORM
    ENV["LD_PRELOAD"] = [libruby_so, ENV["LD_PRELOAD"]].compact.join(' ')
  end
end

cmd = [ruby]
cmd << "-rpurelib.rb" if pure
cmd.concat(ARGV)
cmd.unshift(*debugger) if debugger
exec(*cmd)
