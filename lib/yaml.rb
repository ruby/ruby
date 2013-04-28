##
# The YAML module is an alias of Psych, the YAML engine for ruby.

begin
  require 'psych'
rescue LoadError
  warn "#{caller[0]}:"
  warn "It seems your ruby installation is missing psych (for YAML output)."
  warn "To eliminate this warning, please install libyaml and reinstall your ruby."
  raise
end

YAML = Psych

module Psych # :nodoc:
  # For compatibility, deprecated
  class EngineManager
    attr_reader :yamler # :nodoc:

    def initialize # :nodoc:
      @yamler = 'psych'
    end

    def syck? # :nodoc:
      false
    end

    # Psych is now always used and this method has no effect.
    #
    # This method is still present for compatibility.
    #
    # You may still use the Syck engine by installing
    # the 'syck' gem and using the Syck constant.
    def yamler= engine
      case engine
      when 'syck' then warn "syck has been removed, psych is used instead"
      when 'psych' then @yamler = 'psych'
      else
        raise(ArgumentError, "bad engine")
      end

      engine
    end
  end

  ENGINE = EngineManager.new # :nodoc:
end

# YAML Ain't Markup Language
#
# This module provides a Ruby interface for data serialization in YAML format.
#
# The underlying implementation is now always the libyaml wrapper Psych.
#
# See Psych::EngineManager#yamler= for details on using Syck.
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
# Do not use YAML to load untrusted data. Doing so is unsafe and could allow
# malicious input to execute arbitrary code inside your application. Please see
# doc/security.rdoc for more information.
#
# For more advanced details on the implementation see Psych, and also check out
# http://yaml.org for spec details and other helpful information.
module YAML
end
