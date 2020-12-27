class Exception
  # call-seq:
  #   exception.full_message(highlight: nil, order: nil, backtrace_limit: nil) ->  string
  #
  # Returns formatted string of _exception_.
  # The returned string is formatted using the same format that Ruby uses
  # when printing an uncaught exceptions to stderr.
  #
  # If _highlight_ is +true+ the default error handler will send the
  # messages to a tty.
  #
  # _order_ must be either of +:top+ or +:bottom+, and places the error
  # message and the innermost backtrace come at the top or the bottom.
  #
  # If _backtrace_limit_ is positive number, backtrace length is
  # limited to the value.  If it is +nil+, limited to the default
  # value, specified by the `--backtrace-limit` command line option.
  # If it is +false+, unlimited.
  #
  # The default values of _highlight_ and _order_ depend on
  # <code>$stderr</code> and its +tty?+ at the timing of a call.
  def full_message(highlight: nil, order: nil, backtrace_limit: nil)
    __builtin.exc_full_message(highlight, order, backtrace_limit)
  end
end
