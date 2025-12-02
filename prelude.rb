class Binding
  # :nodoc:
  def irb(...)
    suppress = Thread.current[:__bundled_gems_warning_suppression]
    Thread.current[:__bundled_gems_warning_suppression] = ['irb', 'reline', 'rdoc']

    begin
      require 'irb'
    rescue LoadError, Gem::LoadError
      Gem::BUNDLED_GEMS.force_activate 'irb'
      require 'irb'
    end
    irb(...)
  ensure
    Thread.current[:__bundled_gems_warning_suppression] = suppress
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
