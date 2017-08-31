# coding: US-ASCII
# frozen_string_literal: false
require 'test/unit'
require 'logger'
require 'tempfile'

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

  def test_symbol_level
    logger_symbol_levels = {
      debug:   DEBUG,
      info:    INFO,
      warn:    WARN,
      error:   ERROR,
      fatal:   FATAL,
      unknown: UNKNOWN,
      DEBUG:   DEBUG,
      INFO:    INFO,
      WARN:    WARN,
      ERROR:   ERROR,
      FATAL:   FATAL,
      UNKNOWN: UNKNOWN,
    }
    logger_symbol_levels.each do |symbol, level|
      @logger.level = symbol
      assert(@logger.level == level)
    end
    assert_raise(ArgumentError) { @logger.level = :something_wrong }
  end

  def test_string_level
    logger_string_levels = {
      'debug'   => DEBUG,
      'info'    => INFO,
      'warn'    => WARN,
      'error'   => ERROR,
      'fatal'   => FATAL,
      'unknown' => UNKNOWN,
      'DEBUG'   => DEBUG,
      'INFO'    => INFO,
      'WARN'    => WARN,
      'ERROR'   => ERROR,
      'FATAL'   => FATAL,
      'UNKNOWN' => UNKNOWN,
    }
    logger_string_levels.each do |string, level|
      @logger.level = string
      assert(@logger.level == level)
    end
    assert_raise(ArgumentError) { @logger.level = 'something_wrong' }
  end

  def test_progname
    assert_nil(@logger.progname)
    @logger.progname = "name"
    assert_equal("name", @logger.progname)
  end

  def test_datetime_format
    verbose, $VERBOSE = $VERBOSE, false
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
  ensure
    $VERBOSE = verbose
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

  def test_initialize_with_level
    # default
    logger = Logger.new(STDERR)
    assert_equal(Logger::DEBUG, logger.level)
    # config
    logger = Logger.new(STDERR, level: :info)
    assert_equal(Logger::INFO, logger.level)
  end

  def test_initialize_with_progname
    # default
    logger = Logger.new(STDERR)
    assert_equal(nil, logger.progname)
    # config
    logger = Logger.new(STDERR, progname: :progname)
    assert_equal(:progname, logger.progname)
  end

  def test_initialize_with_formatter
    # default
    logger = Logger.new(STDERR)
    log = log(logger, :info, "foo")
    assert_equal("foo\n", log.msg)
    # config
    logger = Logger.new(STDERR, formatter: proc { |severity, timestamp, progname, msg|
      "#{severity}:#{msg}\n\n"
    })
    line = log_raw(logger, :info, "foo")
    assert_equal("INFO:foo\n\n", line)
  end

  def test_initialize_with_datetime_format
    # default
    logger = Logger.new(STDERR)
    log = log_add(logger, INFO, "foo")
    assert_match(/^\d\d\d\d-\d\d-\d\dT\d\d:\d\d:\d\d.\s*\d+ $/, log.datetime)
    # config
    logger = Logger.new(STDERR, datetime_format: "%d%b%Y@%H:%M:%S")
    log = log_add(logger, INFO, "foo")
    assert_match(/^\d\d\w\w\w\d\d\d\d@\d\d:\d\d:\d\d$/, log.datetime)
  end

  def test_reopen
    logger = Logger.new(STDERR)
    logger.reopen(STDOUT)
    assert_equal(STDOUT, logger.instance_variable_get(:@logdev).dev)
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
    #
    logger = Logger.new(nil)
    log = log_add(logger, INFO, nil, false)
    assert_equal("false\n", log.msg)
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
