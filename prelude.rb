class Binding
  # :nodoc:
  def irb(...)
    suppress = Thread.current[:__bundled_gems_warning_suppression]
    Thread.current[:__bundled_gems_warning_suppression] = ['reline', 'rdoc']

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
