class RaiseErrorMatcher
  attr_writer :block

  def initialize(exception, message, &block)
    @exception = exception
    @message = message
    @block = block
    @actual = nil
  end

  # This #matches? method is unusual because it doesn't always return a boolean but instead
  # re-raises the original exception if proc.call raises an exception and #matching_exception? is false.
  # The reasoning is the original exception class matters and we don't want to change it by raising another exception,
  # so instead we attach the #failure_message and extract it in ExceptionState#message.
  def matches?(proc)
    @result = proc.call
    return false
  rescue Exception => actual
    @actual = actual

    if matching_exception?(actual)
      # The block has its own expectations and will throw an exception if it fails
      @block[actual] if @block
      return true
    else
      actual.instance_variable_set(:@mspec_raise_error_message, failure_message)
      raise actual
    end
  end

  def matching_class?(exc)
    @exception === exc
  end

  def matching_message?(exc)
    case @message
    when String
      @message == exc.message
    when Regexp
      @message =~ exc.message
    else
      true
    end
  end

  def matching_exception?(exc)
    matching_class?(exc) and matching_message?(exc)
  end

  def exception_class_and_message(exception_class, message)
    if message
      "#{exception_class} (#{message})"
    else
      "#{exception_class}"
    end
  end

  def format_expected_exception
    exception_class_and_message(@exception, @message)
  end

  def format_exception(exception)
    exception_class_and_message(exception.class, exception.message)
  end

  def failure_message
    message = ["Expected #{format_expected_exception}"]

    if @actual
      message << "but got: #{format_exception(@actual)}"
    else
      message << "but no exception was raised (#{MSpec.format(@result)} was returned)"
    end

    message
  end

  def negative_failure_message
    message = ["Expected to not get #{format_expected_exception}", ""]
    unless @actual.class == @exception
      message[1] = "but got: #{format_exception(@actual)}"
    end
    message
  end
end

module MSpecMatchers
  private def raise_error(exception = Exception, message = nil, &block)
    RaiseErrorMatcher.new(exception, message, &block)
  end
end
