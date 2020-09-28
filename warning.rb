# encoding: utf-8
# frozen-string-literal: true

module Kernel
  module_function

  # call-seq:
  #    warn(*msgs, uplevel: nil)   -> nil
  #
  # If warnings have been disabled (for example with the
  # <code>-W0</code> flag), does nothing.  Otherwise,
  # converts each of the messages to strings, appends a newline
  # character to the string if the string does not end in a newline,
  # and calls Warning.warn with the string.
  #
  #    warn("warning 1", "warning 2")
  #
  #  <em>produces:</em>
  #
  #    warning 1
  #    warning 2
  #
  # If the <code>uplevel</code> keyword argument is given, the string will
  # be prepended with information for the given caller frame in
  # the same format used by the <code>rb_warn</code> C function.
  #
  #    # In baz.rb
  #    def foo
  #      warn("invalid call to foo", uplevel: 1)
  #    end
  #
  #    def bar
  #      foo
  #    end
  #
  #    bar
  #
  #  <em>produces:</em>
  #
  #    baz.rb:6: warning: invalid call to foo
  #
  # If <code>category</code> keyword argument is given, passes the category
  # to <code>Warning.warn</code>.  The category given must be be one of the
  # following categories:
  #
  # :deprecated :: Used for warning for deprecated functionality that may
  #                be removed in the future.
  # :redefine :: Used for when redefining constants and methods that already
  #              exist.
  # :uninitialized_ivar :: Used for uninitialized instance variables.
  def warn(*msgs, uplevel: nil, category: nil)
    Primitive.rb_warn_m(msgs, uplevel, category)
  end
end
