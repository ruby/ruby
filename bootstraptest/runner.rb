"exec" "${RUBY-ruby}" "-x" "$0" "$@" || true # -*- Ruby -*-
#!./ruby
# $Id$

# NOTE:
# Never use optparse in this file.
# Never use test/unit in this file.
# Never use Ruby extensions in this file.
# Maintain Ruby 1.8 compatibility for now

$start_time = Time.now

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

# Configuration
bt = Struct.new(:ruby,
                :verbose,
                :color,
                :tty,
                :quiet,
                :wn,
                :progress,
                :progress_bs,
                :passed,
                :failed,
                :reset,
                :columns,
                :window_width,
                :width,
                :indent,
                :platform,
                )
BT = Class.new(bt) do
  def indent=(n)
    super
    if (self.columns ||= 0) < n
      $stderr.print(' ' * (n - self.columns))
    end
    self.columns = indent
  end

  def putc(c)
    unless self.quiet
      if self.window_width == nil
        unless w = ENV["COLUMNS"] and (w = w.to_i) > 0
          w = 80
        end
        w -= 1
        self.window_width = w
      end
      if self.window_width and self.columns >= self.window_width
        $stderr.print "\n", " " * (self.indent ||= 0)
        self.columns = indent
      end
      $stderr.print c
      $stderr.flush
      self.columns += 1
    end
  end

  def wn=(wn)
    unless wn == 1
      if /(?:\A|\s)--jobserver-(?:auth|fds)=(?:(\d+),(\d+)|fifo:((?:\\.|\S)+))/ =~ ENV.delete("MAKEFLAGS")
        begin
          if fifo = $3
            fifo.gsub!(/\\(?=.)/, '')
            r = File.open(fifo, IO::RDONLY|IO::NONBLOCK|IO::BINARY)
            w = File.open(fifo, IO::WRONLY|IO::NONBLOCK|IO::BINARY)
          else
            r = IO.for_fd($1.to_i(10), "rb", autoclose: false)
            w = IO.for_fd($2.to_i(10), "wb", autoclose: false)
          end
        rescue
          r.close if r
        else
          r.close_on_exec = true
          w.close_on_exec = true
          tokens = r.read_nonblock(wn > 0 ? wn : 1024, exception: false)
          r.close
          if String === tokens
            tokens.freeze
            auth = w
            w = nil
            at_exit {auth << tokens; auth.close}
            wn = tokens.size + 1
          else
            w.close
            wn = 1
          end
        end
      end
      if wn <= 0
        require 'etc'
        wn = [Etc.nprocessors / 2, 1].max
      end
    end
    super wn
  end
end.new

BT_STATE = Struct.new(:count, :error).new

def main
  BT.ruby = File.expand_path('miniruby')
  BT.verbose = false
  $VERBOSE = false
  $stress = false
  BT.color = nil
  BT.tty = nil
  BT.quiet = false
  # BT.wn = 1
  dir = nil
  quiet = false
  tests = nil
  ARGV.delete_if {|arg|
    case arg
    when /\A--ruby=(.*)/
      ruby = $1
      ruby.gsub!(/^([^ ]*)/){File.expand_path($1)}
      ruby.gsub!(/(\s+-I\s*)((?!(?:\.\/)*-(?:\s|\z))\S+)/){$1+File.expand_path($2)}
      ruby.gsub!(/(\s+-r\s*)(\.\.?\/\S+)/){$1+File.expand_path($2)}
      BT.ruby = ruby
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
      BT.color = color = $1 ? nil : !$2
      true
    when /\A--tty(=(?:yes|(no)|(.*)))?\z/
      warn "unknown --tty argument: #$3" if $3
      BT.tty = !$1 || !$2
      true
    when /\A(-q|--q(uiet))\z/
      quiet = true
      BT.quiet = true
      true
    when /\A-j(\d+)?/
      BT.wn = $1.to_i
      true
    when /\A(-v|--v(erbose))\z/
      BT.verbose = true
      BT.quiet = false
      true
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
    abort "--sets and arguments are exclusive"
  end
  tests ||= ARGV
  tests = Dir.glob("#{File.dirname($0)}/test_*.rb").sort if tests.empty?
  pathes = tests.map {|path| File.expand_path(path) }

  BT.progress = %w[- \\ | /]
  BT.progress_bs = "\b" * BT.progress[0].size
  BT.tty = $stderr.tty? if BT.tty.nil?
  BT.wn ||= /-j(\d+)?/ =~ (ENV["MAKEFLAGS"] || ENV["MFLAGS"]) ? $1.to_i : 1

  case BT.color
  when nil
    BT.color = BT.tty && /dumb/ !~ ENV["TERM"]
  end
  BT.tty &&= !BT.verbose
  if BT.color
    # dircolors-like style
    colors = (colors = ENV['TEST_COLORS']) ? Hash[colors.scan(/(\w+)=([^:\n]*)/)] : {}
    begin
      File.read(File.join(__dir__, "../tool/colors")).scan(/(\w+)=([^:\n]*)/) do |n, c|
        colors[n] ||= c
      end
    rescue
    end
    BT.passed = "\e[;#{colors["pass"] || "32"}m"
    BT.failed = "\e[;#{colors["fail"] || "31"}m"
    BT.reset = "\e[m"
  else
    BT.passed = BT.failed = BT.reset = ""
  end
  target_version = `#{BT.ruby} -v`.chomp
  BT.platform = target_version[/\[(.*)\]\z/, 1]
  unless quiet
    puts $start_time
    if defined?(RUBY_DESCRIPTION)
      puts "Driver is #{RUBY_DESCRIPTION}"
    elsif defined?(RUBY_PATCHLEVEL)
      puts "Driver is ruby #{RUBY_VERSION} (#{RUBY_RELEASE_DATE}#{RUBY_PLATFORM}) [#{RUBY_PLATFORM}]"
    else
      puts "Driver is ruby #{RUBY_VERSION} (#{RUBY_RELEASE_DATE}) [#{RUBY_PLATFORM}]"
    end
    puts "Target is #{target_version}"
    puts
    $stdout.flush
  end

  in_temporary_working_directory(dir) do
    exec_test pathes
  end
end

def erase(e = true)
  if e and BT.columns > 0 and BT.tty and !BT.verbose
    "\e[1K\r"
  else
    ""
  end
end

def load_test pathes
  pathes.each do |path|
    load File.expand_path(path)
  end
end

def concurrent_exec_test
  aq = Queue.new
  rq = Queue.new

  ts = BT.wn.times.map do
    Thread.new do
      while as = aq.pop
        as.call
        rq << as
      end
    ensure
      rq << nil
    end
  end

  Assertion.all.to_a.shuffle.each do |path, assertions|
    assertions.each do |as|
      aq << as
    end
  end

  BT.indent = 1
  aq.close
  i = 1
  term_wn = 0
  begin
    while BT.wn != term_wn
      if r = rq.pop
        case
        when BT.quiet
        when BT.tty
          $stderr.print "#{BT.progress_bs}#{BT.progress[(i+=1) % BT.progress.size]}"
        else
          BT.putc '.'
        end
      else
        term_wn += 1
      end
    end
  ensure
    ts.each(&:kill)
    ts.each(&:join)
  end
end

def exec_test(pathes)
  # setup
  load_test pathes
  BT_STATE.count = 0
  BT_STATE.error = 0
  BT.columns = 0
  BT.width = pathes.map {|path| File.basename(path).size}.max + 2

  # execute tests
  if BT.wn > 1
    concurrent_exec_test
  else
    prev_basename = nil
    Assertion.all.each do |basename, assertions|
      if !BT.quiet && basename != prev_basename
        prev_basename = basename
        $stderr.printf("%s%-*s ", erase(BT.quiet), BT.width, basename)
        $stderr.flush
      end
      BT.columns = BT.width + 1
      $stderr.puts if BT.verbose
      count = BT_STATE.count
      error = BT_STATE.error

      assertions.each do |assertion|
        BT_STATE.count += 1
        assertion.call
      end

      if BT.tty
        if BT_STATE.error == error
          msg = "PASS #{BT_STATE.count-count}"
          BT.columns += msg.size - 1
          $stderr.print "#{BT.progress_bs}#{BT.passed}#{msg}#{BT.reset}" unless BT.quiet
        else
          msg = "FAIL #{BT_STATE.error-error}/#{BT_STATE.count-count}"
          $stderr.print "#{BT.progress_bs}#{BT.failed}#{msg}#{BT.reset}"
          BT.columns = 0
        end
      end
      $stderr.puts if !BT.quiet and (BT.tty or BT_STATE.error == error)
    end
  end

  # show results
  unless BT.quiet
    $stderr.puts(erase)

    sec = Time.now - $start_time
    $stderr.puts "Finished in #{'%.2f' % sec} sec\n\n" if Assertion.count > 0
  end

  Assertion.errbuf.each do |msg|
    $stderr.puts msg
  end

  out = BT.quiet ? $stdout : $stderr

  if BT_STATE.error == 0
    if Assertion.count == 0
      out.puts "No tests, no problem" unless BT.quiet
    else
      out.puts "#{BT.passed}PASS#{BT.reset} all #{Assertion.count} tests"
    end
    true
  else
    $stderr.puts "#{BT.failed}FAIL#{BT.reset} #{BT_STATE.error}/#{BT_STATE.count} tests failed"
    false
  end
end

def target_platform
  BT.platform or RUBY_PLATFORM
end

class Assertion < Struct.new(:src, :path, :lineno, :proc)
  @count = 0
  @all = Hash.new{|h, k| h[k] = []}
  @errbuf = []

  class << self
    attr_reader :count, :errbuf

    def all
      @all
    end

    def add as
      @all[as.path] << as
      as.id = (@count += 1)
    end
  end

  attr_accessor :id
  attr_reader :err, :category

  def initialize(*args)
    super
    self.class.add self
    @category = self.path.match(/test_(.+)\.rb/)[1]
  end

  def call
    self.proc.call self
  end

  def assert_check(message = '', opt = '', **argh)
    show_progress(message) {
      result = get_result_string(opt, **argh)
      yield(result)
    }
  end

  def with_stderr
    out = err = nil
    r, w = IO.pipe
    @err = w
    err_reader = Thread.new{ r.read }

    begin
      out = yield
    ensure
      w.close
      err = err_reader.value
      r.close rescue nil
    end

    return out, err
  end

  def show_error(msg, additional_message)
    msg = "#{BT.failed}\##{self.id} #{self.path}:#{self.lineno}#{BT.reset}: #{msg}  #{additional_message}"
    if BT.tty
      $stderr.puts "#{erase}#{msg}"
    else
      Assertion.errbuf << msg
    end
    BT_STATE.error += 1
  end


  def show_progress(message = '')
    if BT.quiet || BT.wn > 1
      # do nothing
    elsif BT.verbose
      $stderr.print "\##{@id} #{self.path}:#{self.lineno} "
    elsif BT.tty
      $stderr.print "#{BT.progress_bs}#{BT.progress[BT_STATE.count % BT.progress.size]}"
    end

    t = Time.now if BT.verbose
    faildesc, errout = with_stderr {yield}
    t = Time.now - t if BT.verbose

    if !faildesc
      # success
      if BT.quiet || BT.wn > 1
        # do nothing
      elsif BT.tty
        $stderr.print "#{BT.progress_bs}#{BT.progress[BT_STATE.count % BT.progress.size]}"
      elsif BT.verbose
        $stderr.printf(". %.3f\n", t)
      else
        BT.putc '.'
      end
    else
      $stderr.print "#{BT.failed}F"
      $stderr.printf(" %.3f", t) if BT.verbose
      $stderr.print BT.reset
      $stderr.puts if BT.verbose
      show_error faildesc, message
      unless errout.empty?
        $stderr.print "#{BT.failed}stderr output is not empty#{BT.reset}\n", adjust_indent(errout)
      end

      if BT.tty and !BT.verbose and BT.wn == 1
        $stderr.printf("%-*s%s", BT.width, path, BT.progress[BT_STATE.count % BT.progress.size])
      end
    end
  rescue Interrupt
    $stderr.puts "\##{@id} #{path}:#{lineno}"
    raise
  rescue Exception => err
    $stderr.print 'E'
    $stderr.puts if BT.verbose
    show_error err.message, message
  ensure
    begin
      check_coredump
    rescue CoreDumpError => err
      $stderr.print 'E'
      $stderr.puts if BT.verbose
      show_error err.message, message
      cleanup_coredump
    end
  end

  def get_result_string(opt = '', **argh)
    if BT.ruby
      filename = make_srcfile(**argh)
      begin
        kw = self.err ? {err: self.err} : {}
        out = IO.popen("#{BT.ruby} -W0 #{opt} #{filename}", **kw)
        pid = out.pid
        out.read.tap{ Process.waitpid(pid); out.close }
      ensure
        raise Interrupt if $? and $?.signaled? && $?.termsig == Signal.list["INT"]

        begin
          Process.kill :KILL, pid
        rescue Errno::ESRCH
          # OK
        end
      end
    else
      eval(src).to_s
    end
  end

  def make_srcfile(frozen_string_literal: nil)
    filename = "bootstraptest.#{self.path}_#{self.lineno}_#{self.id}.rb"
    File.open(filename, 'w') {|f|
      f.puts "#frozen_string_literal:true" if frozen_string_literal
      if $stress
        f.puts "GC.stress = true" if $stress
      else
        f.puts ""
      end
      f.puts "class BT_Skip < Exception; end; def skip(msg) = raise(BT_Skip, msg.to_s)"
      f.puts "print(begin; #{self.src}; rescue BT_Skip; $!.message; end)"
    }
    filename
  end
end

def add_assertion src, pr
  loc = caller_locations(2, 1).first
  lineno = loc.lineno
  path = File.basename(loc.path)

  Assertion.new(src, path, lineno, pr)
end

def assert_equal(expected, testsrc, message = '', opt = '', **argh)
  add_assertion testsrc, -> as do
    as.assert_check(message, opt, **argh) {|result|
      if expected == result
        nil
      else
        desc = "#{result.inspect} (expected #{expected.inspect})"
        pretty(testsrc, desc, result)
      end
    }
  end
end

def assert_match(expected_pattern, testsrc, message = '')
  add_assertion testsrc, -> as do
    as.assert_check(message) {|result|
      if expected_pattern =~ result
        nil
      else
        desc = "#{expected_pattern.inspect} expected to be =~\n#{result.inspect}"
        pretty(testsrc, desc, result)
      end
    }
  end
end

def assert_not_match(unexpected_pattern, testsrc, message = '')
  add_assertion testsrc, -> as do
    as.assert_check(message) {|result|
      if unexpected_pattern !~ result
        nil
      else
        desc = "#{unexpected_pattern.inspect} expected to be !~\n#{result.inspect}"
        pretty(testsrc, desc, result)
      end
    }
  end
end

def assert_valid_syntax(testsrc, message = '')
  add_assertion testsrc, -> as do
    as.assert_check(message, '-c') {|result|
      result if /Syntax OK/ !~ result
    }
  end
end

def assert_normal_exit(testsrc, *rest, timeout: nil, **opt)
  add_assertion testsrc, -> as do
    message, ignore_signals = rest
    message ||= ''
    as.show_progress(message) {
      faildesc = nil
      filename = as.make_srcfile
      timeout_signaled = false
      logfile = "assert_normal_exit.#{as.path}.#{as.lineno}.log"

      begin
        err = open(logfile, "w")
        io = IO.popen("#{BT.ruby} -W0 #{filename}", err: err)
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
        err.close
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
          stderr_log = File.read(logfile)
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
end

def assert_finish(timeout_seconds, testsrc, message = '')
  add_assertion testsrc, -> as do
    if defined?(RubyVM::RJIT) && RubyVM::RJIT.enabled? # for --jit-wait
      timeout_seconds *= 3
    end

    as.show_progress(message) {
      faildesc = nil
      filename = as.make_srcfile
      io = IO.popen("#{BT.ruby} -W0 #{filename}", err: as.err)
      pid = io.pid
      waited = false
      tlimit = Time.now + timeout_seconds
      diff = timeout_seconds
      while diff > 0
        if Process.waitpid pid, Process::WNOHANG
          waited = true
          break
        end
        if io.respond_to?(:read_nonblock)
          if IO.select([io], nil, nil, diff)
            begin
              io.read_nonblock(1024)
            rescue Errno::EAGAIN, IO::WaitReadable, EOFError
              break
            end while true
          end
        else
          sleep 0.1
        end
        diff = tlimit - Time.now
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
end

def flunk(message = '')
  add_assertion '', -> as do
    as.show_progress('') { message }
  end
end

def show_limit(testsrc, opt = '', **argh)
  return if BT.quiet

  add_assertion testsrc, -> as do
    result = as.get_result_string(opt, **argh)
    Assertion.errbuf << result
  end
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
  if File.file?('core')
    require 'time'
    Dir.glob('/tmp/bootstraptest-core.*').each do |f|
      if Time.now - File.mtime(f) > 7 * 24 * 60 * 60 # 7 days
        warn "Deleting an old core file: #{f}"
        FileUtils.rm(f)
      end
    end
    core_path = "/tmp/bootstraptest-core.#{Time.now.utc.iso8601}"
    warn "A core file is found. Saving it at: #{core_path.dump}"
    FileUtils.mv('core', core_path)
    cmd = ['gdb', BT.ruby, '-c', core_path, '-ex', 'bt', '-batch']
    p cmd # debugging why it's not working
    system(*cmd)
  end
  FileUtils.rm_f Dir.glob('core.*')
  FileUtils.rm_f BT.ruby+'.stackdump' if BT.ruby
end

class CoreDumpError < StandardError; end

def check_coredump
  if File.file?('core') or not Dir.glob('core.*').empty? or
      (BT.ruby and File.exist?(BT.ruby+'.stackdump'))
    raise CoreDumpError, "core dumped"
  end
end

def yjit_enabled?
  ENV.key?('RUBY_YJIT_ENABLE') || ENV.fetch('RUN_OPTS', '').include?('yjit') || BT.ruby.include?('yjit')
end

def rjit_enabled?
  # Don't check `RubyVM::RJIT.enabled?`. On btest-bruby, target Ruby != runner Ruby.
  ENV.fetch('RUN_OPTS', '').include?('rjit')
end

def mmtk?
  `#{BT.ruby} -e 'print (defined?(GC::MMTk.enabled?) && GC::MMTk.enabled?) || false'` == 'true'
end

exit main
