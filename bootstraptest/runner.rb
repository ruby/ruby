# $Id: $

# NOTE:
# Never use optparse in this file.
# Never use test/unit in this file.
# Never use Ruby extensions in this file.

require 'fileutils'

def main
  @ruby = nil
  dir = 'bootstraptest.tmpwd'
  tests = nil
  ARGV.delete_if {|arg|
    case arg
    when /\A--ruby=(.*)/
      @ruby = File.expand_path($1)
      true
    when /\A--sets=(.*)/
      tests = Dir.glob("#{File.dirname($0)}/test_{#{$1}}*.rb")
      puts tests.map {|path| File.basename(path) }.inspect
      true
    else
      false
    end
  }
  if tests and not ARGV.empty?
    $stderr.puts "--tests and arguments are exclusive"
    exit 1
  end
  tests ||= ARGV
  tests = Dir.glob("#{File.dirname($0)}/test_*.rb") if tests.empty?
  pathes = tests.map {|path| File.expand_path(path) }
  in_temporary_working_directory(dir) {
    exec_test pathes
  }
end

def exec_test(pathes)
  @count = 0
  @error = 0
  @errbuf = []
  @location = nil
  pathes.each do |path|
    load File.expand_path(path)
  end
  $stderr.puts
  if @error == 0
    $stderr.puts "PASS #{@count} tests"
    exit 0
  else
    @errbuf.each do |msg|
      $stderr.puts msg
    end
    $stderr.puts "FAIL #{@error}/#{@count} tests failed"
    exit 1
  end
end

def assert_equal(expected, really)
  newtest
  restr = get_result_string(really)
  check_coredump
  if expected == restr
    $stderr.print '.'
  else
    $stderr.print 'F'
    error "expected #{expected.inspect} but is: #{restr.inspect}"
  end
rescue Exception => err
  $stderr.print 'E'
  error err.message
end

def get_result_string(src)
  if @ruby
    File.open('bootstraptest.tmp.rb', 'w') {|f|
      f.puts "print(begin; #{src}; end)"
    }
    `#{@ruby} bootstraptest.tmp.rb`
  else
    eval(src).to_s
  end
end

def newtest
  @location = File.basename(caller(2).first)
  @count += 1
  cleanup_coredump
end

def error(msg)
  @errbuf.push "\##{@count} #{@location}: #{msg}"
  @error += 1
end

def in_temporary_working_directory(dir)
  FileUtils.rm_rf dir
  Dir.mkdir dir
  Dir.chdir(dir) {
    yield
  }
end

def cleanup_coredump
  FileUtils.rm_f 'core'
  Dir.glob('core.*').each do |ent|
    FileUtils.rm_f ent
  end
end

class CoreDumpError < StandardError; end

def check_coredump
  if File.file?('core') or not Dir.glob('core.*').empty?
    raise CoreDumpError, "core dumped"
  end
end

main
