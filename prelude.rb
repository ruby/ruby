class Binding
  # :nodoc:
  def irb
    force_activate 'irb'
    require 'irb'
    irb
  end

  # suppress redefinition warning
  alias irb irb # :nodoc:

  private def force_activate(gem)
    return if !defined?(Bundler) || Gem.loaded_specs.key?(gem)

    Bundler.reset!

    ui = Bundler::UI::Shell.new
    ui.level = "silent"
    Bundler.ui = ui

    @builder = Bundler::Dsl.new
    if Bundler.definition.gemfiles.empty? # bundler/inline
      Bundler.definition.locked_gems.specs.each{|spec| @builder.gem spec.name, spec.version.to_s }
    else
      Bundler.definition.gemfiles.each{|gemfile| @builder.eval_gemfile(gemfile) }
    end
    @builder.gem gem

    definition = @builder.to_definition(nil, true)
    definition.validate_runtime!
    Bundler::Definition.no_lock = true
    Bundler::Runtime.new(nil, definition).setup
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
