class RaiseErrorMatcher
  FAILURE_MESSAGE_FOR_EXCEPTION = {}.compare_by_identity
  UNDEF_CAUSE = Object.new

  attr_writer :block

  def initialize(exception, message = nil, options = nil, &block)
    if message.is_a? Hash
      @message = nil
      options = message
    else
      @message = message
    end
    @cause = options ? options.fetch(:cause, UNDEF_CAUSE) : UNDEF_CAUSE
    @exception = exception
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
  rescue Object => actual
    @actual = actual

    if matching_exception?(actual)
      # The block has its own expectations and will throw an exception if it fails
      @block[actual] if @block
      return true
    else
      FAILURE_MESSAGE_FOR_EXCEPTION[actual] = failure_message
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

  def matching_cause?(exc)
    case @cause
    when UNDEF_CAUSE
      true
    else
      @cause == exc.cause
    end
  end

  def matching_exception?(exc)
    matching_class?(exc) and matching_message?(exc) and matching_cause?(exc)
  end

  def exception_class_and_message_and_cause(exception_class, message, cause)
    string = "#{exception_class}"
    prefixed = false
    prefix = -> { prefixed ? ", " : prefixed = "(" }

    if message != nil
      string << "#{prefix.()}#{message.inspect}"
    end

    if cause != UNDEF_CAUSE
      string << "#{prefix.()}cause: #{cause.inspect}"
    end

    string << ")" if prefixed

    string
  end

  def format_expected_exception
    exception_class_and_message_and_cause(@exception, @message, @cause)
  end

  def format_exception(exception)
    exception_class_and_message_and_cause(exception.class,
                                          @message == nil ? nil : exception.message,
                                          @cause == UNDEF_CAUSE ? UNDEF_CAUSE : exception.cause)
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
  private def raise_error(exception = Exception, message = nil, options = nil, &block)
    RaiseErrorMatcher.new(exception, message, options, &block)
  end

  # CRuby < 4.1 has inconsistent coercion errors:
  # https://bugs.ruby-lang.org/issues/21864
  # This matcher ignores the message on CRuby < 4.1
  # and checks the message for all other cases, including other Rubies
  private def raise_consistent_error(exception = Exception, message = nil, options = nil, &block)
    if RUBY_ENGINE == "ruby" and ruby_version_is ""..."4.1"
      message = nil
    end
    RaiseErrorMatcher.new(exception, message, options, &block)
  end
end
