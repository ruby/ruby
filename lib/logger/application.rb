#
# == Description
#
# Logger::Application --- Add logging support to your application.
#
# == Usage
#
# 1. Define your application class as a sub-class of this class.
# 2. Override the +run+ method in your class to do many things.
# 3. Instantiate it and invoke #start.
#
# == Example
#
#   class FooApp < Logger::Application
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

require 'logger'

class Logger
  class Application
    include Logger::Severity

    # Name of the application given at initialize.
    attr_reader :appname

    #
    # :call-seq:
    #   Logger::Application.new(appname = '')
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
    # Sets the logger for this application.  See the class Logger for an
    # explanation.
    #
    def logger=(logger)
      @log = logger
      @log.progname = @appname
      @log.level = @level
    end

    #
    # Sets the log device for this application.  See <tt>Logger.new</tt> for
    # an explanation of the arguments.
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
