class Exception
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
  def full_message(highlight: nil, order: nil)
    __builtin_exc_full_message(highlight, order)
  end
end

class NameError
  # call-seq:
  #   NameError.new(msg=nil, name=nil, receiver: nil)  -> name_error
  #
  # Construct a new NameError exception. If given the <i>name</i>
  # parameter may subsequently be examined using the NameError#name
  # method. <i>receiver</i> parameter allows to pass object in
  # context of which the error happened. Example:
  #
  #    [1, 2, 3].method(:rject) # NameError with name "rject" and receiver: Array
  #    [1, 2, 3].singleton_method(:rject) # NameError with name "rject" and receiver: [1, 2, 3]
  def initialize(msg = nil, name = nil, receiver: no = true, **kws)
    super(msg, **kws)
    __builtin_err_init_recv(receiver) unless no
    __builtin_name_err_init_attr(name)
    self
  end
end

class NoMethodError
  #
  # call-seq:
  #   NoMethodError.new(msg=nil, name=nil, args=nil, private=false, receiver: nil)  -> no_method_error
  #
  # Construct a NoMethodError exception for a method of the given name
  # called with the given arguments. The name may be accessed using
  # the <code>#name</code> method on the resulting object, and the
  # arguments using the <code>#args</code> method.
  #
  # If <i>private</i> argument were passed, it designates method was
  # attempted to call in private context, and can be accessed with
  # <code>#private_call?</code> method.
  #
  # <i>receiver</i> argument stores an object whose method was called.
  def initialize(msg = nil, name = nil, args = nil, private = false, **kws)
    super(msg, name, **kws)
    __builtin_nometh_err_initialize(args, private)
    self
  end
end

class FrozenError
  # call-seq:
  #   FrozenError.new(msg=nil, receiver: nil)  -> frozen_error
  #
  # Construct a new FrozenError exception. If given the <i>receiver</i>
  # parameter may subsequently be examined using the FrozenError#receiver
  # method.
  #
  #    a = [].freeze
  #    raise FrozenError.new("can't modify frozen array", receiver: a)
  def initialize(msg = nil, receiver: no = true, **kws)
    super(msg, **kws)
    __builtin_err_init_recv(receiver) unless no
    self
  end
end

class KeyError
  # call-seq:
  #   KeyError.new(message=nil, receiver: nil, key: nil) -> key_error
  #
  # Construct a new +KeyError+ exception with the given message,
  # receiver and key.
  def initialize(msg = nil, receiver: norecv = true, key: nokey = true, **kws)
    super(msg, **kws)
    __builtin_err_init_receiver(receiver) unless norecv
    __builtin_err_init_key(key) unless nokey
    self
  end
end
