######################################################################
# This file is imported from the rubygems project.
# DO NOT make modifications in this repo. They _will_ be reverted!
# File a patch instead and assign it to Ryan Davis or Eric Hodel.
######################################################################

##
# Provides a single method +deprecate+ to be used to declare when
# something is going away.
#
#     class Legacy
#       def self.klass_method
#         # ...
#       end
#
#       def instance_method
#         # ...
#       end
#
#       extend Deprecate
#       deprecate :instance_method, "X.z", 2011, 4
#
#       class << self
#         extend Deprecate
#         deprecate :klass_method, :none, 2011, 4
#       end
#     end

module Deprecate

  def self.skip # :nodoc:
    @skip ||= false
  end

  def self.skip= v # :nodoc:
    @skip = v
  end

  ##
  # Temporarily turn off warnings. Intended for tests only.

  def skip_during
    Deprecate.skip, original = true, Deprecate.skip
    yield
  ensure
    Deprecate.skip = original
  end

  ##
  # Simple deprecation method that deprecates +name+ by wrapping it up
  # in a dummy method. It warns on each call to the dummy method
  # telling the user of +repl+ (unless +repl+ is :none) and the
  # year/month that it is planned to go away.

  def deprecate name, repl, year, month
    class_eval {
      old = "_deprecated_#{name}"
      alias_method old, name
      define_method name do |*args, &block| # TODO: really works on 1.8.7?
        klass = self.kind_of? Module
        target = klass ? "#{self}." : "#{self.class}#"
        msg = [ "NOTE: #{target}#{name} is deprecated",
                repl == :none ? " with no replacement" : ", use #{repl}",
                ". It will be removed on or after %4d-%02d-01." % [year, month],
                "\n#{target}#{name} called from #{Gem.location_of_caller.join(":")}",
              ]
        warn "#{msg.join}." unless Deprecate.skip
        send old, *args, &block
      end
    }
  end

  module_function :deprecate, :skip_during
end
