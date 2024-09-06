class Binding
  # :nodoc:
  def irb
    begin
      require 'irb'
    rescue LoadError
      force_require "irb" if defined?(Bundler)
    end
    irb
  end

  # suppress redefinition warning
  alias irb irb # :nodoc:

  private def force_require(gem)
    gemspecs = (Gem::Specification.dirs + [Gem.default_specifications_dir]).map{|d|
                Dir.glob("#{d}/#{gem}*.gemspec").reverse
              }.flatten
    if gemspecs.empty?
      false
    else
      gemspec = Gem::Specification.load(gemspecs[0])
      gemspec.dependencies.each{|dep| force_require dep.name }
      gemspec.activate
      require gem.gsub("-", "/")
    end
  end
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
