require 'fileutils'
require 'getopts'

module FileUtils
#  @fileutils_label = ''
  @fileutils_output = $stdout
end

def setup(options = "")
  options += "v"
  ARGV.map! do |x|
    case x
    when /^-/
      x.delete "^-#{options}"
    when /[*?\[{]/
      Dir[x]
    else
      x
    end
  end
  ARGV.flatten!
  ARGV.delete_if{|x| x == '-'}
  getopts(options)
  options = {}
  options[:verbose] = true if $OPT["v"]
  options[:force] = true if $OPT["f"]
  options[:preserve] = true if $OPT["p"]
  yield ARGV, options, $OPT
end

def mkdir
  setup("p") do |argv, options, opt|
    cmd = "mkdir"
    cmd += "_p" if options.delete :preserve
    FileUtils.send cmd, argv, options
  end
end

def rmdir
  setup do |argv, options|
    FileUtils.rmdir argv, options
  end
end

def ln
  setup("sf") do |argv, options, opt|
    cmd = "ln"
    cmd += "_s" if opt["s"]
    dest = argv.pop
    argv = argv[0] if argv.size == 1
    FileUtils.send cmd, argv, dest, options
  end
end

def cp
  setup("pr") do |argv, options, opt|
    cmd = "cp"
    cmd += "_r" if opt["r"]
    dest = argv.pop
    argv = argv[0] if argv.size == 1
    FileUtils.send cmd, argv, dest, options
  end
end

def mv
  setup do |argv, options|
    dest = argv.pop
    argv = argv[0] if argv.size == 1
    FileUtils.mv argv, dest, options
  end
end

def rm
  setup("fr") do |argv, options, opt|
    cmd = "rm"
    cmd += "_r" if opt["r"]
    FileUtils.send cmd, argv, options
  end
end

def install
  setup("pm:") do |argv, options, opt|
    options[:mode] = opt["m"] ? opt["m"].oct : 0755
    dest = argv.pop
    argv = argv[0] if argv.size == 1
    FileUtils.install argv, dest, options
  end
end

def chmod
  setup do |argv, options|
    mode = argv.shift.oct
    FileUtils.chmod mode, argv, options
  end
end

def touch
  setup do |argv, options|
    FileUtils.touch argv, options
  end
end
