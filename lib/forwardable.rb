#
#   forwardable.rb - 
#   	$Release Version: 1.1$
#   	$Revision$
#   	by Keiju ISHITSUKA(keiju@ishitsuka.com)
#	original definition by delegator.rb
#       Revised by Daniel J. Berger with suggestions from Florian Gross.
#
#       Documentation by James Edward Gray II and Gavin Sinclair
#
# == Introduction
#
# This library allows you delegate method calls to an object, on a method by
# method basis.
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
# Forwardable can be used to setup delegation at the object level as well.
#
#    printer = String.new
#    printer.extend Forwardable              # prepare object for delegation
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
#   f = Foo.new
#   f.printf ...
#   f.gets
#   f.content_at(1)
#
# Also see the example at forwardable.rb.

module Forwardable
  FORWARDABLE_VERSION = "1.0.0"
  
  # Takes a hash as its argument.  The key is a symbol or an array of
  # symbols.  These symbols correspond to method names.  The value is
  # the accessor to which the methods will be delegated.
  #
  # :call-seq:
  #    delegate method => accessor
  #    delegate [method, method, ...] => accessor
  #
  def delegate(hash)
    hash.each{ |methods, accessor|
      methods = methods.to_s unless methods.respond_to?(:each)
      methods.each{ |method|
        def_instance_delegator(accessor, method)
      }
    }
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
  def def_instance_delegators(accessor, *methods)
    methods.delete("__send__")
    methods.delete("__id__")
    methods.each{ |method|
      def_instance_delegator(accessor, method)
    }
  end

  #
  # Defines a method _method_ which delegates to _obj_ (i.e. it calls
  # the method of the same name in _obj_).  If _new_name_ is
  # provided, it is used as the name for the delegate method.
  #
  def def_instance_delegator(accessor, method, ali = method)
    str = %Q{
      def #{ali}(*args, &block)
        #{accessor}.send(:#{method}, *args, &block)
      end
    }

    # If it's not a class or module, it's an instance
    begin
      module_eval(str)
    rescue
      instance_eval(str)
    end
  end

  alias def_delegators def_instance_delegators
  alias def_delegator def_instance_delegator
end

# compatibility
SingleForwardable = Forwardable
