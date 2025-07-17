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

module Enumerable
  # Makes a set from the enumerable object with given arguments.
  # Passing arguments to this method is deprecated.
  def to_set(*args, &block)
    klass = if args.empty?
      Set
    else
      warn "passing arguments to Enumerable#to_set is deprecated", uplevel: 1
      args.shift
    end
    klass.new(self, *args, &block)
  end
end
