#
# = logger.rb
#
# Simple logging utility.
#
# Author:: NAKAMURA, Hiroshi  <nakahiro@sarion.co.jp>
# Documentation:: NAKAMURA, Hiroshi and Gavin Sinclair
# License::
#   You can redistribute it and/or modify it under the same terms of Ruby's
#   license; either the dual license version in 2003, or any later version.
# Revision:: $Id$
#
# See Logger for documentation.
#


#
# == Description
#
# The Logger class provides a simple but sophisticated logging utility that
# anyone can use because it's included in the Ruby 1.8.x standard library.
# For more advanced logging, see the "Log4r" package on the RAA.
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
# See http://raa.ruby-lang.org/list.rhtml?name=log4r for Log4r, which contains
# many advanced features like file-based configuration, a wide range of
# logging targets, simultaneous logging, and heirachical logging.
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
#      logger.level = Logger::WARN
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
# Log messages are rendered in the output stream in a certain format.  The
# default format and a sample are shown below:
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
# There is currently no supported way to change the overall format, but you may
# have some luck hacking the Format constant.
#
class Logger
  /: (\S+),v (\S+)/ =~ %q$Id$
  ProgName = "#{$1}/#{$2}"

  class Error < RuntimeError; end
  class ShiftingError < Error; end

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
  attr_accessor :datetime_format

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
  # Create an instance.  See Logger::LogDevice.new for more information if
  # required.
  #
  def initialize(logdev, shift_age = 0, shift_size = 1048576)
    @logdev = nil
    @progname = nil
    @level = DEBUG
    @datetime_format = nil
    @logdev = nil
    if logdev
      @logdev = LogDevice.new(logdev, :shift_age => shift_age, :shift_size => shift_size)
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
      format_message(
	format_severity(severity),
	format_datetime(Time.now),
	msg2str(message),
	progname
      )
    )
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

  def format_datetime(datetime)
    if @datetime_format.nil?
      datetime.strftime("%Y-%m-%dT%H:%M:%S.") << "%06d " % datetime.usec
    else
      datetime.strftime(@datetime_format)
    end
  end

  Format = "%s, [%s#%d] %5s -- %s: %s\n"
  def format_message(severity, timestamp, msg, progname)
    Format % [severity[0..0], timestamp, $$, severity, progname, msg]
  end

  def msg2str(msg)
    case msg
    when ::String
      msg
    when ::Exception
      "#{ msg.message } (#{ msg.class })\n" << (msg.backtrace || []).join("\n")
    else
      msg.inspect
    end
  end


  #
  # LogDevice -- Logging device.
  #
  class LogDevice
    attr_reader :dev
    attr_reader :filename

    #
    # == Synopsis
    #
    #   Logger::LogDev.new(name, :shift_age => 'daily|weekly|monthly')
    #   Logger::LogDev.new(name, :shift_age => 10, :shift_size => 1024*1024)
    #
    # == Args
    #
    # +name+::
    #   A String (representing a filename) or an IO object (actually, anything
    #   that responds to +write+ and +close+).  If a filename is given, then
    #   that file is opened for writing (and appending if it already exists),
    #   with +sync+ set to +true+.
    # +opts+::
    #   Contains optional arguments for rolling ("shifting") the log file.
    #   <tt>:shift_age</tt> is either a description (e.g. 'daily'), or an
    #   integer number of log files to keep.  <tt>shift_size</tt> is the maximum
    #   size of the log file, and is only significant is a number is given for
    #   <tt>shift_age</tt>.
    #
    #   These arguments are only relevant if a filename is provided for the
    #   first argument.
    #
    # == Description
    #
    # Creates a LogDevice object, which is the target for log messages.  Rolling
    # of log files is supported (only if a filename is given; you can't roll an
    # IO object).  The beginning of each file created by this class is tagged
    # with a header message.
    #
    # This class is unlikely to be used directly; it is a backend for Logger. 
    #
    def initialize(log = nil, opt = {})
      @dev = @filename = @shift_age = @shift_size = nil
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

    #
    # Log a message.  If needed, the log file is rolled and the new file is
    # prepared.  Log device is not locked.  Append open does not need to lock
    # file but on an OS which supports multi I/O, records could possibly be
    # mixed.
    #
    def write(message)
      if shift_log?
       	begin
  	  shift_log
   	rescue
  	  raise Logger::ShiftingError.new("Shifting failed. #{$!}")
   	end
      end

      @dev.write(message) 
    end

    #
    # Close the logging device.
    #
    def close
      @dev.close
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
      add_log_header(logdev)
      logdev
    end

    def add_log_header(file)
      file.write(
     	"# Logfile created on %s by %s\n" % [Time.now.to_s, Logger::ProgName]
    )
    end

    SiD = 24 * 60 * 60

    def shift_log?
      if !@shift_age or !@dev.respond_to?(:stat)
     	return false
      end
      if (@shift_age.is_a?(Integer))
	# Note: always returns false if '0'.
	return (@filename && (@shift_age > 0) && (@dev.stat.size > @shift_size))
      else
	now = Time.now
	limit_time = case @shift_age
	  when /^daily$/
	    eod(now - 1 * SiD)
	  when /^weekly$/
	    eod(now - ((now.wday + 1) * SiD))
	  when /^monthly$/
	    eod(now - now.mday * SiD)
	  else
	    now
	  end
	return (@dev.stat.mtime <= limit_time)
      end
    end

    def shift_log
      # At first, close the device if opened.
      if @dev
      	@dev.close
       	@dev = nil
      end
      if (@shift_age.is_a?(Integer))
	(@shift_age-3).downto(0) do |i|
	  if (FileTest.exist?("#{@filename}.#{i}"))
	    File.rename("#{@filename}.#{i}", "#{@filename}.#{i+1}")
	  end
	end
	File.rename("#{@filename}", "#{@filename}.0")
      else
	now = Time.now
	postfix_time = case @shift_age
	  when /^daily$/
	    eod(now - 1 * SiD)
	  when /^weekly$/
	    eod(now - ((now.wday + 1) * SiD))
	  when /^monthly$/
	    eod(now - now.mday * SiD)
	  else
	    now
	  end
	postfix = postfix_time.strftime("%Y%m%d")	# YYYYMMDD
	age_file = "#{@filename}.#{postfix}"
	if (FileTest.exist?(age_file))
	  raise RuntimeError.new("'#{ age_file }' already exists.")
	end
	File.rename("#{@filename}", age_file)
      end

      @dev = create_logfile(@filename)
      return true
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
  # 3. Instanciate it and invoke 'start'.
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

    attr_reader :appname
    attr_reader :logdev

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

    #
    # Sets the log device for this application.  See the classes Logger and
    # Logger::LogDevice for an explanation of the arguments.
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
      raise RuntimeError.new('Method run must be defined in the derived class.')
    end
  end
end
