# Logger -- Logging utility.
#
# $Id$
#
# This module is copyrighted free software by NAKAMURA, Hiroshi.
# You can redistribute it and/or modify it under the same term as Ruby.
#
# See Logger at first.


# DESCRIPTION
#   Logger -- Logging utility.
#
# How to create a logger.
#   1. Create logger which logs messages to STDERR/STDOUT.
#     logger = Logger.new(STDERR)
#     logger = Logger.new(STDOUT)
#
#   2. Create logger for the file which has the specified name.
#     logger = Logger.new('logfile.log')
#
#   3. Create logger for the specified file.
#     file = open('foo.log', File::WRONLY | File::APPEND)
#     # To create new (and to remove old) logfile, add File::CREAT like;
#     #   file = open('foo.log', File::WRONLY | File::APPEND | File::CREAT)
#     logger = Logger.new(file)
#
#   4. Create logger which ages logfile automatically.  Leave 10 ages and each
#      file is about 102400 bytes.
#     logger = Logger.new('foo.log', 10, 102400)
#
#   5. Create logger which ages logfile daily/weekly/monthly automatically.
#     logger = Logger.new('foo.log', 'daily')
#     logger = Logger.new('foo.log', 'weekly')
#     logger = Logger.new('foo.log', 'monthly')
#
# How to log a message.
#
#   1. Message in block.
#     logger.fatal { "Argument 'foo' not given." }
#
#   2. Message as a string.
#     logger.error "Argument #{ @foo } mismatch."
#
#   3. With progname.
#     logger.info('initialize') { "Initializing..." }
#
#   4. With severity.
#     logger.add(Logger::FATAL) { 'Fatal error!' }
#
# How to close a logger.
#
#   logger.close
#
# Setting severity threshold.
#
#   1. Original interface.
#     logger.level = Logger::WARN
#
#   2. Log4r (somewhat) compatible interface.
#     logger.level = Logger::INFO
#
#   DEBUG < INFO < WARN < ERROR < FATAL < UNKNOWN
#
# Format.
#
#   Log format:
#     SeverityID, [Date Time mSec #pid] SeverityLabel -- ProgName: message
#
#   Log sample:
#     I, [Wed Mar 03 02:34:24 JST 1999 895701 #19074]  INFO -- Main: info.
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

  # Logging severity threshold.
  attr_accessor :level

  # Logging program name.
  attr_accessor :progname

  # Logging date-time format (string passed to strftime)
  attr_accessor :datetime_format

  alias sev_threshold level
  alias sev_threshold= level=

  def debug?; @level <= DEBUG; end
  def info?; @level <= INFO; end
  def warn?; @level <= WARN; end
  def error?; @level <= ERROR; end
  def fatail?; @level <= FATAL; end

  # SYNOPSIS
  #   Logger.new(name, shift_age = 7, shift_size = 1048576)
  #
  # ARGS
  #   log	String as filename of logging.
  #		or
  #		IO as logging device(i.e. STDERR).
  #   shift_age	An Integer	Num of files you want to keep aged logs.
  #		'daily'		Daily shifting.
  #		'weekly'	Weekly shifting (Every monday.)
  #		'monthly'	Monthly shifting (Every 1th day.)
  #   shift_size	Shift size threshold when shift_age is an integer.
  #		Otherwise (like 'daily'), shift_size will be ignored.
  #
  # DESCRIPTION
  #   Create an instance.
  #
  def initialize(logdev, shift_age = 0, shift_size = 1048576)
    @logdev = nil
    @progname = nil
    @level = DEBUG
    @datetime_format = nil
    @logdev = LogDevice.new(logdev, :shift_age => shift_age, :shift_size => shift_size) if logdev
  end

  # SYNOPSIS
  #   Logger#add(severity, msg = nil, progname = nil) { ... } = nil
  #
  # ARGS
  #   severity	Severity.  Constants are defined in Logger namespace.
  #		DEBUG, INFO, WARN, ERROR, FATAL, or UNKNOWN.
  #   msg	Message.  A string, exception, or something. Can be omitted.
  #   progname	Program name string.  Can be omitted.
  #   		Logged as a msg if no msg and block are given.
  #   block     Can be omitted.
  #             Called to get a message string if msg is nil.
  #
  # RETURN
  #   true if succeed, false if failed.
  #   When the given severity is not enough severe,
  #   Log no message, and returns true.
  #
  # DESCRIPTION
  #   Log a log if the given severity is enough severe.
  #
  # BUGS
  #   Logfile is not locked.
  #   Append open does not need to lock file.
  #   But on the OS which supports multi I/O, records possibly be mixed.
  #
  def add(severity, msg = nil, progname = nil, &block)
    severity ||= UNKNOWN
    if @logdev.nil? or severity < @level
      return true
    end
    progname ||= @progname
    if msg.nil?
      if block_given?
	msg = yield
      else
	msg = progname
	progname = @progname
      end
    end
    @logdev.write(
      format_message(
	format_severity(severity),
	format_datetime(Time.now),
	msg2str(msg),
	progname
      )
    )
    true
  end
  alias log add

  # SYNOPSIS
  #   Logger#debug(progname = nil) { ... } = nil
  #   Logger#info(progname = nil) { ... } = nil
  #   Logger#warn(progname = nil) { ... } = nil
  #   Logger#error(progname = nil) { ... } = nil
  #   Logger#fatal(progname = nil) { ... } = nil
  #   Logger#unknown(progname = nil) { ... } = nil
  #
  # ARGS
  #   progname	Program name string.  Can be omitted.
  #   		Logged as a msg if no block are given.
  #   block     Can be omitted.
  #             Called to get a message string if msg is nil.
  #
  # RETURN
  #   See Logger#add .
  #
  # DESCRIPTION
  #   Log a log.
  #
  def debug(progname = nil, &block)
    add(DEBUG, nil, progname, &block)
  end

  def info(progname = nil, &block)
    add(INFO, nil, progname, &block)
  end

  def warn(progname = nil, &block)
    add(WARN, nil, progname, &block)
  end

  def error(progname = nil, &block)
    add(ERROR, nil, progname, &block)
  end

  def fatal(progname = nil, &block)
    add(FATAL, nil, progname, &block)
  end

  def unknown(progname = nil, &block)
    add(UNKNOWN, nil, progname, &block)
  end

  # SYNOPSIS
  #   Logger#close
  #
  # DESCRIPTION
  #   Close the logging device.
  #
  def close
    @logdev.close if @logdev
  end

private

  # Severity label for logging. (max 5 char)
  SEV_LABEL = %w(DEBUG INFO WARN ERROR FATAL ANY);

  def format_severity(severity)
    SEV_LABEL[severity] || 'UNKNOWN'
  end

  def format_datetime(datetime)
    if @datetime_format.nil?
      datetime.strftime("%Y-%m-%dT%H:%M:%S.") << "%6d " % datetime.usec
    else
      datetime.strftime(@datetime_format)
    end
  end

  def format_message(severity, timestamp, msg, progname)
    line = '%s, [%s#%d] %5s -- %s: %s' << "\n"
    line % [severity[0..0], timestamp, $$, severity, progname, msg]
  end

  def msg2str(msg)
    if msg.is_a?(::String)
      msg
    elsif msg.is_a?(::Exception)
      "#{ msg.message } (#{ msg.class })\n" << (msg.backtrace || []).join("\n")
    elsif msg.respond_to?(:to_str)
      msg.to_str
    else
      msg.inspect
    end
  end


  # LogDevice -- Logging device.
  class LogDevice
    attr_reader :dev
    attr_reader :filename

    # SYNOPSIS
    #   Logger::LogDev.new(name, opt = {})
    #
    # ARGS
    #   log	String as filename of logging.
    #		  or
    #		IO as logging device(i.e. STDERR).
    #	opt	Hash of options.
    #
    # DESCRIPTION
    #   Log device class.  Output and shifting of log.
    #	When a String was given, LogDevice opens the file and set sync = true.
    #
    # OPTIONS
    #   :shift_age
    #     An Integer	Num of files you want to keep aged logs.
    #	  'daily'	Daily shifting.
    #	  'weekly'	Weekly shifting (Shift every monday.)
    #	  'monthly'	Monthly shifting (Shift every 1th day.)
    #
    #   :shift_size	Shift size threshold when :shift_age is an integer.
    #			Otherwise (like 'daily'), it is ignored.
    #
    def initialize(log = nil, opt = {})
      @dev = @filename = @shift_age = @shift_size = nil
      if log.is_a?(IO)
	@dev = log
      elsif log.is_a?(String)
	@dev = open_logfile(log)
	@dev.sync = true
	@filename = log
	@shift_age = opt[:shift_age] || 7
	@shift_size = opt[:shift_size] || 1048576
      else
	raise ArgumentError.new("Wrong argument: #{ log } for log.")
      end
    end

    # SYNOPSIS
    #   Logger::LogDev#write(message)
    #
    # ARGS
    #   message		Message to be logged.
    #
    # DESCRIPTION
    #   Log a message.  If needed, the log device is aged and the new device
    #  	is prepared.  Log device is not locked.  Append open does not need to
    #  	lock file but on the OS which supports multi I/O, records possibly be
    #  	mixed.
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

    # SYNOPSIS
    #   Logger::LogDev#close
    #
    # DESCRIPTION
    #   Close the logging device.
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


  # DESCRIPTION
  #   Application -- Add logging support to your application.
  #
  # USAGE
  #   1. Define your application class as a sub-class of this class.
  #   2. Override 'run' method in your class to do many things.
  #   3. Instanciate it and invoke 'start'.
  #
  # EXAMPLE
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

    # SYNOPSIS
    #   Application.new(appname = '')
    #
    # ARGS
    #   appname	Name String of the application.
    #
    # DESCRIPTION
    #   Create an instance.  Log device is STDERR by default.
    #
    def initialize(appname = nil)
      @appname = appname
      @log = Logger.new(STDERR)
      @log.progname = @appname
      @level = @log.level
    end

    # SYNOPSIS
    #   Application#start
    #
    # DESCRIPTION
    #   Start the application.
    #
    # RETURN
    #   Status code.
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

    # SYNOPSIS
    #   Application#set_log(log, shift_age, shift_size)
    #
    # ARGS
    #   (Args are explained in the class Logger)
    #
    # DESCRIPTION
    #   Set the log device for this application.
    #
    def set_log(logdev, shift_age = 0, shift_size = 102400)
      @log = Logger.new(logdev, shift_age, shift_size)
      @log.progname = @appname
      @log.level = @level
    end

    def log=(logdev)
      set_log(logdev)
    end


    # SYNOPSIS
    #   Application#level=(severity)
    #
    # ARGS
    #   level	Severity threshold.
    #
    # DESCRIPTION
    #   Set severity threshold.
    #
    def level=(level)
      @level = level
      @log.level = @level
    end

  protected

    # SYNOPSIS
    #   Application#log(severity, comment = nil) { ... }
    #
    # ARGS
    #   severity	Severity. See above to give this.
    #   comment		Message String.
    #   block     	Can be omitted.  Called to get a message String if
    #			comment is nil or omitted.
    #
    # DESCRIPTION
    #   Log a log if the given severity is enough severe.
    #   For more detail, see Log.add.
    #
    # RETURN
    #   true if succeed, false if failed.
    #   When the given severity is not enough severe,
    #   Log no message, and returns true.
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
