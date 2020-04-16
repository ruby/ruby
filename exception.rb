class Exception
  #
  # call-seq:
  #   exception.full_message(highlight: bool, order: [:top or :bottom]) ->  string
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
  # The default values of these options depend on <code>$stderr</code>
  # and its +tty?+ at the timing of a call.
  #
  def full_message(highlight: nil, order: nil)
    __builtin_exc_full_message(highlight, order)
  end
end
