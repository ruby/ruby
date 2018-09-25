class RaiseErrorMatcher
  def initialize(exception, message, &block)
    @exception = exception
    @message = message
    @block = block
    @actual = nil
  end

  def matches?(proc)
    @result = proc.call
    return false
  rescue Exception => actual
    @actual = actual
    if matching_exception?(actual)
      return true
    else
      raise actual
    end
  end

  def matching_exception?(exc)
    return false unless @exception === exc
    if @message then
      case @message
      when String
        return false if @message != exc.message
      when Regexp
        return false if @message !~ exc.message
      end
    end

    # The block has its own expectations and will throw an exception if it fails
    @block[exc] if @block

    return true
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

  def format_result(result)
    result.pretty_inspect.chomp
  rescue => e
    "#pretty_inspect raised #{e.class}; A #<#{result.class}>"
  end

  def failure_message
    message = ["Expected #{format_expected_exception}"]

    if @actual
      message << "but got #{format_exception(@actual)}"
    else
      message << "but no exception was raised (#{format_result(@result)} was returned)"
    end

    message
  end

  def negative_failure_message
    message = ["Expected to not get #{format_expected_exception}", ""]
    unless @actual.class == @exception
      message[1] = "but got #{format_exception(@actual)}"
    end
    message
  end
end

module MSpecMatchers
  private def raise_error(exception=Exception, message=nil, &block)
    RaiseErrorMatcher.new(exception, message, &block)
  end
end
