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
    elsif raise_error_message = @exception.instance_variable_get(:@mspec_raise_error_message)
      raise_error_message.join("\n")
    else
      "#{@exception.class}: #{message}"
    end
  end

  def backtrace
    @backtrace_filter ||= MSpecScript.config[:backtrace_filter] || %r{(?:/bin/mspec|/lib/mspec/)}

    bt = @exception.backtrace || []
    bt.select { |line| $MSPEC_DEBUG or @backtrace_filter !~ line }.join("\n")
  end
end
