#
#   forwardable.rb - 
#   	$Release Version: 1.1$
#   	$Revision$
#   	$Date$
#   	by Keiju ISHITSUKA(keiju@ishitsuka.com)
#	original definition by delegator.rb
# --
# Usage:
#
#   class Foo
#     extend Forwardable
#
#     def_delegators("@out", "printf", "print")
#     def_delegators(:@in, :gets)
#     def_delegator(:@contents, :[], "content_at")
#   end
#   f = Foo.new
#   f.printf ...
#   f.gets
#   f.content_at(1)
#
#   g = Goo.new
#   g.extend SingleForwardable
#   g.def_delegator("@out", :puts)
#   g.puts ...
#
#

module Forwardable

  @debug = nil
  class<<self
    attr_accessor :debug
  end

  def def_instance_delegators(accessor, *methods)
    for method in methods
      def_instance_delegator(accessor, method)
    end
  end

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

module SingleForwardable
  def def_singleton_delegators(accessor, *methods)
    for method in methods
      def_singleton_delegator(accessor, method)
    end
  end

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




