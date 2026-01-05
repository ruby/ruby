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
  # :stopdoc:
  def pp(*objs)
    require 'pp'
    pp(*objs)
  end

  # suppress redefinition warning
  alias pp pp

  private :pp
  # :startdoc:
end

module Enumerable
  # Makes a set from the enumerable object with given arguments.
  def to_set(&block)
    Set.new(self, &block)
  end
end
