#!./miniruby

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
  else
    break
  end
  ARGV.shift
end

require 'rbconfig'
config = Config::CONFIG

srcdir ||= File.dirname(__FILE__)
archdir ||= '.'

ruby = File.join(archdir, config["RUBY_INSTALL_NAME"]+config['EXEEXT'])
unless File.exist?(ruby)
  abort "#{ruby} is not found.\nTry `make' first, then `make test', please.\n"
end

abs_archdir = File.expand_path(archdir)
libs = [abs_archdir, File.expand_path("lib", srcdir)]
if extout
  abs_extout = File.expand_path(extout)
  libs << abs_extout << File.expand_path(RUBY_PLATFORM, abs_extout)
end
config["bindir"] = abs_archdir

if e = ENV["RUBYLIB"]
  libs |= e.split(File::PATH_SEPARATOR)
end
ENV["RUBYLIB"] = $:.replace(libs).join(File::PATH_SEPARATOR)

if File.file?(File.join(archdir, config['LIBRUBY_SO'])) and
    e = config['LIBPATHENV'] and !e.empty?
  ENV[e] = [abs_archdir, ENV[e]].compact.join(File::PATH_SEPARATOR)
end

exec ruby, *ARGV
