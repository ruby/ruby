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
  def initialize(msg = nil, name = nil, receiver: self, **kws)
    super(msg, **kws)
    __builtin_name_err_initialize(receiver, name)
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
