class Binding
  # :nodoc:
  def irb
    require 'irb'
    irb
  end

  # suppress redefinition warning
  alias irb irb # :nodoc:
end

module Kernel
  def pp(*objs)
    require 'pp'
    pp(*objs)
  end

  # suppress redefinition warning
  alias pp pp # :nodoc:

  private :pp
end

autoload :Set, 'set'

module Enumerable
  # Makes a set from the enumerable object with given arguments.
  def to_set(klass = Set, *args, &block)
    klass.new(self, *args, &block)
  end unless instance_methods.include?(:to_set) # RJIT could already load this from builtin prelude
end
