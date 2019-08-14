# Initialize $MSPEC_DEBUG
$MSPEC_DEBUG ||= false

class ExceptionState
  attr_reader :description, :describe, :it, :exception

  def initialize(state, location, exception)
    @exception = exception

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
    [SpecExpectationNotMetError, SpecExpectationNotFoundError].any? { |e| @exception.is_a? e }
  end

  def message
    if @exception.message.empty?
      "<No message>"
    elsif @exception.class == SpecExpectationNotMetError ||
          @exception.class == SpecExpectationNotFoundError
      @exception.message
    else
      "#{@exception.class}: #{@exception.message}"
    end
  end

  def backtrace
    @backtrace_filter ||= MSpecScript.config[:backtrace_filter]

    bt = @exception.backtrace || []

    bt.select { |line| $MSPEC_DEBUG or @backtrace_filter !~ line }.join("\n")
  end
end
