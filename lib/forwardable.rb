# = forwardable - Support for the Delegation Pattern
#
#    $Release Version: 1.1$
#    $Revision$
#    $Date$
#    by Keiju ISHITSUKA(keiju@ishitsuka.com)
#
#    Documentation by James Edward Gray II and Gavin Sinclair
#
# == Introduction
#
# This library allows you delegate method calls to an object, on a method by
# method basis.  You can use Forwardable to setup this delegation at the class
# level, or SingleForwardable to handle it at the object level.
#
# == Notes
#
# Be advised, RDoc will not detect delegated methods.
#
# <b>forwardable.rb provides single-method delegation via the
# def_delegator() and def_delegators() methods.  For full-class
# delegation via DelegateClass(), see delegate.rb.</b>
#
# == Examples
#
# === Forwardable
#
# Forwardable makes building a new class based on existing work, with a proper
# interface, almost trivial.  We want to rely on what has come before obviously,
# but with delegation we can take just the methods we need and even rename them
# as appropriate.  In many cases this is preferable to inheritance, which gives
# us the entire old interface, even if much of it isn't needed.
#
#   class Queue
#     extend Forwardable
#     
#     def initialize
#       @q = [ ]    # prepare delegate object
#     end
#     
#     # setup preferred interface, enq() and deq()...
#     def_delegator :@q, :push, :enq
#     def_delegator :@q, :shift, :deq
#     
#     # support some general Array methods that fit Queues well
#     def_delegators :@q, :clear, :first, :push, :shift, :size
#   end
# 
#   q = Queue.new
#   q.enq 1, 2, 3, 4, 5
#   q.push 6
# 
#   q.shift    # => 1
#   while q.size > 0
#     puts q.deq
#   end
# 
#   q.enq "Ruby", "Perl", "Python"
#   puts q.first
#   q.clear
#   puts q.first
#
# <i>Prints:</i>
#
#   2
#   3
#   4
#   5
#   6
#   Ruby
#   nil
#
# === SingleForwardable
#
#    printer = String.new
#    printer.extend SingleForwardable        # prepare object for delegation
#    printer.def_delegator "STDOUT", "puts"  # add delegation for STDOUT.puts()
#    printer.puts "Howdy!"
#
# <i>Prints:</i>
#
#    Howdy!

#
# The Forwardable module provides delegation of specified
# methods to a designated object, using the methods #def_delegator
# and #def_delegators.
#
# For example, say you have a class RecordCollection which
# contains an array <tt>@records</tt>.  You could provide the lookup method
# #record_number(), which simply calls #[] on the <tt>@records</tt>
# array, like this:
#
#   class RecordCollection
#     extend Forwardable
#     def_delegator :@records, :[], :record_number
#   end
#
# Further, if you wish to provide the methods #size, #<<, and #map,
# all of which delegate to @records, this is how you can do it:
#
#   class RecordCollection
#     # extend Forwardable, but we did that above
#     def_delegators :@records, :size, :<<, :map
#   end
#
# Also see the example at forwardable.rb.
#
module Forwardable

  @debug = nil
  class<<self
    # force Forwardable to show up in stack backtraces of delegated methods
    attr_accessor :debug
  end

  #
  # Shortcut for defining multiple delegator methods, but with no
  # provision for using a different name.  The following two code
  # samples have the same effect:
  #
  #   def_delegators :@records, :size, :<<, :map
  #
  #   def_delegator :@records, :size
  #   def_delegator :@records, :<<
  #   def_delegator :@records, :map
  #
  # See the examples at Forwardable and forwardable.rb.
  #
  def def_instance_delegators(accessor, *methods)
    for method in methods
      def_instance_delegator(accessor, method)
    end
  end

  #
  # Defines a method _method_ which delegates to _obj_ (i.e. it calls
  # the method of the same name in _obj_).  If _new_name_ is
  # provided, it is used as the name for the delegate method.
  #
  # See the examples at Forwardable and forwardable.rb.
  #
  def def_instance_delegator(accessor, method, ali = method)
    accessor = accessor.id2name if accessor.kind_of?(Integer)
    method = method.id2name if method.kind_of?(Integer)
    ali = ali.id2name if ali.kind_of?(Integer)

    module_eval(<<-EOS, "(__FORWARDABLE__)", 1)
      def #{ali}(*args, &block)
	begin
	  #{accessor}.__send__(:#{method}, *args, &block)
	rescue Exception
	  $@.delete_if{|s| /^\\(__FORWARDABLE__\\):/ =~ s} unless Forwardable::debug
	  Kernel::raise
	end
      end
    EOS
  end

  alias def_delegators def_instance_delegators
  alias def_delegator def_instance_delegator
end

#
# The SingleForwardable module provides delegation of specified
# methods to a designated object, using the methods #def_delegator
# and #def_delegators.  This module is similar to Forwardable, but it works on
# objects themselves, instead of their defining classes.
#
# Also see the example at forwardable.rb.
#
module SingleForwardable
  #
  # Shortcut for defining multiple delegator methods, but with no
  # provision for using a different name.  The following two code
  # samples have the same effect:
  #
  #   single_forwardable.def_delegators :@records, :size, :<<, :map
  #
  #   single_forwardable.def_delegator :@records, :size
  #   single_forwardable.def_delegator :@records, :<<
  #   single_forwardable.def_delegator :@records, :map
  #
  # See the example at forwardable.rb.
  #
  def def_singleton_delegators(accessor, *methods)
    for method in methods
      def_singleton_delegator(accessor, method)
    end
  end

  #
  # Defines a method _method_ which delegates to _obj_ (i.e. it calls
  # the method of the same name in _obj_).  If _new_name_ is
  # provided, it is used as the name for the delegate method.
  #
  # See the example at forwardable.rb.
  #
  def def_singleton_delegator(accessor, method, ali = method)
    accessor = accessor.id2name if accessor.kind_of?(Integer)
    method = method.id2name if method.kind_of?(Integer)
    ali = ali.id2name if ali.kind_of?(Integer)

    instance_eval(<<-EOS, "(__FORWARDABLE__)", 1)
       def #{ali}(*args, &block)
	 begin
	   #{accessor}.__send__(:#{method}, *args,&block)
	 rescue Exception
	   $@.delete_if{|s| /^\\(__FORWARDABLE__\\):/ =~ s} unless Forwardable::debug
	   Kernel::raise
	 end
       end
    EOS
  end

  alias def_delegators def_singleton_delegators
  alias def_delegator def_singleton_delegator
end
