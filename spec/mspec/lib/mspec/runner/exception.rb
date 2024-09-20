# Initialize $MSPEC_DEBUG
$MSPEC_DEBUG ||= false

class ExceptionState
  attr_reader :description, :describe, :it, :exception

  def initialize(state, location, exception)
    @exception = exception
    @failure = exception.class == SpecExpectationNotMetError || exception.class == SpecExpectationNotFoundError

    @description = location ? "An exception occurred during: #{location}" : ""
    if state
      @description += "\n" unless @description.empty?
      @description += state.description
      @describe = state.describe
      @it = state.it
    else
      @describe = @it = ""
    end
  end

  def failure?
    @failure
  end

  def message
    message = @exception.message
    message = "<No message>" if message.empty?

    if @failure
      message
    elsif raise_error_message = RaiseErrorMatcher::FAILURE_MESSAGE_FOR_EXCEPTION[@exception]
      raise_error_message.join("\n")
    else
      "#{@exception.class}: #{message}"
    end
  end

  def backtrace
    @backtrace_filter ||= MSpecScript.config[:backtrace_filter] || %r{(?:/bin/mspec|/lib/mspec/)}

    bt = @exception.backtrace || []
    unless $MSPEC_DEBUG
      # Exclude <internal: entries inside MSpec code, so only after the first ignored entry
      first_excluded_line = bt.index { |line| @backtrace_filter =~ line }
      if first_excluded_line
        bt = bt[0...first_excluded_line] + bt[first_excluded_line..-1].reject { |line|
          @backtrace_filter =~ line || /^<internal:/ =~ line
        }
      end
    end
    bt.join("\n")
  end
end
