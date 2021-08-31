require 'mspec/runner/formatters/base'

class SpecdocFormatter < BaseFormatter
  def register
    super
    MSpec.register :enter, self
  end

  # Callback for the MSpec :enter event. Prints the
  # +describe+ block string.
  def enter(describe)
    print "\n#{describe}\n"
  end

  # Callback for the MSpec :before event. Prints the
  # +it+ block string.
  def before(state)
    super(state)
    print "- #{state.it}"
  end

  # Callback for the MSpec :exception event. Prints
  # either 'ERROR - X' or 'FAILED - X' where _X_ is
  # the sequential number of the exception raised. If
  # there has already been an exception raised while
  # evaluating this example, it prints another +it+
  # block description string so that each description
  # string has an associated 'ERROR' or 'FAILED'
  def exception(exception)
    print "\n- #{exception.it}" if exception?
    super(exception)
    print " (#{exception.failure? ? 'FAILED' : 'ERROR'} - #{@count})"
  end

  # Callback for the MSpec :after event. Prints a
  # newline to finish the description string output.
  def after(state = nil)
    super(state)
    print "\n"
  end
end
