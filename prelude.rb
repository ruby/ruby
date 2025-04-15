class Binding
  # :nodoc:
  def irb(...)
    begin
      require 'irb'
    rescue LoadError, Gem::LoadError
      Gem::BUNDLED_GEMS.force_activate 'irb'
      require 'irb'
    end
    irb(...)
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

autoload :SortedSet, 'set/sorted_set'

module Enumerable
  # Makes a set from the enumerable object with given arguments.
  def to_set(klass = Set, *args, &block)
    klass.new(self, *args, &block)
  end
end
