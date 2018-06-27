"exec" "${RUBY-ruby}" "-x" "$0" "$@" || true # -*- mode: ruby; coding: utf-8 -*-
#!./ruby
# $Id$

# NOTE:
# Never use optparse in this file.
# Never use test/unit in this file.
# Never use Ruby extensions in this file.

begin
  require 'fileutils'
  require 'tmpdir'
rescue LoadError
  $:.unshift File.join(File.dirname(__FILE__), '../lib')
  retry
end

if !Dir.respond_to?(:mktmpdir)
  # copied from lib/tmpdir.rb
  def Dir.mktmpdir(prefix_suffix=nil, tmpdir=nil)
    case prefix_suffix
    when nil
      prefix = "d"
      suffix = ""
    when String
      prefix = prefix_suffix
      suffix = ""
    when Array
      prefix = prefix_suffix[0]
      suffix = prefix_suffix[1]
    else
      raise ArgumentError, "unexpected prefix_suffix: #{prefix_suffix.inspect}"
    end
    tmpdir ||= Dir.tmpdir
    t = Time.now.strftime("%Y%m%d")
    n = nil
    begin
      path = "#{tmpdir}/#{prefix}#{t}-#{$$}-#{rand(0x100000000).to_s(36)}"
      path << "-#{n}" if n
      path << suffix
      Dir.mkdir(path, 0700)
    rescue Errno::EEXIST
      n ||= 0
      n += 1
      retry
    end

    if block_given?
      begin
        yield path
      ensure
        FileUtils.remove_entry_secure path
      end
    else
      path
    end
  end
end

def main
  @ruby = File.expand_path('miniruby')
  @verbose = false
  $VERBOSE = false
  $stress = false
  @color = nil
  @tty = nil
  @quiet = false
  dir = nil
  quiet = false
  tests = nil
  ARGV.delete_if {|arg|
    case arg
    when /\A--ruby=(.*)/
      @ruby = $1
      @ruby.gsub!(/^([^ ]*)/){File.expand_path($1)}
      @ruby.gsub!(/(\s+-I\s*)((?!(?:\.\/)*-(?:\s|\z))\S+)/){$1+File.expand_path($2)}
      @ruby.gsub!(/(\s+-r\s*)(\.\.?\/\S+)/){$1+File.expand_path($2)}
      true
    when /\A--sets=(.*)/
      tests = Dir.glob("#{File.dirname($0)}/test_{#{$1}}*.rb").sort
      puts tests.map {|path| File.basename(path) }.inspect
      true
    when /\A--dir=(.*)/
      dir = $1
      true
    when /\A(--stress|-s)/
      $stress = true
    when /\A--color(?:=(?:always|(auto)|(never)|(.*)))?\z/
      warn "unknown --color argument: #$3" if $3
      @color = $1 ? nil : !$2
      true
    when /\A--tty(=(?:yes|(no)|(.*)))?\z/
      warn "unknown --tty argument: #$3" if $3
      @tty = !$1 || !$2
      true
    when /\A(-q|--q(uiet))\z/
      quiet = true
      @quiet = true
      true
    when /\A(-v|--v(erbose))\z/
      @verbose = true
    when /\A(-h|--h(elp)?)\z/
      puts(<<-End)
Usage: #{File.basename($0, '.*')} --ruby=PATH [--sets=NAME,NAME,...]
        --sets=NAME,NAME,...        Name of test sets.
        --dir=DIRECTORY             Working directory.
                                    default: /tmp/bootstraptestXXXXX.tmpwd
        --color[=WHEN]              Colorize the output.  WHEN defaults to 'always'
                                    or can be 'never' or 'auto'.
    -s, --stress                    stress test.
    -v, --verbose                   Output test name before exec.
    -q, --quiet                     Don\'t print header message.
    -h, --help                      Print this message and quit.
End
      exit true
    when /\A-j/
      true
    else
      false
    end
  }
  if tests and not ARGV.empty?
    $stderr.puts "--tests and arguments are exclusive"
    exit false
  end
  tests ||= ARGV
  tests = Dir.glob("#{File.dirname($0)}/test_*.rb").sort if tests.empty?
  pathes = tests.map {|path| File.expand_path(path) }

  @progress = %w[- \\ | /]
  @progress_bs = "\b" * @progress[0].size
  @tty = $stderr.tty? if @tty.nil?
  case @color
  when nil
    @color = @tty && /dumb/ !~ ENV["TERM"]
  end
  @tty &&= !@verbose
  if @color
    # dircolors-like style
    colors = (colors = ENV['TEST_COLORS']) ? Hash[colors.scan(/(\w+)=([^:\n]*)/)] : {}
    begin
      File.read(File.join(__dir__, "../test/colors")).scan(/(\w+)=([^:\n]*)/) do |n, c|
        colors[n] ||= c
      end
    rescue
    end
    @passed = "\e[;#{colors["pass"] || "32"}m"
    @failed = "\e[;#{colors["fail"] || "31"}m"
    @reset = "\e[m"
  else
    @passed = @failed = @reset = ""
  end
  unless quiet
    puts Time.now
    if defined?(RUBY_DESCRIPTION)
      puts "Driver is #{RUBY_DESCRIPTION}"
    elsif defined?(RUBY_PATCHLEVEL)
      puts "Driver is ruby #{RUBY_VERSION} (#{RUBY_RELEASE_DATE}#{RUBY_PLATFORM}) [#{RUBY_PLATFORM}]"
    else
      puts "Driver is ruby #{RUBY_VERSION} (#{RUBY_RELEASE_DATE}) [#{RUBY_PLATFORM}]"
    end
    puts "Target is #{`#{@ruby} -v`.chomp}"
    puts
    $stdout.flush
  end

  in_temporary_working_directory(dir) {
    exec_test pathes
  }
end

def erase(e = true)
  if e and @columns > 0 and !@verbose
    "\r#{" "*@columns}\r"
  else
    ""
  end
end

def exec_test(pathes)
  @count = 0
  @error = 0
  @errbuf = []
  @location = nil
  @columns = 0
  @width = pathes.map {|path| File.basename(path).size}.max + 2
  pathes.each do |path|
    @basename = File.basename(path)
    $stderr.printf("%s%-*s ", erase(@quiet), @width, @basename)
    $stderr.flush
    @columns = @width + 1
    $stderr.puts if @verbose
    count = @count
    error = @error
    load File.expand_path(path)
    if @tty
      if @error == error
        msg = "PASS #{@count-count}"
        @columns += msg.size - 1
        $stderr.print "#{@progress_bs}#{@passed}#{msg}#{@reset}"
      else
        msg = "FAIL #{@error-error}/#{@count-count}"
        $stderr.print "#{@progress_bs}#{@failed}#{msg}#{@reset}"
        @columns = 0
      end
    end
    $stderr.puts unless @quiet and @tty and @error == error
  end
  $stderr.print(erase) if @quiet
  if @error == 0
    if @count == 0
      $stderr.puts "No tests, no problem"
    else
      $stderr.puts "#{@passed}PASS#{@reset} all #{@count} tests"
    end
    exit true
  else
    @errbuf.each do |msg|
      $stderr.puts msg
    end
    $stderr.puts "#{@failed}FAIL#{@reset} #{@error}/#{@count} tests failed"
    exit false
  end
end

def show_progress(message = '')
  if @verbose
    $stderr.print "\##{@count} #{@location} "
  elsif @tty
    $stderr.print "#{@progress_bs}#{@progress[@count % @progress.size]}"
  end
  t = Time.now if @verbose
  faildesc, errout = with_stderr {yield}
  t = Time.now - t if @verbose
  if !faildesc
    if @tty
      $stderr.print "#{@progress_bs}#{@progress[@count % @progress.size]}"
    elsif @verbose
      $stderr.printf(". %.3f\n", t)
    else
      $stderr.print '.'
    end
  else
    $stderr.print "#{@failed}F"
    $stderr.printf(" %.3f", t) if @verbose
    $stderr.print "#{@reset}"
    $stderr.puts if @verbose
    error faildesc, message
    unless errout.empty?
      $stderr.print "#{@failed}stderr output is not empty#{@reset}\n", adjust_indent(errout)
    end
    if @tty and !@verbose
      $stderr.printf("%-*s%s", @width, @basename, @progress[@count % @progress.size])
    end
  end
rescue Interrupt
  $stderr.puts "\##{@count} #{@location}"
  raise Interrupt
rescue Exception => err
  $stderr.print 'E'
  $stderr.puts if @verbose
  error err.message, message
end

def assert_check(testsrc, message = '', opt = '', **argh)
  show_progress(message) {
    result = get_result_string(testsrc, opt, **argh)
    check_coredump
    yield(result)
  }
end

def assert_equal(expected, testsrc, message = '', opt = '', **argh)
  newtest
  assert_check(testsrc, message, opt, **argh) {|result|
    if expected == result
      nil
    else
      desc = "#{result.inspect} (expected #{expected.inspect})"
      pretty(testsrc, desc, result)
    end
  }
end

def assert_match(expected_pattern, testsrc, message = '')
  newtest
  assert_check(testsrc, message) {|result|
    if expected_pattern =~ result
      nil
    else
      desc = "#{expected_pattern.inspect} expected to be =~\n#{result.inspect}"
      pretty(testsrc, desc, result)
    end
  }
end

def assert_not_match(unexpected_pattern, testsrc, message = '')
  newtest
  assert_check(testsrc, message) {|result|
    if unexpected_pattern !~ result
      nil
    else
      desc = "#{unexpected_pattern.inspect} expected to be !~\n#{result.inspect}"
      pretty(testsrc, desc, result)
    end
  }
end

def assert_valid_syntax(testsrc, message = '')
  newtest
  assert_check(testsrc, message, '-c') {|result|
    result if /Syntax OK/ !~ result
  }
end

def assert_normal_exit(testsrc, *rest, timeout: nil, **opt)
  newtest
  message, ignore_signals = rest
  message ||= ''
  show_progress(message) {
    faildesc = nil
    filename = make_srcfile(testsrc)
    old_stderr = $stderr.dup
    timeout_signaled = false
    begin
      $stderr.reopen("assert_normal_exit.log", "w")
      io = IO.popen("#{@ruby} -W0 #{filename}")
      pid = io.pid
      th = Thread.new {
        io.read
        io.close
        $?
      }
      if !th.join(timeout)
        Process.kill :KILL, pid
        timeout_signaled = true
      end
      status = th.value
    ensure
      $stderr.reopen(old_stderr)
      old_stderr.close
    end
    if status && status.signaled?
      signo = status.termsig
      signame = Signal.list.invert[signo]
      unless ignore_signals and ignore_signals.include?(signame)
        sigdesc = "signal #{signo}"
        if signame
          sigdesc = "SIG#{signame} (#{sigdesc})"
        end
        if timeout_signaled
          sigdesc << " (timeout)"
        end
        faildesc = pretty(testsrc, "killed by #{sigdesc}", nil)
        stderr_log = File.read("assert_normal_exit.log")
        if !stderr_log.empty?
          faildesc << "\n" if /\n\z/ !~ faildesc
          stderr_log << "\n" if /\n\z/ !~ stderr_log
          stderr_log.gsub!(/^.*\n/) { '| ' + $& }
          faildesc << stderr_log
        end
      end
    end
    faildesc
  }
end

def assert_finish(timeout_seconds, testsrc, message = '')
  newtest
  show_progress(message) {
    faildesc = nil
    filename = make_srcfile(testsrc)
    io = IO.popen("#{@ruby} -W0 #{filename}")
    pid = io.pid
    waited = false
    tlimit = Time.now + timeout_seconds
    while Time.now < tlimit
      if Process.waitpid pid, Process::WNOHANG
        waited = true
        break
      end
      sleep 0.1
    end
    if !waited
      Process.kill(:KILL, pid)
      Process.waitpid pid
      faildesc = pretty(testsrc, "not finished in #{timeout_seconds} seconds", nil)
    end
    io.close
    faildesc
  }
end

def flunk(message = '')
  newtest
  show_progress('') { message }
end

def pretty(src, desc, result)
  src = src.sub(/\A\s*\n/, '')
  (/\n/ =~ src ? "\n#{adjust_indent(src)}" : src) + "  #=> #{desc}"
end

INDENT = 27

def adjust_indent(src)
  untabify(src).gsub(/^ {#{INDENT}}/o, '').gsub(/^/, '   ').sub(/\s*\z/, "\n")
end

def untabify(str)
  str.gsub(/^\t+/) {' ' * (8 * $&.size) }
end

def make_srcfile(src, frozen_string_literal: nil)
  filename = 'bootstraptest.tmp.rb'
  File.open(filename, 'w') {|f|
    f.puts "#frozen_string_literal:true" if frozen_string_literal
    f.puts "GC.stress = true" if $stress
    f.puts "print(begin; #{src}; end)"
  }
  filename
end

def get_result_string(src, opt = '', **argh)
  if @ruby
    filename = make_srcfile(src, **argh)
    begin
      `#{@ruby} -W0 #{opt} #{filename}`
    ensure
      raise Interrupt if $? and $?.signaled? && $?.termsig == Signal.list["INT"]
      raise CoreDumpError, "core dumped" if $? and $?.coredump?
    end
  else
    eval(src).to_s
  end
end

def with_stderr
  out = err = nil
  begin
    r, w = IO.pipe
    stderr = $stderr.dup
    $stderr.reopen(w)
    w.close
    reader = Thread.start {r.read}
    begin
      out = yield
    ensure
      $stderr.reopen(stderr)
      err = reader.value
    end
  ensure
    w.close rescue nil
    r.close rescue nil
  end
  return out, err
end

def newtest
  @location = File.basename(caller(2).first)
  @count += 1
  cleanup_coredump
end

def error(msg, additional_message)
  msg = "#{@failed}\##{@count} #{@location}#{@reset}: #{msg}  #{additional_message}"
  if @tty
    $stderr.puts "#{erase}#{msg}"
  else
    @errbuf.push msg
  end
  @error += 1
end

def in_temporary_working_directory(dir)
  if dir
    Dir.mkdir dir
    Dir.chdir(dir) {
      yield
    }
  else
    Dir.mktmpdir(["bootstraptest", ".tmpwd"]) {|d|
      Dir.chdir(d) {
        yield
      }
    }
  end
end

def cleanup_coredump
  FileUtils.rm_f 'core'
  FileUtils.rm_f Dir.glob('core.*')
  FileUtils.rm_f @ruby+'.stackdump' if @ruby
end

class CoreDumpError < StandardError; end

def check_coredump
  if File.file?('core') or not Dir.glob('core.*').empty? or
      (@ruby and File.exist?(@ruby+'.stackdump'))
    raise CoreDumpError, "core dumped"
  end
end

main
