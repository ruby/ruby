# coding: US-ASCII
require 'test/unit'
require 'tempfile'
begin
  require 'syslog/logger'
rescue LoadError
  # skip.  see the bottom of this file.
end

# These tests ensure Syslog::Logger works like Logger

class TestSyslogRootLogger < Test::Unit::TestCase

  module MockSyslog

    PRIMASK = Syslog::Level.constants.inject(0) { |mask, name| mask | Syslog::Level.const_get(name) }

    LEVEL_LABEL_MAP = {
      Syslog::LOG_ALERT   => 'ALERT',
      Syslog::LOG_ERR     => 'ERR',
      Syslog::LOG_WARNING => 'WARNING',
      Syslog::LOG_NOTICE  => 'NOTICE',
      Syslog::LOG_INFO    => 'INFO',
      Syslog::LOG_DEBUG   => 'DEBUG'
    }

    @facility = Syslog::LOG_USER

    class << self

      attr_reader :facility
      attr_reader :line
      attr_reader :program_name

      def log(priority, format, *args)
        level = priority & PRIMASK
        @line = "<#{priority}> #{LEVEL_LABEL_MAP[level]} - #{format % args}"
      end

      def open(program_name)
        @program_name = program_name
      end

      def reset
        @line = ''
      end

    end
  end

  Syslog::Logger.syslog = MockSyslog

  LEVEL_LABEL_MAP = {
    Logger::DEBUG => 'DEBUG',
    Logger::INFO => 'INFO',
    Logger::WARN => 'WARN',
    Logger::ERROR => 'ERROR',
    Logger::FATAL => 'FATAL',
    Logger::UNKNOWN => 'ANY',
  }

  def setup
    @logger = Logger.new(nil)
  end

  class Log
    attr_reader :line, :label, :datetime, :pid, :severity, :progname, :msg
    def initialize(line)
      @line = line
      /\A(\w+), \[([^#]*)#(\d+)\]\s+(\w+) -- (\w*): ([\x0-\xff]*)/ =~ @line
      @label, @datetime, @pid, @severity, @progname, @msg = $1, $2, $3, $4, $5, $6
    end
  end

  def log_add(severity, msg, progname = nil, &block)
    log(:add, severity, msg, progname, &block)
  end

  def log(msg_id, *arg, &block)
    Log.new(log_raw(msg_id, *arg, &block))
  end

  def log_raw(msg_id, *arg, &block)
    Tempfile.create(File.basename(__FILE__) + '.log') {|logdev|
      @logger.instance_eval { @logdev = Logger::LogDevice.new(logdev) }
      assert_equal true, @logger.__send__(msg_id, *arg, &block)
      logdev.rewind
      logdev.read
    }
  end

  def test_initialize
    assert_equal Logger::DEBUG, @logger.level
  end

  def test_custom_formatter
    @logger.formatter = Class.new {
      def call severity, time, progname, msg
        "hi mom!"
      end
    }.new

    assert_match(/hi mom!/, log_raw(:fatal, 'fatal level message'))
  end

  def test_add
    msg = log_add nil,           'unknown level message' # nil == unknown
    assert_equal LEVEL_LABEL_MAP[Logger::UNKNOWN], msg.severity

    msg = log_add Logger::FATAL, 'fatal level message'
    assert_equal LEVEL_LABEL_MAP[Logger::FATAL],   msg.severity

    msg = log_add Logger::ERROR, 'error level message'
    assert_equal LEVEL_LABEL_MAP[Logger::ERROR],   msg.severity

    msg = log_add Logger::WARN,  'warn level message'
    assert_equal LEVEL_LABEL_MAP[Logger::WARN],    msg.severity

    msg = log_add Logger::INFO,  'info level message'
    assert_equal LEVEL_LABEL_MAP[Logger::INFO],    msg.severity

    msg = log_add Logger::DEBUG, 'debug level message'
    assert_equal LEVEL_LABEL_MAP[Logger::DEBUG],   msg.severity
  end

  def test_add_level_unknown
    @logger.level = Logger::UNKNOWN

    msg = log_add nil,           'unknown level message' # nil == unknown
    assert_equal LEVEL_LABEL_MAP[Logger::UNKNOWN], msg.severity

    msg = log_add Logger::FATAL, 'fatal level message'
    assert_equal '', msg.line

    msg = log_add Logger::ERROR, 'error level message'
    assert_equal '', msg.line

    msg = log_add Logger::WARN,  'warn level message'
    assert_equal '', msg.line

    msg = log_add Logger::INFO,  'info level message'
    assert_equal '', msg.line

    msg = log_add Logger::DEBUG, 'debug level message'
    assert_equal '', msg.line
  end

  def test_add_level_fatal
    @logger.level = Logger::FATAL

    msg = log_add nil,           'unknown level message' # nil == unknown
    assert_equal LEVEL_LABEL_MAP[Logger::UNKNOWN], msg.severity

    msg = log_add Logger::FATAL, 'fatal level message'
    assert_equal LEVEL_LABEL_MAP[Logger::FATAL],   msg.severity

    msg = log_add Logger::ERROR, 'error level message'
    assert_equal '', msg.line

    msg = log_add Logger::WARN,  'warn level message'
    assert_equal '', msg.line

    msg = log_add Logger::INFO,  'info level message'
    assert_equal '', msg.line

    msg = log_add Logger::DEBUG, 'debug level message'
    assert_equal '', msg.line
  end

  def test_add_level_error
    @logger.level = Logger::ERROR

    msg = log_add nil,           'unknown level message' # nil == unknown
    assert_equal LEVEL_LABEL_MAP[Logger::UNKNOWN], msg.severity

    msg = log_add Logger::FATAL, 'fatal level message'
    assert_equal LEVEL_LABEL_MAP[Logger::FATAL],   msg.severity

    msg = log_add Logger::ERROR, 'error level message'
    assert_equal LEVEL_LABEL_MAP[Logger::ERROR],   msg.severity

    msg = log_add Logger::WARN,  'warn level message'
    assert_equal '', msg.line

    msg = log_add Logger::INFO,  'info level message'
    assert_equal '', msg.line

    msg = log_add Logger::DEBUG, 'debug level message'
    assert_equal '', msg.line
  end

  def test_add_level_warn
    @logger.level = Logger::WARN

    msg = log_add nil,           'unknown level message' # nil == unknown
    assert_equal LEVEL_LABEL_MAP[Logger::UNKNOWN], msg.severity

    msg = log_add Logger::FATAL, 'fatal level message'
    assert_equal LEVEL_LABEL_MAP[Logger::FATAL],   msg.severity

    msg = log_add Logger::ERROR, 'error level message'
    assert_equal LEVEL_LABEL_MAP[Logger::ERROR],   msg.severity

    msg = log_add Logger::WARN,  'warn level message'
    assert_equal LEVEL_LABEL_MAP[Logger::WARN],   msg.severity

    msg = log_add Logger::INFO,  'info level message'
    assert_equal '', msg.line

    msg = log_add Logger::DEBUG, 'debug level message'
    assert_equal '', msg.line
  end

  def test_add_level_info
    @logger.level = Logger::INFO

    msg = log_add nil,           'unknown level message' # nil == unknown
    assert_equal LEVEL_LABEL_MAP[Logger::UNKNOWN], msg.severity

    msg = log_add Logger::FATAL, 'fatal level message'
    assert_equal LEVEL_LABEL_MAP[Logger::FATAL],   msg.severity

    msg = log_add Logger::ERROR, 'error level message'
    assert_equal LEVEL_LABEL_MAP[Logger::ERROR],   msg.severity

    msg = log_add Logger::WARN,  'warn level message'
    assert_equal LEVEL_LABEL_MAP[Logger::WARN],    msg.severity

    msg = log_add Logger::INFO,  'info level message'
    assert_equal LEVEL_LABEL_MAP[Logger::INFO],    msg.severity

    msg = log_add Logger::DEBUG, 'debug level message'
    assert_equal '', msg.line
  end

  def test_add_level_debug
    @logger.level = Logger::DEBUG

    msg = log_add nil,           'unknown level message' # nil == unknown
    assert_equal LEVEL_LABEL_MAP[Logger::UNKNOWN], msg.severity

    msg = log_add Logger::FATAL, 'fatal level message'
    assert_equal LEVEL_LABEL_MAP[Logger::FATAL],   msg.severity

    msg = log_add Logger::ERROR, 'error level message'
    assert_equal LEVEL_LABEL_MAP[Logger::ERROR],   msg.severity

    msg = log_add Logger::WARN,  'warn level message'
    assert_equal LEVEL_LABEL_MAP[Logger::WARN],    msg.severity

    msg = log_add Logger::INFO,  'info level message'
    assert_equal LEVEL_LABEL_MAP[Logger::INFO],    msg.severity

    msg = log_add Logger::DEBUG, 'debug level message'
    assert_equal LEVEL_LABEL_MAP[Logger::DEBUG],   msg.severity
  end

  def test_unknown
    msg = log :unknown, 'unknown level message'
    assert_equal LEVEL_LABEL_MAP[Logger::UNKNOWN], msg.severity

    @logger.level = Logger::UNKNOWN
    msg = log :unknown, 'unknown level message'
    assert_equal LEVEL_LABEL_MAP[Logger::UNKNOWN], msg.severity

    @logger.level = Logger::FATAL
    msg = log :unknown, 'unknown level message'
    assert_equal LEVEL_LABEL_MAP[Logger::UNKNOWN], msg.severity

    @logger.level = Logger::ERROR
    msg = log :unknown, 'unknown level message'
    assert_equal LEVEL_LABEL_MAP[Logger::UNKNOWN], msg.severity

    @logger.level = Logger::WARN
    msg = log :unknown, 'unknown level message'
    assert_equal LEVEL_LABEL_MAP[Logger::UNKNOWN], msg.severity

    @logger.level = Logger::INFO
    msg = log :unknown, 'unknown level message'
    assert_equal LEVEL_LABEL_MAP[Logger::UNKNOWN], msg.severity

    @logger.level = Logger::DEBUG
    msg = log :unknown, 'unknown level message'
    assert_equal LEVEL_LABEL_MAP[Logger::UNKNOWN], msg.severity
  end

  def test_fatal
    msg = log :fatal, 'fatal level message'
    assert_equal LEVEL_LABEL_MAP[Logger::FATAL], msg.severity

    @logger.level = Logger::UNKNOWN
    msg = log :fatal, 'fatal level message'
    assert_equal '', msg.line

    @logger.level = Logger::FATAL
    msg = log :fatal, 'fatal level message'
    assert_equal LEVEL_LABEL_MAP[Logger::FATAL], msg.severity

    @logger.level = Logger::ERROR
    msg = log :fatal, 'fatal level message'
    assert_equal LEVEL_LABEL_MAP[Logger::FATAL], msg.severity

    @logger.level = Logger::WARN
    msg = log :fatal, 'fatal level message'
    assert_equal LEVEL_LABEL_MAP[Logger::FATAL], msg.severity

    @logger.level = Logger::INFO
    msg = log :fatal, 'fatal level message'
    assert_equal LEVEL_LABEL_MAP[Logger::FATAL], msg.severity

    @logger.level = Logger::DEBUG
    msg = log :fatal, 'fatal level message'
    assert_equal LEVEL_LABEL_MAP[Logger::FATAL], msg.severity
  end

  def test_fatal_eh
    @logger.level = Logger::FATAL
    assert_equal true, @logger.fatal?

    @logger.level = Logger::UNKNOWN
    assert_equal false, @logger.fatal?
  end

  def test_error
    msg = log :error, 'error level message'
    assert_equal LEVEL_LABEL_MAP[Logger::ERROR], msg.severity

    @logger.level = Logger::UNKNOWN
    msg = log :error, 'error level message'
    assert_equal '', msg.line

    @logger.level = Logger::FATAL
    msg = log :error, 'error level message'
    assert_equal '', msg.line

    @logger.level = Logger::ERROR
    msg = log :error, 'error level message'
    assert_equal LEVEL_LABEL_MAP[Logger::ERROR], msg.severity

    @logger.level = Logger::WARN
    msg = log :error, 'error level message'
    assert_equal LEVEL_LABEL_MAP[Logger::ERROR], msg.severity

    @logger.level = Logger::INFO
    msg = log :error, 'error level message'
    assert_equal LEVEL_LABEL_MAP[Logger::ERROR], msg.severity

    @logger.level = Logger::DEBUG
    msg = log :error, 'error level message'
    assert_equal LEVEL_LABEL_MAP[Logger::ERROR], msg.severity
  end

  def test_error_eh
    @logger.level = Logger::ERROR
    assert_equal true, @logger.error?

    @logger.level = Logger::FATAL
    assert_equal false, @logger.error?
  end

  def test_warn
    msg = log :warn, 'warn level message'
    assert_equal LEVEL_LABEL_MAP[Logger::WARN], msg.severity

    @logger.level = Logger::UNKNOWN
    msg = log :warn, 'warn level message'
    assert_equal '', msg.line

    @logger.level = Logger::FATAL
    msg = log :warn, 'warn level message'
    assert_equal '', msg.line

    @logger.level = Logger::ERROR
    msg = log :warn, 'warn level message'
    assert_equal '', msg.line

    @logger.level = Logger::WARN
    msg = log :warn, 'warn level message'
    assert_equal LEVEL_LABEL_MAP[Logger::WARN], msg.severity

    @logger.level = Logger::INFO
    msg = log :warn, 'warn level message'
    assert_equal LEVEL_LABEL_MAP[Logger::WARN], msg.severity

    @logger.level = Logger::DEBUG
    msg = log :warn, 'warn level message'
    assert_equal LEVEL_LABEL_MAP[Logger::WARN], msg.severity
  end

  def test_warn_eh
    @logger.level = Logger::WARN
    assert_equal true, @logger.warn?

    @logger.level = Logger::ERROR
    assert_equal false, @logger.warn?
  end

  def test_info
    msg = log :info, 'info level message'
    assert_equal LEVEL_LABEL_MAP[Logger::INFO], msg.severity

    @logger.level = Logger::UNKNOWN
    msg = log :info, 'info level message'
    assert_equal '', msg.line

    @logger.level = Logger::FATAL
    msg = log :info, 'info level message'
    assert_equal '', msg.line

    @logger.level = Logger::ERROR
    msg = log :info, 'info level message'
    assert_equal '', msg.line

    @logger.level = Logger::WARN
    msg = log :info, 'info level message'
    assert_equal '', msg.line

    @logger.level = Logger::INFO
    msg = log :info, 'info level message'
    assert_equal LEVEL_LABEL_MAP[Logger::INFO], msg.severity

    @logger.level = Logger::DEBUG
    msg = log :info, 'info level message'
    assert_equal LEVEL_LABEL_MAP[Logger::INFO], msg.severity
  end

  def test_info_eh
    @logger.level = Logger::INFO
    assert_equal true, @logger.info?

    @logger.level = Logger::WARN
    assert_equal false, @logger.info?
  end

  def test_debug
    msg = log :debug, 'debug level message'
    assert_equal LEVEL_LABEL_MAP[Logger::DEBUG], msg.severity

    @logger.level = Logger::UNKNOWN
    msg = log :debug, 'debug level message'
    assert_equal '', msg.line

    @logger.level = Logger::FATAL
    msg = log :debug, 'debug level message'
    assert_equal '', msg.line

    @logger.level = Logger::ERROR
    msg = log :debug, 'debug level message'
    assert_equal '', msg.line

    @logger.level = Logger::WARN
    msg = log :debug, 'debug level message'
    assert_equal '', msg.line

    @logger.level = Logger::INFO
    msg = log :debug, 'debug level message'
    assert_equal '', msg.line

    @logger.level = Logger::DEBUG
    msg = log :debug, 'debug level message'
    assert_equal LEVEL_LABEL_MAP[Logger::DEBUG], msg.severity
  end

  def test_debug_eh
    @logger.level = Logger::DEBUG
    assert_equal true, @logger.debug?

    @logger.level = Logger::INFO
    assert_equal false, @logger.debug?
  end

end if defined?(Syslog)

class TestSyslogLogger < TestSyslogRootLogger

  @facility = Syslog::LOG_USER

  def facility
    self.class.instance_variable_get("@facility")
  end

  def setup
    super
    @logger = Syslog::Logger.new
  end

  SEVERITY_MAP = {}.tap { |map|
    level2severity = Syslog::Logger::LEVEL_MAP.invert

    MockSyslog::LEVEL_LABEL_MAP.each { |level, name|
      map[name] = TestSyslogRootLogger::LEVEL_LABEL_MAP[level2severity[level]]
    }
  }

  class Log
    attr_reader :line, :label, :datetime, :pid, :severity, :progname, :msg, :priority
    def initialize(line)
      @line = line
      return unless /\A<(\d+)> (\w+) - (.*)\Z/ =~ @line
      priority, severity, @msg = $1, $2, $3
      @severity = SEVERITY_MAP[severity]
      @priority = priority.to_i
    end
  end

  def log_add(severity, msg, progname = nil, &block)
    log(:add, severity, msg, progname, &block)
  end

  def log(msg_id, *arg, &block)
    Log.new(log_raw(msg_id, *arg, &block))
  end

  def log_raw(msg_id, *arg, &block)
    assert_equal true, @logger.__send__(msg_id, *arg, &block)
    msg = MockSyslog.line
    MockSyslog.reset
    return msg
  end

  def test_unknown_eh
    @logger.level = Logger::UNKNOWN
    assert_equal true, @logger.unknown?

    @logger.level = Logger::UNKNOWN + 1
    assert_equal false, @logger.unknown?
  end

  def test_facility
    assert_equal facility, @logger.facility
  end

  def test_priority
    msg = log_add nil,           'unknown level message' # nil == unknown
    assert_equal facility|Syslog::LOG_ALERT,   msg.priority

    msg = log_add Logger::FATAL, 'fatal level message'
    assert_equal facility|Syslog::LOG_ERR,     msg.priority

    msg = log_add Logger::ERROR, 'error level message'
    assert_equal facility|Syslog::LOG_WARNING, msg.priority

    msg = log_add Logger::WARN,  'warn level message'
    assert_equal facility|Syslog::LOG_NOTICE,  msg.priority

    msg = log_add Logger::INFO,  'info level message'
    assert_equal facility|Syslog::LOG_INFO,    msg.priority

    msg = log_add Logger::DEBUG, 'debug level message'
    assert_equal facility|Syslog::LOG_DEBUG,   msg.priority
  end

end if defined?(Syslog)


# Create test class for each available facility

Syslog::Facility.constants.each do |facility_symb|

  test_syslog_class = Class.new(TestSyslogLogger) do

    @facility = Syslog.const_get(facility_symb)

    def setup
      super
      @logger.facility = facility
    end

  end
  Object.const_set("TestSyslogLogger_#{facility_symb}", test_syslog_class)

end if defined?(Syslog)
