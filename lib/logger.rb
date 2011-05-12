# logger.rb - simple logging utility
# Copyright (C) 2000-2003, 2005, 2008, 2011  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.
#
# Documentation:: NAKAMURA, Hiroshi and Gavin Sinclair
# License::
#   You can redistribute it and/or modify it under the same terms of Ruby's
#   license; either the dual license version in 2003, or any later version.
# Revision:: $Id$
#
# See Logger for documentation.


require 'monitor'


# == Description
#
# The Logger class provides a simple but sophisticated logging utility that
# anyone can use because it's included in the Ruby 1.8.x standard library.
#
# The HOWTOs below give a code-based overview of Logger's usage, but the basic
# concept is as follows.  You create a Logger object (output to a file or
# elsewhere), and use it to log messages.  The messages will have varying
# levels (+info+, +error+, etc), reflecting their varying importance.  The
# levels, and their meanings, are:
#
# +FATAL+:: an unhandleable error that results in a program crash
# +ERROR+:: a handleable error condition
# +WARN+::  a warning
# +INFO+::  generic (useful) information about system operation
# +DEBUG+:: low-level information for developers
#
# So each message has a level, and the Logger itself has a level, which acts
# as a filter, so you can control the amount of information emitted from the
# logger without having to remove actual messages.
#
# For instance, in a production system, you may have your logger(s) set to
# +INFO+ (or +WARN+ if you don't want the log files growing large with
# repetitive information).  When you are developing it, though, you probably
# want to know about the program's internal state, and would set them to
# +DEBUG+.
#
# **Note**: Logger does not escape or sanitize any messages passed to it.
# Developers should be aware of when potentially malicious data (user-input)
# is passed to Logger, and manually escape the untrusted data:
#
#   logger.info("User-input: #{input.dump}")
#   logger.info("User-input: %p" % input)
#
# You can use Logger#formatter= for escaping all data.
#
#   original_formatter = Logger::Formatter.new
#   logger.formatter = proc { |severity, datetime, progname, msg|
#     original_formatter.call(severity, datetime, progname, msg.dump)
#   }
#   logger.info(input)
#
# === Example
#
# A simple example demonstrates the above explanation:
#
#   log = Logger.new(STDOUT)
#   log.level = Logger::WARN
#
#   log.debug("Created logger")
#   log.info("Program started")
#   log.warn("Nothing to do!")
#
#   begin
#     File.each_line(path) do |line|
#       unless line =~ /^(\w+) = (.*)$/
#         log.error("Line in wrong format: #{line}")
#       end
#     end
#   rescue => err
#     log.fatal("Caught exception; exiting")
#     log.fatal(err)
#   end
#
# Because the Logger's level is set to +WARN+, only the warning, error, and
# fatal messages are recorded.  The debug and info messages are silently
# discarded.
#
# === Features
#
# There are several interesting features that Logger provides, like
# auto-rolling of log files, setting the format of log messages, and
# specifying a program name in conjunction with the message.  The next section
# shows you how to achieve these things.
#
#
# == HOWTOs
#
# === How to create a logger
#
# The options below give you various choices, in more or less increasing
# complexity.
#
# 1. Create a logger which logs messages to STDERR/STDOUT.
#
#      logger = Logger.new(STDERR)
#      logger = Logger.new(STDOUT)
#
# 2. Create a logger for the file which has the specified name.
#
#      logger = Logger.new('logfile.log')
#
# 3. Create a logger for the specified file.
#
#      file = File.open('foo.log', File::WRONLY | File::APPEND)
#      # To create new (and to remove old) logfile, add File::CREAT like;
#      #   file = open('foo.log', File::WRONLY | File::APPEND | File::CREAT)
#      logger = Logger.new(file)
#
# 4. Create a logger which ages logfile once it reaches a certain size.  Leave
#    10 "old log files" and each file is about 1,024,000 bytes.
#
#      logger = Logger.new('foo.log', 10, 1024000)
#
# 5. Create a logger which ages logfile daily/weekly/monthly.
#
#      logger = Logger.new('foo.log', 'daily')
#      logger = Logger.new('foo.log', 'weekly')
#      logger = Logger.new('foo.log', 'monthly')
#
# === How to log a message
#
# Notice the different methods (+fatal+, +error+, +info+) being used to log
# messages of various levels.  Other methods in this family are +warn+ and
# +debug+.  +add+ is used below to log a message of an arbitrary (perhaps
# dynamic) level.
#
# 1. Message in block.
#
#      logger.fatal { "Argument 'foo' not given." }
#
# 2. Message as a string.
#
#      logger.error "Argument #{ @foo } mismatch."
#
# 3. With progname.
#
#      logger.info('initialize') { "Initializing..." }
#
# 4. With severity.
#
#      logger.add(Logger::FATAL) { 'Fatal error!' }
#
# === How to close a logger
#
#      logger.close
#
# === Setting severity threshold
#
# 1. Original interface.
#
#      logger.sev_threshold = Logger::WARN
#
# 2. Log4r (somewhat) compatible interface.
#
#      logger.level = Logger::INFO
#
#      DEBUG < INFO < WARN < ERROR < FATAL < UNKNOWN
#
#
# == Format
#
# Log messages are rendered in the output stream in a certain format by
# default.  The default format and a sample are shown below:
#
# Log format:
#   SeverityID, [Date Time mSec #pid] SeverityLabel -- ProgName: message
#
# Log sample:
#   I, [Wed Mar 03 02:34:24 JST 1999 895701 #19074]  INFO -- Main: info.
#
# You may change the date and time format in this manner:
#
#   logger.datetime_format = "%Y-%m-%d %H:%M:%S"
#         # e.g. "2004-01-03 00:54:26"
#
# You may change the overall format with Logger#formatter= method.
#
#   logger.formatter = proc { |severity, datetime, progname, msg|
#     "#{datetime}: #{msg}\n"
#   }
#         # e.g. "Thu Sep 22 08:51:08 GMT+9:00 2005: hello world"
#


class Logger
  VERSION = "1.2.7"
  _, name, rev = %w$Id$
  if name
    name = name.chomp(",v")
  else
    name = File.basename(__FILE__)
  end
  rev ||= "v#{VERSION}"
  ProgName = "#{name}/#{rev}"

  class Error < RuntimeError; end
  class ShiftingError < Error; end # not used after 1.2.7. just for compat.

  # Logging severity.
  module Severity
    DEBUG = 0
    INFO = 1
    WARN = 2
    ERROR = 3
    FATAL = 4
    UNKNOWN = 5
  end
  include Severity

  # Logging severity threshold (e.g. <tt>Logger::INFO</tt>).
  attr_accessor :level

  # Logging program name.
  attr_accessor :progname

  # Logging date-time format (string passed to +strftime+).
  def datetime_format=(datetime_format)
    @default_formatter.datetime_format = datetime_format
  end

  # Returns the date format (string passed to +strftime+) being used (it's set using datetime_format=)
  def datetime_format
    @default_formatter.datetime_format
  end

  # Logging formatter.  formatter#call is invoked with 4 arguments; severity,
  # time, progname and msg for each log.  Bear in mind that time is a Time and
  # msg is an Object that user passed and it could not be a String.  It is
  # expected to return a logdev#write-able Object.  Default formatter is used
  # when no formatter is set.
  attr_accessor :formatter

  alias sev_threshold level
  alias sev_threshold= level=

  # Returns +true+ iff the current severity level allows for the printing of
  # +DEBUG+ messages.
  def debug?; @level <= DEBUG; end

  # Returns +true+ iff the current severity level allows for the printing of
  # +INFO+ messages.
  def info?; @level <= INFO; end

  # Returns +true+ iff the current severity level allows for the printing of
  # +WARN+ messages.
  def warn?; @level <= WARN; end

  # Returns +true+ iff the current severity level allows for the printing of
  # +ERROR+ messages.
  def error?; @level <= ERROR; end

  # Returns +true+ iff the current severity level allows for the printing of
  # +FATAL+ messages.
  def fatal?; @level <= FATAL; end

  #
  # === Synopsis
  #
  #   Logger.new(name, shift_age = 7, shift_size = 1048576)
  #   Logger.new(name, shift_age = 'weekly')
  #
  # === Args
  #
  # +logdev+::
  #   The log device.  This is a filename (String) or IO object (typically
  #   +STDOUT+, +STDERR+, or an open file).
  # +shift_age+::
  #   Number of old log files to keep, *or* frequency of rotation (+daily+,
  #   +weekly+ or +monthly+).
  # +shift_size+::
  #   Maximum logfile size (only applies when +shift_age+ is a number).
  #
  # === Description
  #
  # Create an instance.
  #
  def initialize(logdev, shift_age = 0, shift_size = 1048576)
    @progname = nil
    @level = DEBUG
    @default_formatter = Formatter.new
    @formatter = nil
    @logdev = nil
    if logdev
      @logdev = LogDevice.new(logdev, :shift_age => shift_age,
        :shift_size => shift_size)
    end
  end

  #
  # === Synopsis
  #
  #   Logger#add(severity, message = nil, progname = nil) { ... }
  #
  # === Args
  #
  # +severity+::
  #   Severity.  Constants are defined in Logger namespace: +DEBUG+, +INFO+,
  #   +WARN+, +ERROR+, +FATAL+, or +UNKNOWN+.
  # +message+::
  #   The log message.  A String or Exception.
  # +progname+::
  #   Program name string.  Can be omitted.  Treated as a message if no +message+ and
  #   +block+ are given.
  # +block+::
  #   Can be omitted.  Called to get a message string if +message+ is nil.
  #
  # === Return
  #
  # +true+ if successful, +false+ otherwise.
  #
  # When the given severity is not high enough (for this particular logger), log
  # no message, and return +true+.
  #
  # === Description
  #
  # Log a message if the given severity is high enough.  This is the generic
  # logging method.  Users will be more inclined to use #debug, #info, #warn,
  # #error, and #fatal.
  #
  # <b>Message format</b>: +message+ can be any object, but it has to be
  # converted to a String in order to log it.  Generally, +inspect+ is used
  # if the given object is not a String.
  # A special case is an +Exception+ object, which will be printed in detail,
  # including message, class, and backtrace.  See #msg2str for the
  # implementation if required.
  #
  # === Bugs
  #
  # * Logfile is not locked.
  # * Append open does not need to lock file.
  # * But on the OS which supports multi I/O, records possibly be mixed.
  #
  def add(severity, message = nil, progname = nil, &block)
    severity ||= UNKNOWN
    if @logdev.nil? or severity < @level
      return true
    end
    progname ||= @progname
    if message.nil?
      if block_given?
        message = yield
      else
        message = progname
        progname = @progname
      end
    end
    @logdev.write(
      format_message(format_severity(severity), Time.now, progname, message))
    true
  end
  alias log add

  #
  # Dump given message to the log device without any formatting.  If no log
  # device exists, return +nil+.
  #
  def <<(msg)
    unless @logdev.nil?
      @logdev.write(msg)
    end
  end

  #
  # Log a +DEBUG+ message.
  #
  # See #info for more information.
  #
  def debug(progname = nil, &block)
    add(DEBUG, nil, progname, &block)
  end

  #
  # Log an +INFO+ message.
  #
  # The message can come either from the +progname+ argument or the +block+.  If
  # both are provided, then the +block+ is used as the message, and +progname+
  # is used as the program name.
  #
  # === Examples
  #
  #   logger.info("MainApp") { "Received connection from #{ip}" }
  #   # ...
  #   logger.info "Waiting for input from user"
  #   # ...
  #   logger.info { "User typed #{input}" }
  #
  # You'll probably stick to the second form above, unless you want to provide a
  # program name (which you can do with <tt>Logger#progname=</tt> as well).
  #
  # === Return
  #
  # See #add.
  #
  def info(progname = nil, &block)
    add(INFO, nil, progname, &block)
  end

  #
  # Log a +WARN+ message.
  #
  # See #info for more information.
  #
  def warn(progname = nil, &block)
    add(WARN, nil, progname, &block)
  end

  #
  # Log an +ERROR+ message.
  #
  # See #info for more information.
  #
  def error(progname = nil, &block)
    add(ERROR, nil, progname, &block)
  end

  #
  # Log a +FATAL+ message.
  #
  # See #info for more information.
  #
  def fatal(progname = nil, &block)
    add(FATAL, nil, progname, &block)
  end

  #
  # Log an +UNKNOWN+ message.  This will be printed no matter what the logger
  # level.
  #
  # See #info for more information.
  #
  def unknown(progname = nil, &block)
    add(UNKNOWN, nil, progname, &block)
  end

  #
  # Close the logging device.
  #
  def close
    @logdev.close if @logdev
  end

private

  # Severity label for logging. (max 5 char)
  SEV_LABEL = %w(DEBUG INFO WARN ERROR FATAL ANY)

  def format_severity(severity)
    SEV_LABEL[severity] || 'ANY'
  end

  def format_message(severity, datetime, progname, msg)
    (@formatter || @default_formatter).call(severity, datetime, progname, msg)
  end


  class Formatter
    Format = "%s, [%s#%d] %5s -- %s: %s\n"

    attr_accessor :datetime_format

    def initialize
      @datetime_format = nil
    end

    def call(severity, time, progname, msg)
      Format % [severity[0..0], format_datetime(time), $$, severity, progname,
        msg2str(msg)]
    end

  private

    def format_datetime(time)
      if @datetime_format.nil?
        time.strftime("%Y-%m-%dT%H:%M:%S.") << "%06d " % time.usec
      else
        time.strftime(@datetime_format)
      end
    end

    def msg2str(msg)
      case msg
      when ::String
        msg
      when ::Exception
        "#{ msg.message } (#{ msg.class })\n" <<
          (msg.backtrace || []).join("\n")
      else
        msg.inspect
      end
    end
  end


  class LogDevice
    attr_reader :dev
    attr_reader :filename

    class LogDeviceMutex
      include MonitorMixin
    end

    def initialize(log = nil, opt = {})
      @dev = @filename = @shift_age = @shift_size = nil
      @mutex = LogDeviceMutex.new
      if log.respond_to?(:write) and log.respond_to?(:close)
        @dev = log
      else
        @dev = open_logfile(log)
        @dev.sync = true
        @filename = log
        @shift_age = opt[:shift_age] || 7
        @shift_size = opt[:shift_size] || 1048576
      end
    end

    def write(message)
      begin
        @mutex.synchronize do
          if @shift_age and @dev.respond_to?(:stat)
            begin
              check_shift_log
            rescue
              warn("log shifting failed. #{$!}")
            end
          end
          begin
            @dev.write(message)
          rescue
            warn("log writing failed. #{$!}")
          end
        end
      rescue Exception => ignored
        warn("log writing failed. #{ignored}")
      end
    end

    def close
      begin
        @mutex.synchronize do
          @dev.close rescue nil
        end
      rescue Exception
        @dev.close rescue nil
      end
    end

  private

    def open_logfile(filename)
      if (FileTest.exist?(filename))
        open(filename, (File::WRONLY | File::APPEND))
      else
        create_logfile(filename)
      end
    end

    def create_logfile(filename)
      logdev = open(filename, (File::WRONLY | File::APPEND | File::CREAT))
      logdev.sync = true
      add_log_header(logdev)
      logdev
    end

    def add_log_header(file)
      file.write(
        "# Logfile created on %s by %s\n" % [Time.now.to_s, Logger::ProgName]
      )
    end

    SiD = 24 * 60 * 60

    def check_shift_log
      if @shift_age.is_a?(Integer)
        # Note: always returns false if '0'.
        if @filename && (@shift_age > 0) && (@dev.stat.size > @shift_size)
          shift_log_age
        end
      else
        now = Time.now
        period_end = previous_period_end(now)
        if @dev.stat.mtime <= period_end
          shift_log_period(period_end)
        end
      end
    end

    def shift_log_age
      (@shift_age-3).downto(0) do |i|
        if FileTest.exist?("#{@filename}.#{i}")
          File.rename("#{@filename}.#{i}", "#{@filename}.#{i+1}")
        end
      end
      @dev.close rescue nil
      File.rename("#{@filename}", "#{@filename}.0")
      @dev = create_logfile(@filename)
      return true
    end

    def shift_log_period(period_end)
      postfix = period_end.strftime("%Y%m%d") # YYYYMMDD
      age_file = "#{@filename}.#{postfix}"
      if FileTest.exist?(age_file)
        # try to avoid filename crash caused by Timestamp change.
        idx = 0
        # .99 can be overridden; avoid too much file search with 'loop do'
        while idx < 100
          idx += 1
          age_file = "#{@filename}.#{postfix}.#{idx}"
          break unless FileTest.exist?(age_file)
        end
      end
      @dev.close rescue nil
      File.rename("#{@filename}", age_file)
      @dev = create_logfile(@filename)
      return true
    end

    def previous_period_end(now)
      case @shift_age
      when /^daily$/
        eod(now - 1 * SiD)
      when /^weekly$/
        eod(now - ((now.wday + 1) * SiD))
      when /^monthly$/
        eod(now - now.mday * SiD)
      else
        now
      end
    end

    def eod(t)
      Time.mktime(t.year, t.month, t.mday, 23, 59, 59)
    end
  end


  #
  # == Description
  #
  # Application -- Add logging support to your application.
  #
  # == Usage
  #
  # 1. Define your application class as a sub-class of this class.
  # 2. Override 'run' method in your class to do many things.
  # 3. Instantiate it and invoke 'start'.
  #
  # == Example
  #
  #   class FooApp < Application
  #     def initialize(foo_app, application_specific, arguments)
  #       super('FooApp') # Name of the application.
  #     end
  #
  #     def run
  #       ...
  #       log(WARN, 'warning', 'my_method1')
  #       ...
  #       @log.error('my_method2') { 'Error!' }
  #       ...
  #     end
  #   end
  #
  #   status = FooApp.new(....).start
  #
  class Application
    include Logger::Severity

    # Name of the application given at initialize.
    attr_reader :appname

    #
    # == Synopsis
    #
    #   Application.new(appname = '')
    #
    # == Args
    #
    # +appname+:: Name of the application.
    #
    # == Description
    #
    # Create an instance.  Log device is +STDERR+ by default.  This can be
    # changed with #set_log.
    #
    def initialize(appname = nil)
      @appname = appname
      @log = Logger.new(STDERR)
      @log.progname = @appname
      @level = @log.level
    end

    #
    # Start the application.  Return the status code.
    #
    def start
      status = -1
      begin
        log(INFO, "Start of #{ @appname }.")
        status = run
      rescue
        log(FATAL, "Detected an exception. Stopping ... #{$!} (#{$!.class})\n" << $@.join("\n"))
      ensure
        log(INFO, "End of #{ @appname }. (status: #{ status.to_s })")
      end
      status
    end

    # Logger for this application.  See the class Logger for an explanation.
    def logger
      @log
    end

    #
    # Sets the logger for this application.  See the class Logger for an explanation.
    #
    def logger=(logger)
      @log = logger
      @log.progname = @appname
      @log.level = @level
    end

    #
    # Sets the log device for this application.  See <tt>Logger.new</tt> for an explanation
    # of the arguments.
    #
    def set_log(logdev, shift_age = 0, shift_size = 1024000)
      @log = Logger.new(logdev, shift_age, shift_size)
      @log.progname = @appname
      @log.level = @level
    end

    def log=(logdev)
      set_log(logdev)
    end

    #
    # Set the logging threshold, just like <tt>Logger#level=</tt>.
    #
    def level=(level)
      @level = level
      @log.level = @level
    end

    #
    # See Logger#add.  This application's +appname+ is used.
    #
    def log(severity, message = nil, &block)
      @log.add(severity, message, @appname, &block) if @log
    end

  private

    def run
      # TODO: should be an NotImplementedError
      raise RuntimeError.new('Method run must be defined in the derived class.')
    end
  end
end
