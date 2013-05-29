# YAML Ain't Markup Language
#
# This module provides a Ruby interface for data serialization in YAML format.
#
# You can choose from one of two YAML engines that ship with Ruby 1.9. By
# default Psych is used but the old unmaintained Syck may chosen.
#
# == Usage
#
# Working with YAML can be very simple, for example:
#
#     require 'yaml' # STEP ONE, REQUIRE YAML!
#     # Parse a YAML string
#     YAML.load("--- foo") #=> "foo"
#
#     # Emit some YAML
#     YAML.dump("foo")     # => "--- foo\n...\n"
#     { :a => 'b'}.to_yaml  # => "---\n:a: b\n"
#
# == Security
#
# Do not use YAML to load untrusted data. Doing so is unsafe and could allow
# malicious input to execute arbitrary code inside your application. Please see
# doc/security.rdoc for more information.
#
# == Syck
#
# Syck was the original for YAML implementation in Ruby's standard library
# developed by why the lucky stiff.
#
# If you prefer, you can still use Syck by changing the YAML::ENGINE like so:
#
#   YAML::ENGINE.yamler = 'syck'
#   # switch back to the default Psych
#   YAML::ENGINE.yamler = 'psych'
#
# In older Ruby versions, ie. <= 1.9, Syck is still provided, however it was
# completely removed with the release of Ruby 2.0.0.
#
# == More info
#
# For more advanced details on the implementation see Psych, and also check out
# http://yaml.org for spec details and other helpful information.
module YAML
  class EngineManager # :nodoc:
    attr_reader :yamler

    def initialize
      @yamler = nil
    end

    def syck?
      'syck' == @yamler
    end

    def yamler= engine
      raise(ArgumentError, "bad engine") unless %w{syck psych}.include?(engine)

      require engine unless (engine == 'syck' ? Syck : Psych).const_defined?(:VERSION)

      Object.class_eval <<-eorb, __FILE__, __LINE__ + 1
        remove_const 'YAML'
        YAML = #{engine.capitalize}
        remove_method :to_yaml
        alias :to_yaml :#{engine}_to_yaml
      eorb

      @yamler = engine
      engine
    end
  end

  ##
  # Allows changing the current YAML engine.  See YAML for details.

  ENGINE = YAML::EngineManager.new # :nodoc:
end

if defined?(Psych)
  engine = 'psych'
elsif defined?(Syck)
  engine = 'syck'
else
  begin
    require 'psych'
    engine = 'psych'
  rescue LoadError
    warn "#{caller[0]}:"
    warn "It seems your ruby installation is missing psych (for YAML output)."
    warn "To eliminate this warning, please install libyaml and reinstall your ruby."
    require 'syck'
    engine = 'syck'
  end
end

module Syck # :nodoc:
  ENGINE = YAML::ENGINE
end

module Psych # :nodoc:
  ENGINE = YAML::ENGINE
end

YAML::ENGINE.yamler = engine
