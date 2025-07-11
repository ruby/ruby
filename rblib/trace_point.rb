# loaded from vm_trace.c

# A class that provides the functionality of Kernel#set_trace_func in a
# well-structured Object-Oriented API.
#
# == Example
#
# Use TracePoint to gather information specifically for exceptions:
#
#     trace = TracePoint.new(:raise) do |tp|
#       p [tp.lineno, tp.event, tp.raised_exception]
#     end
#     #=> #<TracePoint:disabled>
#
#     trace.enable  #=> false
#
#     0 / 0
#     #=> [5, :raise, #<ZeroDivisionError: divided by 0>]
#
# == Events
#
# If you don't specify the types of events you want to listen for,
# TracePoint will include all available events.
#
# *Note:* Do not depend on the current event set, as this list is subject to
# change. Instead, it is recommended to specify the types of events you
# want to use.
#
# To filter what is traced, you can pass any of the following as +events+:
#
# +:line+:: Execute an expression or statement on a new line.
# +:class+:: Start a class or module definition.
# +:end+:: Finish a class or module definition.
# +:call+:: Call a Ruby method.
# +:return+:: Return from a Ruby method.
# +:c_call+:: Call a C-language routine.
# +:c_return+:: Return from a C-language routine.
# +:raise+:: Raise an exception.
# +:rescue+:: Rescue an exception.
# +:b_call+:: Event hook at block entry.
# +:b_return+:: Event hook at block ending.
# +:a_call+:: Event hook at all calls (+call+, +b_call+, and +c_call+).
# +:a_return+:: Event hook at all returns (+return+, +b_return+, and +c_return+).
# +:thread_begin+:: Event hook at thread beginning.
# +:thread_end+:: Event hook at thread ending.
# +:fiber_switch+:: Event hook at fiber switch.
# +:script_compiled+:: New Ruby code compiled (with +eval+, +load+, or +require+).
#
class TracePoint
  # call-seq:
  #   TracePoint.new(*events) { |tp| block } -> tp
  #
  # Returns a new TracePoint object, not enabled by default.
  #
  # To activate the TracePoint object, use TracePoint#enable:
  #
  #     trace = TracePoint.new(:call) do |tp|
  #       p [tp.lineno, tp.defined_class, tp.method_id, tp.event]
  #     end
  #     #=> #<TracePoint:disabled>
  #
  #     trace.enable  #=> false
  #
  #     puts "Hello, TracePoint!"
  #     # ...
  #     # [48, IRB::Notifier::AbstractNotifier, :printf, :call]
  #     # ...
  #
  # To deactivate the trace, use TracePoint#disable.
  #
  #     trace.disable
  #
  # See TracePoint@Events for possible events and more information.
  #
  # A block must be given; otherwise, an ArgumentError is raised.
  #
  # If the trace method isn't included in the given events filter, a
  # RuntimeError is raised.
  #
  #     TracePoint.trace(:line) do |tp|
  #       p tp.raised_exception
  #     end
  #     #=> RuntimeError: 'raised_exception' not supported by this event
  #
  # If the trace method is called outside a block, a RuntimeError is raised.
  #
  #     TracePoint.trace(:line) do |tp|
  #       $tp = tp
  #     end
  #     $tp.lineno #=> access from outside (RuntimeError)
  #
  # Access from other threads is also forbidden.
  #
  def self.new(*events)
    Primitive.attr! :use_block
    Primitive.tracepoint_new_s(events)
  end

  # call-seq:
  #   trace.inspect -> string
  #
  # Returns a string containing a human-readable TracePoint
  # status.
  def inspect
    Primitive.tracepoint_inspect
  end

  # call-seq:
  #   TracePoint.stat -> obj
  #
  # Returns internal information of TracePoint.
  #
  # The contents of the returned value are implementation-specific
  # and may change in the future.
  #
  # This method is only for debugging TracePoint itself.
  def self.stat
    Primitive.tracepoint_stat_s
  end

  # call-seq:
  #   TracePoint.trace(*events) { |tp| block } -> obj
  #
  # A convenience method for TracePoint.new that activates the trace
  # automatically.
  #
  #     trace = TracePoint.trace(:call) { |tp| [tp.lineno, tp.event] }
  #     #=> #<TracePoint:enabled>
  #
  #     trace.enabled?  #=> true
  #
  def self.trace(*events)
    Primitive.attr! :use_block
    Primitive.tracepoint_trace_s(events)
  end

  # call-seq:
  #   TracePoint.allow_reentry { block }
  #
  # Generally, while a TracePoint callback is running,
  # other registered callbacks are not called to avoid
  # confusion from reentrance.
  # This method allows reentrance within a given block.
  # Use this method carefully to avoid infinite callback invocation.
  #
  # If called when reentrance is already allowed,
  # it raises a RuntimeError.
  #
  # <b>Example:</b>
  #
  #   # Without reentry
  #   # ---------------
  #
  #   line_handler = TracePoint.new(:line) do |tp|
  #     next if tp.path != __FILE__ # Only works in this file
  #     puts "Line handler"
  #     binding.eval("class C; end")
  #   end.enable
  #
  #   class_handler = TracePoint.new(:class) do |tp|
  #     puts "Class handler"
  #   end.enable
  #
  #   class B
  #   end
  #
  #   # This script will print "Class handler" only once: when inside the :line
  #   # handler, all other handlers are ignored.
  #
  #
  #   # With reentry
  #   # ------------
  #
  #   line_handler = TracePoint.new(:line) do |tp|
  #     next if tp.path != __FILE__ # Only works in this file
  #     next if (__LINE__..__LINE__+3).cover?(tp.lineno) # Prevent infinite calls
  #     puts "Line handler"
  #     TracePoint.allow_reentry { binding.eval("class C; end") }
  #   end.enable
  #
  #   class_handler = TracePoint.new(:class) do |tp|
  #     puts "Class handler"
  #   end.enable
  #
  #   class B
  #   end
  #
  #   # This will print "Class handler" twice: inside the allow_reentry block in the :line
  #   # handler, other handlers are enabled.
  #
  # Note that the example shows the principal effect of the method, but its
  # practical usage is for debugging libraries that sometimes require other libraries'
  # hooks to not be affected by the debugger being inside trace point handling.
  # Precautions should be taken against infinite recursion in this case
  # (note that we needed to filter out calls by itself from the :line handler,
  # otherwise it would call itself infinitely).
  #
  def self.allow_reentry
    Primitive.attr! :use_block
    Primitive.tracepoint_allow_reentry
  end

  # call-seq:
  #   trace.enable(target: nil, target_line: nil, target_thread: nil) -> true or false
  #   trace.enable(target: nil, target_line: nil, target_thread: :default) { block } -> obj
  #
  # Activates the trace.
  #
  # Returns +true+ if the trace was enabled.
  # Returns +false+ if the trace was disabled.
  #
  #   trace.enabled?  #=> false
  #   trace.enable    #=> false (previous state)
  #                   #   trace is enabled
  #   trace.enabled?  #=> true
  #   trace.enable    #=> true (previous state)
  #                   #   trace is still enabled
  #
  # If a block is given, the trace will only be enabled during the block execution.
  # If target and target_line are both nil, then target_thread will default
  # to the current thread if a block is given.
  #
  #     trace.enabled?  #=> false
  #
  #     trace.enable do
  #       trace.enabled?
  #       # Only enabled for this block and thread
  #     end
  #
  #     trace.enabled?  #=> false
  #
  # The +target+, +target_line+, and +target_thread+ parameters are used to
  # limit tracing to specified code objects. +target+ should be a
  # code object for which RubyVM::InstructionSequence.of will return
  # an instruction sequence.
  #
  #     t = TracePoint.new(:line) { |tp| p tp }
  #
  #     def m1
  #       p 1
  #     end
  #
  #     def m2
  #       p 2
  #     end
  #
  #     t.enable(target: method(:m1))
  #
  #     m1
  #     # Prints #<TracePoint:line test.rb:4 in `m1'>
  #     m2
  #     # Prints nothing
  #
  # Note: You cannot access event hooks within the +enable+ block.
  #
  #     trace.enable { p tp.lineno }
  #     #=> RuntimeError: access from outside
  #
  def enable(target: nil, target_line: nil, target_thread: :default)
    Primitive.attr! :use_block
    Primitive.tracepoint_enable_m(target, target_line, target_thread)
  end

  # call-seq:
  #   trace.disable -> true or false
  #   trace.disable { block } -> obj
  #
  # Deactivates the trace.
  #
  # Returns +true+ if the trace was enabled.
  # Returns +false+ if the trace was disabled.
  #
  #     trace.enabled?  #=> true
  #     trace.disable   #=> true (previous status)
  #     trace.enabled?  #=> false
  #     trace.disable   #=> false
  #
  # If a block is given, the trace will only be disabled within the scope of the
  # block.
  #
  #     trace.enabled?  #=> true
  #
  #     trace.disable do
  #       trace.enabled?
  #       # Only disabled for this block
  #     end
  #
  #     trace.enabled?  #=> true
  #
  # Note: You cannot access event hooks within the block.
  #
  #     trace.disable { p tp.lineno }
  #     #=> RuntimeError: access from outside
  #
  def disable
    Primitive.attr! :use_block
    Primitive.tracepoint_disable_m
  end

  # call-seq:
  #   trace.enabled? -> true or false
  #
  # Returns the current status of the trace.
  def enabled?
    Primitive.tracepoint_enabled_p
  end

  # Returns the type of event.
  #
  # See TracePoint@Events for more information.
  def event
    Primitive.tracepoint_attr_event
  end

  # Returns the line number of the event.
  def lineno
    Primitive.tracepoint_attr_lineno
  end

  # Returns the path of the file being executed.
  def path
    Primitive.tracepoint_attr_path
  end

  # Returns the parameter definitions of the method or block that the
  # current hook belongs to. The format is the same as for Method#parameters.
  def parameters
    Primitive.tracepoint_attr_parameters
  end

  # Returns the name at the definition of the method being called.
  def method_id
    Primitive.tracepoint_attr_method_id
  end

  # Returns the called name of the method being called.
  def callee_id
    Primitive.tracepoint_attr_callee_id
  end

  # Returns the class or module of the method being called.
  #
  #     class C; def foo; end; end
  #     trace = TracePoint.new(:call) do |tp|
  #       p tp.defined_class #=> C
  #     end.enable do
  #       C.new.foo
  #     end
  #
  # If the method is defined by a module, then that module is returned.
  #
  #     module M; def foo; end; end
  #     class C; include M; end
  #     trace = TracePoint.new(:call) do |tp|
  #       p tp.defined_class #=> M
  #     end.enable do
  #       C.new.foo
  #     end
  #
  # <b>Note:</b> #defined_class returns the singleton class.
  #
  # The 6th block parameter of Kernel#set_trace_func passes the original class
  # attached by the singleton class.
  #
  # <b>This is a difference between Kernel#set_trace_func and TracePoint.</b>
  #
  #     class C; def self.foo; end; end
  #     trace = TracePoint.new(:call) do |tp|
  #       p tp.defined_class #=> #<Class:C>
  #     end.enable do
  #       C.foo
  #     end
  def defined_class
    Primitive.tracepoint_attr_defined_class
  end

  # Returns the generated binding object from the event.
  #
  # Note that for +:c_call+ and +:c_return+ events, the method returns
  # +nil+, since C methods themselves do not have bindings.
  def binding
    Primitive.tracepoint_attr_binding
  end

  # Returns the trace object during the event.
  #
  # Similar to the following, but it returns the correct object (the method
  # receiver) for +:c_call+ and +:c_return+ events:
  #
  #   trace.binding.eval('self')
  def self
    Primitive.tracepoint_attr_self
  end

  # Returns the return value from +:return+, +:c_return+, and +:b_return+ events.
  def return_value
    Primitive.tracepoint_attr_return_value
  end

  # Returns the exception raised on the +:raise+ event or rescued on the +:rescue+ event.
  def raised_exception
    Primitive.tracepoint_attr_raised_exception
  end

  # Returns the compiled source code (String) from eval methods on the +:script_compiled+ event.
  # If loaded from a file, it returns +nil+.
  def eval_script
    Primitive.tracepoint_attr_eval_script
  end

  # Returns the compiled instruction sequence represented by a RubyVM::InstructionSequence instance
  # on the +:script_compiled+ event.
  #
  # Note that this method is CRuby-specific.
  def instruction_sequence
    Primitive.tracepoint_attr_instruction_sequence
  end
end
