# loaded from vm_trace.c

# Document-class: TracePoint
#
# A class that provides the functionality of Kernel#set_trace_func in a
# nice Object-Oriented API.
#
# == Example
#
# We can use TracePoint to gather information specifically for exceptions:
#
#	    trace = TracePoint.new(:raise) do |tp|
#		p [tp.lineno, tp.event, tp.raised_exception]
#	    end
#	    #=> #<TracePoint:disabled>
#
#	    trace.enable
#	    #=> false
#
#	    0 / 0
#	    #=> [5, :raise, #<ZeroDivisionError: divided by 0>]
#
# == Events
#
# If you don't specify the type of events you want to listen for,
# TracePoint will include all available events.
#
# *Note* do not depend on current event set, as this list is subject to
# change. Instead, it is recommended you specify the type of events you
# want to use.
#
# To filter what is traced, you can pass any of the following as +events+:
#
# +:line+:: execute code on a new line
# +:class+:: start a class or module definition
# +:end+:: finish a class or module definition
# +:call+:: call a Ruby method
# +:return+:: return from a Ruby method
# +:c_call+:: call a C-language routine
# +:c_return+:: return from a C-language routine
# +:raise+:: raise an exception
# +:b_call+:: event hook at block entry
# +:b_return+:: event hook at block ending
# +:thread_begin+:: event hook at thread beginning
# +:thread_end+:: event hook at thread ending
# +:fiber_switch+:: event hook at fiber switch
# +:script_compiled+:: new Ruby code compiled (with +eval+, +load+ or +require+)
#
class TracePoint
  # call-seq:
  #	TracePoint.new(*events) { |obj| block }	    -> obj
  #
  # Returns a new TracePoint object, not enabled by default.
  #
  # Next, in order to activate the trace, you must use TracePoint#enable
  #
  #	trace = TracePoint.new(:call) do |tp|
  #	    p [tp.lineno, tp.defined_class, tp.method_id, tp.event]
  #	end
  #	#=> #<TracePoint:disabled>
  #
  #	trace.enable
  #	#=> false
  #
  #	puts "Hello, TracePoint!"
  #	# ...
  #	# [48, IRB::Notifier::AbstractNotifier, :printf, :call]
  #	# ...
  #
  # When you want to deactivate the trace, you must use TracePoint#disable
  #
  #	trace.disable
  #
  # See TracePoint@Events for possible events and more information.
  #
  # A block must be given, otherwise an ArgumentError is raised.
  #
  # If the trace method isn't included in the given events filter, a
  # RuntimeError is raised.
  #
  #	TracePoint.trace(:line) do |tp|
  #	    p tp.raised_exception
  #	end
  #	#=> RuntimeError: 'raised_exception' not supported by this event
  #
  # If the trace method is called outside block, a RuntimeError is raised.
  #
  #      TracePoint.trace(:line) do |tp|
  #        $tp = tp
  #      end
  #      $tp.lineno #=> access from outside (RuntimeError)
  #
  # Access from other threads is also forbidden.
  #
  def self.new(*events)
    Primitive.tracepoint_new_s(events)
  end

  #  call-seq:
  #    trace.inspect  -> string
  #
  #  Return a string containing a human-readable TracePoint
  #  status.
  def inspect
    Primitive.tracepoint_inspect
  end

  # call-seq:
  #	TracePoint.stat -> obj
  #
  #  Returns internal information of TracePoint.
  #
  #  The contents of the returned value are implementation specific.
  #  It may be changed in future.
  #
  #  This method is only for debugging TracePoint itself.
  def self.stat
    Primitive.tracepoint_stat_s
  end

  # Document-method: trace
  #
  # call-seq:
  #	TracePoint.trace(*events) { |obj| block }	-> obj
  #
  #  A convenience method for TracePoint.new, that activates the trace
  #  automatically.
  #
  #	    trace = TracePoint.trace(:call) { |tp| [tp.lineno, tp.event] }
  #	    #=> #<TracePoint:enabled>
  #
  #	    trace.enabled? #=> true
  #
  def self.trace(*events)
    Primitive.tracepoint_trace_s(events)
  end

  # call-seq:
  #    trace.enable(target: nil, target_line: nil, target_thread: nil)    -> true or false
  #    trace.enable(target: nil, target_line: nil, target_thread: nil) { block }  -> obj
  #
  # Activates the trace.
  #
  # Returns +true+ if trace was enabled.
  # Returns +false+ if trace was disabled.
  #
  #   trace.enabled?  #=> false
  #   trace.enable    #=> false (previous state)
  #                   #   trace is enabled
  #   trace.enabled?  #=> true
  #   trace.enable    #=> true (previous state)
  #                   #   trace is still enabled
  #
  # If a block is given, the trace will only be enabled within the scope of the
  # block.
  #
  #    trace.enabled?
  #    #=> false
  #
  #    trace.enable do
  #      trace.enabled?
  #      # only enabled for this block
  #    end
  #
  #    trace.enabled?
  #    #=> false
  #
  # +target+, +target_line+ and +target_thread+ parameters are used to
  # limit tracing only to specified code objects. +target+ should be a
  # code object for which RubyVM::InstructionSequence.of will return
  # an instruction sequence.
  #
  #    t = TracePoint.new(:line) { |tp| p tp }
  #
  #    def m1
  #      p 1
  #    end
  #
  #    def m2
  #      p 2
  #    end
  #
  #    t.enable(target: method(:m1))
  #
  #    m1
  #    # prints #<TracePoint:line test.rb:4 in `m1'>
  #    m2
  #    # prints nothing
  #
  # Note: You cannot access event hooks within the +enable+ block.
  #
  #    trace.enable { p tp.lineno }
  #    #=> RuntimeError: access from outside
  #
  def enable(target: nil, target_line: nil, target_thread: nil)
    Primitive.tracepoint_enable_m(target, target_line, target_thread)
  end

  # call-seq:
  #	trace.disable		-> true or false
  #	trace.disable { block } -> obj
  #
  # Deactivates the trace
  #
  # Return true if trace was enabled.
  # Return false if trace was disabled.
  #
  #	trace.enabled?	#=> true
  #	trace.disable	#=> true (previous status)
  #	trace.enabled?	#=> false
  #	trace.disable	#=> false
  #
  # If a block is given, the trace will only be disable within the scope of the
  # block.
  #
  #	trace.enabled?
  #	#=> true
  #
  #	trace.disable do
  #	    trace.enabled?
  #	    # only disabled for this block
  #	end
  #
  #	trace.enabled?
  #	#=> true
  #
  # Note: You cannot access event hooks within the block.
  #
  #	trace.disable { p tp.lineno }
  #	#=> RuntimeError: access from outside
  def disable
    Primitive.tracepoint_disable_m
  end

  # call-seq:
  #	trace.enabled?	    -> true or false
  #
  # The current status of the trace
  def enabled?
    Primitive.tracepoint_enabled_p
  end

  # Type of event
  #
  # See TracePoint@Events for more information.
  def event
    Primitive.tracepoint_attr_event
  end

  # Line number of the event
  def lineno
    Primitive.tracepoint_attr_lineno
  end

  # Path of the file being run
  def path
    Primitive.tracepoint_attr_path
  end

  # Return the parameters definition of the method or block that the
  # current hook belongs to. Format is the same as for Method#parameters
  def parameters
    Primitive.tracepoint_attr_parameters
  end

  # Return the name at the definition of the method being called
  def method_id
    Primitive.tracepoint_attr_method_id
  end

  # Return the called name of the method being called
  def callee_id
    Primitive.tracepoint_attr_callee_id
  end

  # Return class or module of the method being called.
  #
  #	class C; def foo; end; end
  # 	trace = TracePoint.new(:call) do |tp|
  # 	  p tp.defined_class #=> C
  # 	end.enable do
  # 	  C.new.foo
  # 	end
  #
  # If method is defined by a module, then that module is returned.
  #
  #	module M; def foo; end; end
  # 	class C; include M; end;
  # 	trace = TracePoint.new(:call) do |tp|
  # 	  p tp.defined_class #=> M
  # 	end.enable do
  # 	  C.new.foo
  # 	end
  #
  # <b>Note:</b> #defined_class returns singleton class.
  #
  # 6th block parameter of Kernel#set_trace_func passes original class
  # of attached by singleton class.
  #
  # <b>This is a difference between Kernel#set_trace_func and TracePoint.</b>
  #
  #	class C; def self.foo; end; end
  # 	trace = TracePoint.new(:call) do |tp|
  # 	  p tp.defined_class #=> #<Class:C>
  # 	end.enable do
  # 	  C.foo
  # 	end
  def defined_class
    Primitive.tracepoint_attr_defined_class
  end

  # Return the generated binding object from event
  def binding
    Primitive.tracepoint_attr_binding
  end

  # Return the trace object during event
  #
  # Same as TracePoint#binding:
  #	trace.binding.eval('self')
  def self
    Primitive.tracepoint_attr_self
  end

  #  Return value from +:return+, +c_return+, and +b_return+ event
  def return_value
    Primitive.tracepoint_attr_return_value
  end

  # Value from exception raised on the +:raise+ event
  def raised_exception
    Primitive.tracepoint_attr_raised_exception
  end

  # Compiled source code (String) on *eval methods on the +:script_compiled+ event.
  # If loaded from a file, it will return nil.
  def eval_script
    Primitive.tracepoint_attr_eval_script
  end

  # Compiled instruction sequence represented by a RubyVM::InstructionSequence instance
  # on the +:script_compiled+ event.
  #
  # Note that this method is MRI specific.
  def instruction_sequence
    Primitive.tracepoint_attr_instruction_sequence
  end
end
