# frozen_string_literal: false
# logger.rb - simple logging utility
# Copyright (C) 2000-2003, 2005, 2008, 2011  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.
#
# Documentation:: NAKAMURA, Hiroshi and Gavin Sinclair
# License::
#   You can redistribute it and/or modify it under the same terms of Ruby's
#   license; either the dual license version in 2003, or any later version.
# Revision:: $Id$
#
# A simple system for logging messages.  See Logger for more documentation.

require 'monitor'

# == Description
#
# The Logger class provides a simple but sophisticated logging utility that
# you can use to output messages.
#
# The messages have associated levels, such as +INFO+ or +ERROR+ that indicate
# their importance.  You can then give the Logger a level, and only messages
# at that level or higher will be printed.
#
# The levels are:
#
# +UNKNOWN+:: An unknown message that should always be logged.
# +FATAL+:: An unhandleable error that results in a program crash.
# +ERROR+:: A handleable error condition.
# +WARN+::  A warning.
# +INFO+::  Generic (useful) information about system operation.
# +DEBUG+:: Low-level information for developers.
#
# For instance, in a production system, you may have your Logger set to
# +INFO+ or even +WARN+.
# When you are developing the system, however, you probably
# want to know about the program's internal state, and would set the Logger to
# +DEBUG+.
#
# *Note*: Logger does not escape or sanitize any messages passed to it.
# Developers should be aware of when potentially malicious data (user-input)
# is passed to Logger, and manually escape the untrusted data:
#
#   logger.info("User-input: #{input.dump}")
#   logger.info("User-input: %p" % input)
#
# You can use #formatter= for escaping all data.
#
#   original_formatter = Logger::Formatter.new
#   logger.formatter = proc { |severity, datetime, progname, msg|
#     original_formatter.call(severity, datetime, progname, msg.dump)
#   }
#   logger.info(input)
#
# === Example
#
# This creates a Logger that outputs to the standard output stream, with a
# level of +WARN+:
#
#   require 'logger'
#
#   logger = Logger.new(STDOUT)
#   logger.level = Logger::WARN
#
#   logger.debug("Created logger")
#   logger.info("Program started")
#   logger.warn("Nothing to do!")
#
#   path = "a_non_existent_file"
#
#   begin
#     File.foreach(path) do |line|
#       unless line =~ /^(\w+) = (.*)$/
#         logger.error("Line in wrong format: #{line.chomp}")
#       end
#     end
#   rescue => err
#     logger.fatal("Caught exception; exiting")
#     logger.fatal(err)
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
#      # To create new (and to remove old) logfile, add File::CREAT like:
#      # file = File.open('foo.log', File::WRONLY | File::APPEND | File::CREAT)
#      logger = Logger.new(file)
#
# 4. Create a logger which ages the logfile once it reaches a certain size.
#    Leave 10 "old" log files where each file is about 1,024,000 bytes.
#
#      logger = Logger.new('foo.log', 10, 1024000)
#
# 5. Create a logger which ages the logfile daily/weekly/monthly.
#
#      logger = Logger.new('foo.log', 'daily')
#      logger = Logger.new('foo.log', 'weekly')
#      logger = Logger.new('foo.log', 'monthly')
#
# === How to log a message
#
# Notice the different methods (+fatal+, +error+, +info+) being used to log
# messages of various levels?  Other methods in this family are +warn+ and
# +debug+.  +add+ is used below to log a message of an arbitrary (perhaps
# dynamic) level.
#
# 1. Message in a block.
#
#      logger.fatal { "Argument 'foo' not given." }
#
# 2. Message as a string.
#
#      logger.error "Argument #{@foo} mismatch."
#
# 3. With progname.
#
#      logger.info('initialize') { "Initializing..." }
#
# 4. With severity.
#
#      logger.add(Logger::FATAL) { 'Fatal error!' }
#
# The block form allows you to create potentially complex log messages,
# but to delay their evaluation until and unless the message is
# logged.  For example, if we have the following:
#
#     logger.debug { "This is a " + potentially + " expensive operation" }
#
# If the logger's level is +INFO+ or higher, no debug messages will be logged,
# and the entire block will not even be evaluated.  Compare to this:
#
#     logger.debug("This is a " + potentially + " expensive operation")
#
# Here, the string concatenation is done every time, even if the log
# level is not set to show the debug message.
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
#      # DEBUG < INFO < WARN < ERROR < FATAL < UNKNOWN
#
# 3. Symbol or String (case insensitive)
#
#      logger.level = :info
#      logger.level = 'INFO'
#
#      # :debug < :info < :warn < :error < :fatal < :unknown
#
# 4. Constructor
#
#      Logger.new(logdev, level: Logger::INFO)
#      Logger.new(logdev, level: :info)
#      Logger.new(logdev, level: 'INFO')
#
# == Format
#
# Log messages are rendered in the output stream in a certain format by
# default.  The default format and a sample are shown below:
#
# Log format:
#   SeverityID, [DateTime #pid] SeverityLabel -- ProgName: message
#
# Log sample:
#   I, [1999-03-03T02:34:24.895701 #19074]  INFO -- Main: info.
#
# You may change the date and time format via #datetime_format=.
#
#   logger.datetime_format = '%Y-%m-%d %H:%M:%S'
#         # e.g. "2004-01-03 00:54:26"
#
# or via the constructor.
#
#   Logger.new(logdev, datetime_format: '%Y-%m-%d %H:%M:%S')
#
# Or, you may change the overall format via the #formatter= method.
#
#   logger.formatter = proc do |severity, datetime, progname, msg|
#     "#{datetime}: #{msg}\n"
#   end
#   # e.g. "2005-09-22 08:51:08 +0900: hello world"
#
# or via the constructor.
#
#   Logger.new(logdev, formatter: proc {|severity, datetime, progname, msg|
#     "#{datetime}: #{msg}\n"
#   })
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
  ProgName = "#{name}/#{rev}".freeze

  class Error < RuntimeError # :nodoc:
  end
  # not used after 1.2.7. just for compat.
  class ShiftingError < Error # :nodoc:
  end

  # Logging severity.
  module Severity
    # Low-level information, mostly for developers.
    DEBUG = 0
    # Generic (useful) information about system operation.
    INFO = 1
    # A warning.
    WARN = 2
    # A handleable error condition.
    ERROR = 3
    # An unhandleable error that results in a program crash.
    FATAL = 4
    # An unknown message that should always be logged.
    UNKNOWN = 5
  end
  include Severity

  # Logging severity threshold (e.g. <tt>Logger::INFO</tt>).
  attr_reader :level

  # Set logging severity threshold.
  #
  # +severity+:: The Severity of the log message.
  def level=(severity)
    if severity.is_a?(Integer)
      @level = severity
    else
      case severity.to_s.downcase
      when 'debug'.freeze
        @level = DEBUG
      when 'info'.freeze
        @level = INFO
      when 'warn'.freeze
        @level = WARN
      when 'error'.freeze
        @level = ERROR
      when 'fatal'.freeze
        @level = FATAL
      when 'unknown'.freeze
        @level = UNKNOWN
      else
        raise ArgumentError, "invalid log level: #{severity}"
      end
    end
  end

  # Program name to include in log messages.
  attr_accessor :progname

  # Set date-time format.
  #
  # +datetime_format+:: A string suitable for passing to +strftime+.
  def datetime_format=(datetime_format)
    @default_formatter.datetime_format = datetime_format
  end

  # Returns the date format being used.  See #datetime_format=
  def datetime_format
    @default_formatter.datetime_format
  end

  # Logging formatter, as a +Proc+ that will take four arguments and
  # return the formatted message. The arguments are:
  #
  # +severity+:: The Severity of the log message.
  # +time+:: A Time instance representing when the message was logged.
  # +progname+:: The #progname configured, or passed to the logger method.
  # +msg+:: The _Object_ the user passed to the log message; not necessarily a
  #         String.
  #
  # The block should return an Object that can be written to the logging
  # device via +write+.  The default formatter is used when no formatter is
  # set.
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
  # :call-seq:
  #   Logger.new(logdev, shift_age = 0, shift_size = 1048576)
  #   Logger.new(logdev, shift_age = 'weekly')
  #   Logger.new(logdev, level: :info)
  #   Logger.new(logdev, progname: 'progname')
  #   Logger.new(logdev, formatter: formatter)
  #   Logger.new(logdev, datetime_format: '%Y-%m-%d %H:%M:%S')
  #
  # === Args
  #
  # +logdev+::
  #   The log device.  This is a filename (String) or IO object (typically
  #   +STDOUT+, +STDERR+, or an open file).
  # +shift_age+::
  #   Number of old log files to keep, *or* frequency of rotation (+daily+,
  #   +weekly+ or +monthly+). Default value is 0.
  # +shift_size+::
  #   Maximum logfile size in bytes (only applies when +shift_age+ is a number).
  #   Defaults to +1048576+ (1MB).
  # +level+::
  #   Logging severity threshold. Default values is Logger::DEBUG.
  # +progname+::
  #   Program name to include in log messages. Default value is nil.
  # +formatter+::
  #   Logging formatter. Default values is an instance of Logger::Formatter.
  # +datetime_format+::
  #   Date and time format. Default value is '%Y-%m-%d %H:%M:%S'.
  # +shift_period_suffix+::
  #   The log file suffix format for +daily+, +weekly+ or +monthly+ rotation.
  #   Default is '%Y%m%d'.
  #
  # === Description
  #
  # Create an instance.
  #
  def initialize(logdev, shift_age = 0, shift_size = 1048576, level: DEBUG,
                 progname: nil, formatter: nil, datetime_format: nil,
                 shift_period_suffix: '%Y%m%d')
    self.level = level
    self.progname = progname
    @default_formatter = Formatter.new
    self.datetime_format = datetime_format
    self.formatter = formatter
    @logdev = nil
    if logdev
      @logdev = LogDevice.new(logdev, :shift_age => shift_age,
        :shift_size => shift_size,
        :shift_period_suffix => shift_period_suffix)
    end
  end

  #
  # :call-seq:
  #   Logger#reopen
  #   Logger#reopen(logdev)
  #
  # === Args
  #
  # +logdev+::
  #   The log device.  This is a filename (String) or IO object (typically
  #   +STDOUT+, +STDERR+, or an open file).  reopen the same filename if
  #   it is +nil+, do nothing for IO.  Default is +nil+.
  #
  # === Description
  #
  # Reopen a log device.
  #
  def reopen(logdev = nil)
    @logdev.reopen(logdev)
    self
  end

  #
  # :call-seq:
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
  #   Program name string.  Can be omitted.  Treated as a message if no
  #   +message+ and +block+ are given.
  # +block+::
  #   Can be omitted.  Called to get a message string if +message+ is nil.
  #
  # === Return
  #
  # When the given severity is not high enough (for this particular logger),
  # log no message, and return +true+.
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
  # * If the OS supports multi I/O, records possibly may be mixed.
  #
  def add(severity, message = nil, progname = nil)
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
  # :call-seq:
  #   info(message)
  #   info(progname, &block)
  #
  # Log an +INFO+ message.
  #
  # +message+:: The message to log; does not need to be a String.
  # +progname+:: In the block form, this is the #progname to use in the
  #              log message.  The default can be set with #progname=.
  # +block+:: Evaluates to the message to log.  This is not evaluated unless
  #           the logger's level is sufficient to log the message.  This
  #           allows you to create potentially expensive logging messages that
  #           are only called when the logger is configured to show them.
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
  # program name (which you can do with #progname= as well).
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
  # Log an +UNKNOWN+ message.  This will be printed no matter what the logger's
  # level is.
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

  # Severity label for logging (max 5 chars).
  SEV_LABEL = %w(DEBUG INFO WARN ERROR FATAL ANY).each(&:freeze).freeze

  def format_severity(severity)
    SEV_LABEL[severity] || 'ANY'
  end

  def format_message(severity, datetime, progname, msg)
    (@formatter || @default_formatter).call(severity, datetime, progname, msg)
  end


  # Default formatter for log messages.
  class Formatter
    Format = "%s, [%s#%d] %5s -- %s: %s\n".freeze

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
      time.strftime(@datetime_format || "%Y-%m-%dT%H:%M:%S.%6N ".freeze)
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

  module Period
    module_function

    SiD = 24 * 60 * 60

    def next_rotate_time(now, shift_age)
      case shift_age
      when 'daily'
        t = Time.mktime(now.year, now.month, now.mday) + SiD
      when 'weekly'
        t = Time.mktime(now.year, now.month, now.mday) + SiD * (7 - now.wday)
      when 'monthly'
        t = Time.mktime(now.year, now.month, 1) + SiD * 32
        return Time.mktime(t.year, t.month, 1)
      else
        return now
      end
      if t.hour.nonzero? or t.min.nonzero? or t.sec.nonzero?
        hour = t.hour
        t = Time.mktime(t.year, t.month, t.mday)
        t += SiD if hour > 12
      end
      t
    end

    def previous_period_end(now, shift_age)
      case shift_age
      when 'daily'
        t = Time.mktime(now.year, now.month, now.mday) - SiD / 2
      when 'weekly'
        t = Time.mktime(now.year, now.month, now.mday) - (SiD * now.wday + SiD / 2)
      when 'monthly'
        t = Time.mktime(now.year, now.month, 1) - SiD / 2
      else
        return now
      end
      Time.mktime(t.year, t.month, t.mday, 23, 59, 59)
    end
  end

  # Device used for logging messages.
  class LogDevice
    include Period

    attr_reader :dev
    attr_reader :filename
    include MonitorMixin

    def initialize(log = nil, shift_age: nil, shift_size: nil, shift_period_suffix: nil)
      @dev = @filename = @shift_age = @shift_size = @shift_period_suffix = nil
      mon_initialize
      set_dev(log)
      if @filename
        @shift_age = shift_age || 7
        @shift_size = shift_size || 1048576
        @shift_period_suffix = shift_period_suffix || '%Y%m%d'

        unless @shift_age.is_a?(Integer)
          base_time = @dev.respond_to?(:stat) ? @dev.stat.mtime : Time.now
          @next_rotate_time = next_rotate_time(base_time, @shift_age)
        end
      end
    end

    def write(message)
      begin
        synchronize do
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
        synchronize do
          @dev.close rescue nil
        end
      rescue Exception
        @dev.close rescue nil
      end
    end

    def reopen(log = nil)
      # reopen the same filename if no argument, do nothing for IO
      log ||= @filename if @filename
      if log
        synchronize do
          if @filename and @dev
            @dev.close rescue nil # close only file opened by Logger
            @filename = nil
          end
          set_dev(log)
        end
      end
      self
    end

  private

    def set_dev(log)
      if log.respond_to?(:write) and log.respond_to?(:close)
        @dev = log
      else
        @dev = open_logfile(log)
        @dev.sync = true
        @filename = log
      end
    end

    def open_logfile(filename)
      begin
        open(filename, (File::WRONLY | File::APPEND))
      rescue Errno::ENOENT
        create_logfile(filename)
      end
    end

    def create_logfile(filename)
      begin
        logdev = open(filename, (File::WRONLY | File::APPEND | File::CREAT | File::EXCL))
        logdev.flock(File::LOCK_EX)
        logdev.sync = true
        add_log_header(logdev)
        logdev.flock(File::LOCK_UN)
      rescue Errno::EEXIST
        # file is created by another process
        logdev = open_logfile(filename)
        logdev.sync = true
      end
      logdev
    end

    def add_log_header(file)
      file.write(
        "# Logfile created on %s by %s\n" % [Time.now.to_s, Logger::ProgName]
      ) if file.size == 0
    end

    def check_shift_log
      if @shift_age.is_a?(Integer)
        # Note: always returns false if '0'.
        if @filename && (@shift_age > 0) && (@dev.stat.size > @shift_size)
          lock_shift_log { shift_log_age }
        end
      else
        now = Time.now
        if now >= @next_rotate_time
          @next_rotate_time = next_rotate_time(now, @shift_age)
          lock_shift_log { shift_log_period(previous_period_end(now, @shift_age)) }
        end
      end
    end

    if /mswin|mingw/ =~ RUBY_PLATFORM
      def lock_shift_log
        yield
      end
    else
      def lock_shift_log
        retry_limit = 8
        retry_sleep = 0.1
        begin
          File.open(@filename, File::WRONLY | File::APPEND) do |lock|
            lock.flock(File::LOCK_EX) # inter-process locking. will be unlocked at closing file
            if File.identical?(@filename, lock) and File.identical?(lock, @dev)
              yield # log shifting
            else
              # log shifted by another process (i-node before locking and i-node after locking are different)
              @dev.close rescue nil
              @dev = open_logfile(@filename)
              @dev.sync = true
            end
          end
        rescue Errno::ENOENT
          # @filename file would not exist right after #rename and before #create_logfile
          if retry_limit <= 0
            warn("log rotation inter-process lock failed. #{$!}")
          else
            sleep retry_sleep
            retry_limit -= 1
            retry_sleep *= 2
            retry
          end
        end
      rescue
        warn("log rotation inter-process lock failed. #{$!}")
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
      suffix = period_end.strftime(@shift_period_suffix)
      age_file = "#{@filename}.#{suffix}"
      if FileTest.exist?(age_file)
        # try to avoid filename crash caused by Timestamp change.
        idx = 0
        # .99 can be overridden; avoid too much file search with 'loop do'
        while idx < 100
          idx += 1
          age_file = "#{@filename}.#{suffix}.#{idx}"
          break unless FileTest.exist?(age_file)
        end
      end
      @dev.close rescue nil
      File.rename("#{@filename}", age_file)
      @dev = create_logfile(@filename)
      return true
    end
  end
end
