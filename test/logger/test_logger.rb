# coding: US-ASCII
require 'test/unit'
require 'logger'
require 'tempfile'
require 'tmpdir'
require_relative '../ruby/envutil'


class TestLoggerSeverity < Test::Unit::TestCase
  def test_enum
    logger_levels = Logger.constants
    levels = ["WARN", "UNKNOWN", "INFO", "FATAL", "DEBUG", "ERROR"]
    Logger::Severity.constants.each do |level|
      assert(levels.include?(level.to_s))
      assert(logger_levels.include?(level))
    end
    assert_equal(levels.size, Logger::Severity.constants.size)
  end
end


class TestLogger < Test::Unit::TestCase
  include Logger::Severity

  def setup
    @logger = Logger.new(nil)
  end

  class Log
    attr_reader :label, :datetime, :pid, :severity, :progname, :msg
    def initialize(line)
      /\A(\w+), \[([^#]*)#(\d+)\]\s+(\w+) -- (\w*): ([\x0-\xff]*)/ =~ line
      @label, @datetime, @pid, @severity, @progname, @msg = $1, $2, $3, $4, $5, $6
    end
  end

  def log_add(logger, severity, msg, progname = nil, &block)
    log(logger, :add, severity, msg, progname, &block)
  end

  def log(logger, msg_id, *arg, &block)
    Log.new(log_raw(logger, msg_id, *arg, &block))
  end

  def log_raw(logger, msg_id, *arg, &block)
    Tempfile.create(File.basename(__FILE__) + '.log') {|logdev|
      logger.instance_eval { @logdev = Logger::LogDevice.new(logdev) }
      logger.__send__(msg_id, *arg, &block)
      logdev.rewind
      logdev.read
    }
  end

  def test_level
    @logger.level = UNKNOWN
    assert_equal(UNKNOWN, @logger.level)
    @logger.level = INFO
    assert_equal(INFO, @logger.level)
    @logger.sev_threshold = ERROR
    assert_equal(ERROR, @logger.sev_threshold)
    @logger.sev_threshold = WARN
    assert_equal(WARN, @logger.sev_threshold)
    assert_equal(WARN, @logger.level)

    @logger.level = DEBUG
    assert(@logger.debug?)
    assert(@logger.info?)
    @logger.level = INFO
    assert(!@logger.debug?)
    assert(@logger.info?)
    assert(@logger.warn?)
    @logger.level = WARN
    assert(!@logger.info?)
    assert(@logger.warn?)
    assert(@logger.error?)
    @logger.level = ERROR
    assert(!@logger.warn?)
    assert(@logger.error?)
    assert(@logger.fatal?)
    @logger.level = FATAL
    assert(!@logger.error?)
    assert(@logger.fatal?)
    @logger.level = UNKNOWN
    assert(!@logger.error?)
    assert(!@logger.fatal?)
  end

  def test_progname
    assert_nil(@logger.progname)
    @logger.progname = "name"
    assert_equal("name", @logger.progname)
  end

  def test_datetime_format
    dummy = STDERR
    logger = Logger.new(dummy)
    log = log_add(logger, INFO, "foo")
    assert_match(/^\d\d\d\d-\d\d-\d\dT\d\d:\d\d:\d\d.\s*\d+ $/, log.datetime)
    logger.datetime_format = "%d%b%Y@%H:%M:%S"
    log = log_add(logger, INFO, "foo")
    assert_match(/^\d\d\w\w\w\d\d\d\d@\d\d:\d\d:\d\d$/, log.datetime)
    logger.datetime_format = ""
    log = log_add(logger, INFO, "foo")
    assert_match(/^$/, log.datetime)
  end

  def test_formatter
    dummy = STDERR
    logger = Logger.new(dummy)
    # default
    log = log(logger, :info, "foo")
    assert_equal("foo\n", log.msg)
    # config
    logger.formatter = proc { |severity, timestamp, progname, msg|
      "#{severity}:#{msg}\n\n"
    }
    line = log_raw(logger, :info, "foo")
    assert_equal("INFO:foo\n\n", line)
    # recover
    logger.formatter = nil
    log = log(logger, :info, "foo")
    assert_equal("foo\n", log.msg)
    # again
    o = Object.new
    def o.call(severity, timestamp, progname, msg)
      "<<#{severity}-#{msg}>>\n"
    end
    logger.formatter = o
    line = log_raw(logger, :info, "foo")
    assert_equal("<""<INFO-foo>>\n", line)
  end

  def test_initialize
    logger = Logger.new(STDERR)
    assert_nil(logger.progname)
    assert_equal(DEBUG, logger.level)
    assert_nil(logger.datetime_format)
  end

  def test_add
    logger = Logger.new(nil)
    logger.progname = "my_progname"
    assert(logger.add(INFO))
    log = log_add(logger, nil, "msg")
    assert_equal("ANY", log.severity)
    assert_equal("my_progname", log.progname)
    logger.level = WARN
    assert(logger.log(INFO))
    assert_nil(log_add(logger, INFO, "msg").msg)
    log = log_add(logger, WARN, nil) { "msg" }
    assert_equal("msg\n", log.msg)
    log = log_add(logger, WARN, "") { "msg" }
    assert_equal("\n", log.msg)
    assert_equal("my_progname", log.progname)
    log = log_add(logger, WARN, nil, "progname?")
    assert_equal("progname?\n", log.msg)
    assert_equal("my_progname", log.progname)
  end

  def test_level_log
    logger = Logger.new(nil)
    logger.progname = "my_progname"
    log = log(logger, :debug, "custom_progname") { "msg" }
    assert_equal("msg\n", log.msg)
    assert_equal("custom_progname", log.progname)
    assert_equal("DEBUG", log.severity)
    assert_equal("D", log.label)
    #
    log = log(logger, :debug) { "msg_block" }
    assert_equal("msg_block\n", log.msg)
    assert_equal("my_progname", log.progname)
    log = log(logger, :debug, "msg_inline")
    assert_equal("msg_inline\n", log.msg)
    assert_equal("my_progname", log.progname)
    #
    log = log(logger, :info, "custom_progname") { "msg" }
    assert_equal("msg\n", log.msg)
    assert_equal("custom_progname", log.progname)
    assert_equal("INFO", log.severity)
    assert_equal("I", log.label)
    #
    log = log(logger, :warn, "custom_progname") { "msg" }
    assert_equal("msg\n", log.msg)
    assert_equal("custom_progname", log.progname)
    assert_equal("WARN", log.severity)
    assert_equal("W", log.label)
    #
    log = log(logger, :error, "custom_progname") { "msg" }
    assert_equal("msg\n", log.msg)
    assert_equal("custom_progname", log.progname)
    assert_equal("ERROR", log.severity)
    assert_equal("E", log.label)
    #
    log = log(logger, :fatal, "custom_progname") { "msg" }
    assert_equal("msg\n", log.msg)
    assert_equal("custom_progname", log.progname)
    assert_equal("FATAL", log.severity)
    assert_equal("F", log.label)
    #
    log = log(logger, :unknown, "custom_progname") { "msg" }
    assert_equal("msg\n", log.msg)
    assert_equal("custom_progname", log.progname)
    assert_equal("ANY", log.severity)
    assert_equal("A", log.label)
  end

  def test_close
    r, w = IO.pipe
    assert(!w.closed?)
    logger = Logger.new(w)
    logger.close
    assert(w.closed?)
    r.close
  end

  class MyError < StandardError
  end

  class MyMsg
    def inspect
      "my_msg"
    end
  end

  def test_format
    logger = Logger.new(nil)
    log = log_add(logger, INFO, "msg\n")
    assert_equal("msg\n\n", log.msg)
    begin
      raise MyError.new("excn")
    rescue MyError => e
      log = log_add(logger, INFO, e)
      assert_match(/^excn \(TestLogger::MyError\)/, log.msg)
      # expects backtrace is dumped across multi lines.  10 might be changed.
      assert(log.msg.split(/\n/).size >= 10)
    end
    log = log_add(logger, INFO, MyMsg.new)
    assert_equal("my_msg\n", log.msg)
  end

  def test_lshift
    r, w = IO.pipe
    logger = Logger.new(w)
    logger << "msg"
    read_ready, = IO.select([r], nil, nil, 0.1)
    w.close
    msg = r.read
    r.close
    assert_equal("msg", msg)
    #
    r, w = IO.pipe
    logger = Logger.new(w)
    logger << "msg2\n\n"
    read_ready, = IO.select([r], nil, nil, 0.1)
    w.close
    msg = r.read
    r.close
    assert_equal("msg2\n\n", msg)
  end
end

class TestLogDevice < Test::Unit::TestCase
  class LogExcnRaiser
    def write(*arg)
      raise 'disk is full'
    end

    def close
    end

    def stat
      Object.new
    end
  end

  def setup
    @tempfile = Tempfile.new("logger")
    @tempfile.close
    @filename = @tempfile.path
    File.unlink(@filename)
  end

  def teardown
    @tempfile.close(true)
  end

  def d(log, opt = {})
    Logger::LogDevice.new(log, opt)
  end

  def test_initialize
    logdev = d(STDERR)
    assert_equal(STDERR, logdev.dev)
    assert_nil(logdev.filename)
    assert_raises(TypeError) do
      d(nil)
    end
    #
    logdev = d(@filename)
    begin
      assert(File.exist?(@filename))
      assert(logdev.dev.sync)
      assert_equal(@filename, logdev.filename)
      logdev.write('hello')
    ensure
      logdev.close
    end
    # create logfile whitch is already exist.
    logdev = d(@filename)
    begin
      logdev.write('world')
      logfile = File.read(@filename)
      assert_equal(2, logfile.split(/\n/).size)
      assert_match(/^helloworld$/, logfile)
    ensure
      logdev.close
    end
  end

  def test_write
    r, w = IO.pipe
    logdev = d(w)
    logdev.write("msg2\n\n")
    read_ready, = IO.select([r], nil, nil, 0.1)
    w.close
    msg = r.read
    r.close
    assert_equal("msg2\n\n", msg)
    #
    logdev = d(LogExcnRaiser.new)
    class << (stderr = '')
      alias write <<
    end
    $stderr, stderr = stderr, $stderr
    begin
      assert_nothing_raised do
        logdev.write('hello')
      end
    ensure
      logdev.close
      $stderr, stderr = stderr, $stderr
    end
    assert_equal "log writing failed. disk is full\n", stderr
  end

  def test_close
    r, w = IO.pipe
    logdev = d(w)
    logdev.write("msg2\n\n")
    read_ready, = IO.select([r], nil, nil, 0.1)
    assert(!w.closed?)
    logdev.close
    assert(w.closed?)
    r.close
  end

  def test_shifting_size
    tmpfile = Tempfile.new([File.basename(__FILE__, '.*'), '_1.log'])
    logfile = tmpfile.path
    logfile0 = logfile + '.0'
    logfile1 = logfile + '.1'
    logfile2 = logfile + '.2'
    logfile3 = logfile + '.3'
    tmpfile.close(true)
    File.unlink(logfile) if File.exist?(logfile)
    File.unlink(logfile0) if File.exist?(logfile0)
    File.unlink(logfile1) if File.exist?(logfile1)
    File.unlink(logfile2) if File.exist?(logfile2)
    logger = Logger.new(logfile, 4, 100)
    logger.error("0" * 15)
    assert(File.exist?(logfile))
    assert(!File.exist?(logfile0))
    logger.error("0" * 15)
    assert(File.exist?(logfile0))
    assert(!File.exist?(logfile1))
    logger.error("0" * 15)
    assert(File.exist?(logfile1))
    assert(!File.exist?(logfile2))
    logger.error("0" * 15)
    assert(File.exist?(logfile2))
    assert(!File.exist?(logfile3))
    logger.error("0" * 15)
    assert(!File.exist?(logfile3))
    logger.error("0" * 15)
    assert(!File.exist?(logfile3))
    logger.close
    File.unlink(logfile)
    File.unlink(logfile0)
    File.unlink(logfile1)
    File.unlink(logfile2)

    tmpfile = Tempfile.new([File.basename(__FILE__, '.*'), '_2.log'])
    logfile = tmpfile.path
    logfile0 = logfile + '.0'
    logfile1 = logfile + '.1'
    logfile2 = logfile + '.2'
    logfile3 = logfile + '.3'
    tmpfile.close(true)
    logger = Logger.new(logfile, 4, 150)
    logger.error("0" * 15)
    assert(File.exist?(logfile))
    assert(!File.exist?(logfile0))
    logger.error("0" * 15)
    assert(!File.exist?(logfile0))
    logger.error("0" * 15)
    assert(File.exist?(logfile0))
    assert(!File.exist?(logfile1))
    logger.error("0" * 15)
    assert(!File.exist?(logfile1))
    logger.error("0" * 15)
    assert(File.exist?(logfile1))
    assert(!File.exist?(logfile2))
    logger.error("0" * 15)
    assert(!File.exist?(logfile2))
    logger.error("0" * 15)
    assert(File.exist?(logfile2))
    assert(!File.exist?(logfile3))
    logger.error("0" * 15)
    assert(!File.exist?(logfile3))
    logger.error("0" * 15)
    assert(!File.exist?(logfile3))
    logger.error("0" * 15)
    assert(!File.exist?(logfile3))
    logger.close
    File.unlink(logfile)
    File.unlink(logfile0)
    File.unlink(logfile1)
    File.unlink(logfile2)
  end

  def test_shifting_age_variants
    logger = Logger.new(@filename, 'daily')
    logger.info('daily')
    logger.close
    logger = Logger.new(@filename, 'weekly')
    logger.info('weekly')
    logger.close
    logger = Logger.new(@filename, 'monthly')
    logger.info('monthly')
    logger.close
  end

  def test_shifting_age
    # shift_age other than 'daily', 'weekly', and 'monthly' means 'everytime'
    yyyymmdd = Time.now.strftime("%Y%m%d")
    filename1 = @filename + ".#{yyyymmdd}"
    filename2 = @filename + ".#{yyyymmdd}.1"
    filename3 = @filename + ".#{yyyymmdd}.2"
    begin
      logger = Logger.new(@filename, 'now')
      assert(File.exist?(@filename))
      assert(!File.exist?(filename1))
      assert(!File.exist?(filename2))
      assert(!File.exist?(filename3))
      logger.info("0" * 15)
      assert(File.exist?(@filename))
      assert(File.exist?(filename1))
      assert(!File.exist?(filename2))
      assert(!File.exist?(filename3))
      logger.warn("0" * 15)
      assert(File.exist?(@filename))
      assert(File.exist?(filename1))
      assert(File.exist?(filename2))
      assert(!File.exist?(filename3))
      logger.error("0" * 15)
      assert(File.exist?(@filename))
      assert(File.exist?(filename1))
      assert(File.exist?(filename2))
      assert(File.exist?(filename3))
    ensure
      logger.close if logger
      [filename1, filename2, filename3].each do |filename|
        File.unlink(filename) if File.exist?(filename)
      end
    end
  end

  def test_shifting_size_in_multiprocess
    tmpfile = Tempfile.new([File.basename(__FILE__, '.*'), '_1.log'])
    logfile = tmpfile.path
    logfile0 = logfile + '.0'
    logfile1 = logfile + '.1'
    logfile2 = logfile + '.2'
    logfile3 = logfile + '.3'
    tmpfile.close(true)
    File.unlink(logfile) if File.exist?(logfile)
    File.unlink(logfile0) if File.exist?(logfile0)
    File.unlink(logfile1) if File.exist?(logfile1)
    File.unlink(logfile2) if File.exist?(logfile2)
    begin
      stderr = run_children(2, [logfile], <<-'END')
        logger = Logger.new(ARGV[0], 4, 10)
        10.times do
          logger.info '0' * 15
        end
      END
      assert_no_match(/log shifting failed/, stderr)
      assert_no_match(/log writing failed/, stderr)
      assert_no_match(/log rotation inter-process lock failed/, stderr)
    ensure
      File.unlink(logfile) if File.exist?(logfile)
      File.unlink(logfile0) if File.exist?(logfile0)
      File.unlink(logfile1) if File.exist?(logfile1)
      File.unlink(logfile2) if File.exist?(logfile2)
    end
  end

  def test_shifting_age_in_multiprocess
    yyyymmdd = Time.now.strftime("%Y%m%d")
    begin
      stderr = run_children(2, [@filename], <<-'END')
        logger = Logger.new(ARGV[0], 'now')
        10.times do
          logger.info '0' * 15
        end
      END
      assert_no_match(/log shifting failed/, stderr)
      assert_no_match(/log writing failed/, stderr)
      assert_no_match(/log rotation inter-process lock failed/, stderr)
    ensure
      Dir.glob("#{@filename}.#{yyyymmdd}{,.[1-9]*}") do |filename|
        File.unlink(filename) if File.exist?(filename)
      end
    end
  end

  def test_open_logfile_in_multiprocess
    tmpfile = Tempfile.new([File.basename(__FILE__, '.*'), '_1.log'])
    logfile = tmpfile.path
    tmpfile.close(true)
    begin
      20.times do
        run_children(2, [logfile], <<-'END')
          logfile = ARGV[0]
          logdev = Logger::LogDevice.new(logfile)
          logdev.send(:open_logfile, logfile)
        END
        assert_equal(1, File.readlines(logfile).grep(/# Logfile created on/).size)
        File.unlink(logfile)
      end
    ensure
      File.unlink(logfile) if File.exist?(logfile)
    end
  end

  def test_shifting_size_not_rotate_too_much
    d(@filename).__send__(:add_log_header, @tempfile)
    header_size = @tempfile.size
    message = "*" * 99 + "\n"
    shift_size = header_size + message.size * 3 - 1
    opt = {shift_age: 1, shift_size: shift_size}

    Dir.mktmpdir do |tmpdir|
      begin
        log = File.join(tmpdir, "log")
        logdev1 = d(log, opt)
        logdev2 = d(log, opt)

        assert_file.identical?(log, logdev1.dev)
        assert_file.identical?(log, logdev2.dev)

        3.times{logdev1.write(message)}
        assert_file.identical?(log, logdev1.dev)
        assert_file.identical?(log, logdev2.dev)

        logdev1.write(message)
        assert_file.identical?(log, logdev1.dev)
        assert_file.identical?(log + ".0", logdev2.dev)

        logdev2.write(message)
        assert_file.identical?(log, logdev1.dev)
        assert_file.identical?(log, logdev2.dev)

        logdev1.write(message)
        assert_file.identical?(log, logdev1.dev)
        assert_file.identical?(log, logdev2.dev)
      ensure
        logdev1.close if logdev1
        logdev2.close if logdev2
      end
    end
  end unless /mswin|mingw/ =~ RUBY_PLATFORM

  private

  def run_children(n, args, src)
    r, w = IO.pipe
    [w, *(1..n).map do
       f = IO.popen([EnvUtil.rubybin, *%w[--disable=gems -rlogger -], *args], "w", err: w)
       f.puts(src)
       f
     end].each(&:close)
    stderr = r.read
    r.close
    stderr
  end
end


class TestLoggerApplication < Test::Unit::TestCase
  def setup
    @app = Logger::Application.new('appname')
    @tempfile = Tempfile.new("logger")
    @tempfile.close
    @filename = @tempfile.path
    File.unlink(@filename)
  end

  def teardown
    @tempfile.close(true)
  end

  def test_initialize
    app = Logger::Application.new('appname')
    assert_equal('appname', app.appname)
  end

  def test_start
    @app.set_log(@filename)
    begin
      @app.level = Logger::UNKNOWN
      @app.start # logs FATAL log
      assert_equal(1, File.read(@filename).split(/\n/).size)
    ensure
      @app.logger.close
    end
  end

  def test_logger
    @app.level = Logger::WARN
    @app.set_log(@filename)
    begin
      assert_equal(Logger::WARN, @app.logger.level)
    ensure
      @app.logger.close
    end
    @app.logger = logger = Logger.new(STDOUT)
    assert_equal(logger, @app.logger)
    assert_equal(Logger::WARN, @app.logger.level)
    @app.log = @filename
    begin
      assert(logger != @app.logger)
      assert_equal(Logger::WARN, @app.logger.level)
    ensure
      @app.logger.close
    end
  end
end
