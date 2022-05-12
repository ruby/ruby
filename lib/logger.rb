# frozen_string_literal: true
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
require 'rbconfig'

require_relative 'logger/version'
require_relative 'logger/formatter'
require_relative 'logger/log_device'
require_relative 'logger/severity'
require_relative 'logger/errors'

# \Class \Logger provides a simple but sophisticated logging utility that
# you can use to create one or more
# {event logs}[https://en.wikipedia.org/wiki/Logging_(software)#Event_logs]
# for your program.
# Each such log contains a chronological sequence of entries
# that provides a record of the program's activities.
#
# == About the Examples
#
# All examples on this page assume that \Logger has been required:
#
#   require 'logger'
#
# == Synopsis
#
# Create a log with Logger.new:
#
#   # Single log file.
#   logger = Logger.new('t.log')
#   # Size-based rotated log: 3 10-megabyte files.
#   logger = Logger.new('t.log', 3, 10485760)
#   # Period-based rotated log: daily (also allowed: 'weekly', 'monthly').
#   logger = Logger.new('t.log', 'daily')
#
# Add entries (level, message) with Logger#add:
#
#   logger.add(Logger::DEBUG, 'Maximal debugging info')
#   logger.add(Logger::INFO, 'Non-error information')
#   logger.add(Logger::WARN, 'Non-error warning')
#   logger.add(Logger::ERROR, 'Non-fatal error')
#   logger.add(Logger::FATAL, 'Fatal error')
#   logger.add(Logger::UNKNOWN, 'Most severe')
#
# There are also these shorthand methods:
#
#   logger.debug('Maximal debugging info')
#   logger.info('Non-error information')
#   logger.warn('Non-error warning')
#   logger.error('Non-fatal error')
#   logger.fatal('Fatal error')
#   logger.unknown('Most severe')
#
# For each method in the two groups immediately above,
# you can omit the string message and provide a block instead.
# Doing so can have two benefits:
#
# - Context: the block can evaluate the entire program context
#   and create a context-dependent message.
# - Performance: the block is not evaluated unless the log level
#   permits the entry actually to be written:
#
#     logger.error { my_slow_message_generator }
#
#   Contrast this with the string form, where the string is
#   always evaluated, regardless of the log level:
#
#     logger.error("#{my_slow_message_generator}")
#
# Close the log with Logger#close:
#
#   logger.close
#
# == Log Stream
#
# When you create a \Logger instance, you specify an IO stream
# for the logger's output, usually either an open File object
# or an IO object such as <tt>$stdout</tt> or <tt>$stderr</tt>.
#
# == Entries
#
# When you call instance method #add (or its alias #log),
# an entry may (or may not) be written to the log;
# see {Log Level}[rdoc-ref:Logger@Log+Level]
#
# An entry always has:
#
# - A severity (the required argument to #add).
# - An automatically created timestamp.
#
# And may also have:
#
# - A message.
# - A program name.
#
# Example:
#
#   logger = Logger.new($stdout)
#   logger.add(Logger::INFO, 'msg', 'progname')
#   # => I, [2022-05-07T17:21:46.536234 #20536]  INFO -- progname: msg
#
# The default format for an entry is:
#
#   "%s, [%s #%d] %5s -- %s: %s\n"
#
# where the values to be formatted are:
#
# - \Severity (one letter).
# - Timestamp.
# - Timezone.
# - \Severity (word).
# - Program name.
# - Message.
#
# You can use a different entry format by:
#
# - Calling #add with a block (affects only the one entry).
# - Setting a format proc with method
#   {formatter=}[Logger.html#attribute-i-formatter]
#   (affects following entries).
#
# === \Severity
#
# The severity of a log entry, which is specified in the call to #add,
# does two things:
#
# - Determines whether the entry is selected for inclusion in the log;
#   see {Log Level}[rdoc-ref:Logger@Log+Level].
# - Indicates to any log reader (whether a person or a program)
#   the relative importance of the entry.
#
# === Timestamp
#
# The timestamp for a log entry is generated automatically
# when the entry is created (by a call to #add).
#
# The logged timestamp is formatted by method
# {Time#strftime}[https://docs.ruby-lang.org/en/master/Time.html#method-i-strftime]
# using this format string:
#
#   '%Y-%m-%dT%H:%M:%S.%6N'
#
# Example:
#
#   logger = Logger.new($stdout)
#   logger.add(Logger::INFO)
#   # => I, [2022-05-07T17:04:32.318331 #20536]  INFO -- : nil
#
# You can set a different format using method #datetime_format=.
#
# === Message
#
# The message is an optional argument to method #add:
#
#   logger = Logger.new($stdout)
#   logger.add(Logger::INFO, 'My message')
#   # => I, [2022-05-07T18:15:37.647581 #20536]  INFO -- : My message
#
# The message object may be a string, or an object that can be converted
# to a string.
#
# *Note*: \Logger does not escape or sanitize any messages passed to it.
# Developers should be aware that malicious data (user input)
# may be passed to \Logger, and should explicitly escape untrusted data.
#
# You can use a custom formatter to escape message data;
# this formatter uses
# {String#dump}[https://ruby-doc.org/core-3.1.2/String.html#method-i-dump]
# to escape the message string:
#
#   original_formatter = logger.formatter || Logger::Formatter.new
#   logger.formatter = proc { |sev, time, progname, msg|
#     original_formatter.call(sev, time, progname, msg.dump)
#   }
#   logger.info(input)
#
# === Program Name
#
# The program name is an optional argument to method #add:
#
#   logger = Logger.new($stdout)
#   logger.add(Logger::INFO, 'My message', 'mung')
#   # => I, [2022-05-07T18:17:38.084716 #20536]  INFO -- mung: My message
#
# The default program name for a new logger may be set in the call to
# Logger.new via optional keyword argument +progname+:
#
#   logger = Logger.new('t.log', progname: 'mung')
#
# The default program name for an existing logger may be set
# by a call to method #progname=:
#
#   logger.progname = 'mung'
#
# The current program name may be retrieved with method
# {progname}[Logger.html#attribute-i-progname]:
#
# == Log Level
#
# The log level setting determines whether an entry is actually
# written to the log, based on the entry's severity.
#
# These are the defined severities (least severe to most severe):
#
#   logger = Logger.new($stdout)
#   logger.add(Logger::DEBUG, 'Maximal debugging info')
#   # => D, [2022-05-07T17:57:41.776220 #20536] DEBUG -- : Maximal debugging info
#   logger.add(Logger::INFO, 'Non-error information')
#   # => I, [2022-05-07T17:59:14.349167 #20536]  INFO -- : Non-error information
#   logger.add(Logger::WARN, 'Non-error warning')
#   # => W, [2022-05-07T18:00:45.337538 #20536]  WARN -- : Non-error warning
#   logger.add(Logger::ERROR, 'Non-fatal error')
#   # => E, [2022-05-07T18:02:41.592912 #20536] ERROR -- : Non-fatal error
#   logger.add(Logger::FATAL, 'Fatal error')
#   # => F, [2022-05-07T18:05:24.703931 #20536] FATAL -- : Fatal error
#   logger.add(Logger::UNKNOWN, 'Most severe')
#   # => A, [2022-05-07T18:07:54.657491 #20536]   ANY -- : Most severe
#
# The default initial level setting is Logger::DEBUG, the lowest level,
# which means that all entries are to be written, regardless of severity:
#
#   logger = Logger.new($stdout)
#   logger.level # => 0
#   logger.add(0, "My message")
#   # => D, [2022-05-11T15:10:59.773668 #20536] DEBUG -- : My message
#
# You can specify a different setting in a new logger
# using keyword argument +level+ with an appropriate value:
#
#   logger = Logger.new($stdout, level: Logger::ERROR)
#   logger = Logger.new($stdout, level: 'error')
#   logger = Logger.new($stdout, level: :error)
#   logger.level # => 3
#
# With this level, entries with severity Logger::ERROR and higher
# are written, while those with lower severities are not written:
#
#   logger = Logger.new($stdout)
#   logger.add(3)
#   # =? E, [2022-05-11T15:17:20.933362 #20536] ERROR -- : nil
#   logger.add(2) # Silent.
#
# You can set the log level for an existing logger
# with method #level=:
#
#   logger.level = Logger::ERROR
#
# There are also these shorthand methods for setting the level:
#
#   logger.debug! # => 0
#   logger.info!  # => 1
#   logger.warn!  # => 2
#   logger.error! # => 3
#   logger.fatal! # => 4
#
# You can retrieve the log level with method
# {level}[Logger.html#attribute-i-level]:
#
#   logger.level = 3
#   logger.level # => 3
#
# There are also these methods for determining whether a given
# level is to be written:
#
#   logger.level = 3
#   logger.debug? # => false
#   logger.info?  # => false
#   logger.warn?  # => false
#   logger.error? # => true
#   logger.fatal? # => true
#
# == Log File Rotation
#
# By default, a log file is a single file that grows indefinitely
# (until explicitly closed); there is no file rotation.
#
# To keep log files to a manageable size,
# you can use _log_ _file_ _rotation_, which uses multiple log files:
#
# - Each log file has entries for a non-overlapping
#   time interval.
# - Only the most recent log file is open and active;
#   the others are closed and inactive.
#
# === Size-Based Rotation
#
# For size-based log file rotation, call Logger.new with:
#
# - Argument +logdev+ as a file path.
# - Argument +shift_age+ with a positive integer:
#   the number of log files to be in the rotation.
# - Argument +shift_size+ as a positive integer:
#   the maximum size (in bytes) of each log file;
#   defaults to 1048576 (1 megabyte).
#
# Examples:
#
#   logger = Logger.new('t.log', 3)           # Three 1-megabyte files.
#   logger = Logger.new('t.log', 5, 10485760) # Five 10-megabyte files.
#
# For these examples, suppose:
#
#   logger = Logger.new('t.log', 3)
#
# Logging begins in the new log file, +t.log+;
# the log file is "full" and ready for rotation
# when a new entry would cause its size to exceed +shift_size+.
#
# The first time +t.log+ is full:
#
# - +t.log+ is closed and renamed to +t.log.0+.
# - A new file +t.log+ is opened.
#
# The second time +t.log+ is full:
#
# - +t.log.0 is renamed as +t.log.1+.
# - +t.log+ is closed and renamed to +t.log.0+.
# - A new file +t.log+ is opened.
#
# Each subsequent time that +t.log+ is full,
# the log files are rotated:
#
# - +t.log.1+ is removed.
# - +t.log.0 is renamed as +t.log.1+.
# - +t.log+ is closed and renamed to +t.log.0+.
# - A new file +t.log+ is opened.
#
# === Periodic Rotation
#
# For periodic rotation, call Logger.new with:
#
# - Argument +logdev+ as a file path.
# - Argument +shift_age+ as a string period indicator.
#
# Examples:
#
#   logger = Logger.new('t.log', 'daily')   # Rotate log files daily.
#   logger = Logger.new('t.log', 'weekly')  # Rotate log files weekly.
#   logger = Logger.new('t.log', 'monthly') # Rotate log files monthly.
#
# Example:
#
#   logger = Logger.new('t.log', 'daily')
#
# When the given period expires:
#
# - The base log file, +t.log+ is closed and renamed
#   with a date-based suffix such as +t.log.20220509+.
# - A new log file +t.log+ is opened.
# - Nothing is removed.
#
# The default format for the suffix is <tt>'%Y%m%d'</tt>,
# which produces a suffix similar to the one above.
# You can set a different format using create-time option
# +shift_period_suffix+;
# see details and suggestions at
# {Time#strftime}[https://docs.ruby-lang.org/en/master/Time.html#method-i-strftime].
#
class Logger
  _, name, rev = %w$Id$
  if name
    name = name.chomp(",v")
  else
    name = File.basename(__FILE__)
  end
  rev ||= "v#{VERSION}"
  ProgName = "#{name}/#{rev}"

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
      when 'debug'
        @level = DEBUG
      when 'info'
        @level = INFO
      when 'warn'
        @level = WARN
      when 'error'
        @level = ERROR
      when 'fatal'
        @level = FATAL
      when 'unknown'
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

  # Returns +true+ if and only if the current severity level allows for the printing of
  # +DEBUG+ messages.
  def debug?; level <= DEBUG; end

  # Sets the severity to DEBUG.
  def debug!; self.level = DEBUG; end

  # Returns +true+ if and only if the current severity level allows for the printing of
  # +INFO+ messages.
  def info?; level <= INFO; end

  # Sets the severity to INFO.
  def info!; self.level = INFO; end

  # Returns +true+ if and only if the current severity level allows for the printing of
  # +WARN+ messages.
  def warn?; level <= WARN; end

  # Sets the severity to WARN.
  def warn!; self.level = WARN; end

  # Returns +true+ if and only if the current severity level allows for the printing of
  # +ERROR+ messages.
  def error?; level <= ERROR; end

  # Sets the severity to ERROR.
  def error!; self.level = ERROR; end

  # Returns +true+ if and only if the current severity level allows for the printing of
  # +FATAL+ messages.
  def fatal?; level <= FATAL; end

  # Sets the severity to FATAL.
  def fatal!; self.level = FATAL; end

  #
  # :call-seq:
  #   Logger.new(logdev, shift_age = 0, shift_size = 1048576, **options)
  #   Logger.new(logdev, shift_age = 'weekly', **options)
  #
  # With the single argument +logdev+,
  # returns a new logger with all default options:
  #
  #   Logger.new('t.log') # => #<Logger:0x000001e685dc6ac8>
  #
  # Argument +logdev+ must be one of:
  #
  # - A string filepath: entries are to be written
  #   to the file at that path.
  # - An IO stream (typically +$stdout+, +$stderr+. or an open file):
  #   entries are to be written to the given stream.
  # - +nil+ or +File::NULL+: no entries are to be written.
  #
  # === Args
  #
  # +logdev+::
  #   The log device.  This is a filename (String), IO object (typically
  #   +STDOUT+, +STDERR+, or an open file), +nil+ (it writes nothing) or
  #   +File::NULL+ (same as +nil+).
  # +shift_age+::
  #   Number of old log files to keep, *or* frequency of rotation (+daily+,
  #   +weekly+ or +monthly+). Default value is 0, which disables log file
  #   rotation.
  # +shift_size+::
  #   Maximum logfile size in bytes (only applies when +shift_age+ is a positive
  #   Integer). Defaults to +1048576+ (1MB).
  # +level+::
  #   Logging severity threshold. Default values is Logger::DEBUG.
  # +progname+::
  #   Program name to include in log messages. Default value is nil.
  # +formatter+::
  #   Logging formatter. Default values is an instance of Logger::Formatter.
  # +datetime_format+::
  #   Date and time format. Default value is '%Y-%m-%d %H:%M:%S'.
  # +binmode+::
  #   Use binary mode on the log device. Default value is false.
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
                 binmode: false, shift_period_suffix: '%Y%m%d')
    self.level = level
    self.progname = progname
    @default_formatter = Formatter.new
    self.datetime_format = datetime_format
    self.formatter = formatter
    @logdev = nil
    if logdev && logdev != File::NULL
      @logdev = LogDevice.new(logdev, shift_age: shift_age,
        shift_size: shift_size,
        shift_period_suffix: shift_period_suffix,
        binmode: binmode)
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
    @logdev&.reopen(logdev)
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
    if @logdev.nil? or severity < level
      return true
    end
    if progname.nil?
      progname = @progname
    end
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
    @logdev&.write(msg)
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
    @logdev&.close
  end

private

  # Severity label for logging (max 5 chars).
  SEV_LABEL = %w(DEBUG INFO WARN ERROR FATAL ANY).freeze

  def format_severity(severity)
    SEV_LABEL[severity] || 'ANY'
  end

  def format_message(severity, datetime, progname, msg)
    (@formatter || @default_formatter).call(severity, datetime, progname, msg)
  end
end
