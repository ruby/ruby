##
# The YAML module allows you to use one of the two YAML engines that ship with
# ruby.  By default Psych is used but the old and unmaintained Syck may be
# chosen.

begin
  require 'psych'
rescue LoadError
  warn "#{caller[0]}:"
  warn "It seems your ruby installation is missing psych (for YAML output)."
  warn "To eliminate this warning, please install libyaml and reinstall your ruby."
  raise
end

module Psych
  class EngineManager
    # Returns the YAML engine in use.
    #
    # By default Psych is used but the old and unmaintained Syck may be chosen.
    #
    # See #yamler= for more information.
    attr_reader :yamler

    def initialize # :nodoc:
      @yamler = 'psych'
    end

    def syck? # :nodoc:
      false
    end

    # By default Psych is used but the old and unmaintained Syck may be chosen.
    #
    # After installing the 'syck' gem, you can set the YAML engine to syck:
    #
    #   YAML::ENGINE.yamler = 'syck'
    #
    # To set the YAML engine back to psych:
    #
    #   YAML::ENGINE.yamler = 'psych'
    def yamler= engine
      case engine
      when 'syck' then warn "syck has been removed"
      when 'psych' then @yamler = 'psych'
      else
        raise(ArgumentError, "bad engine")
      end

      engine
    end
  end

  ENGINE = EngineManager.new # :nodoc:
end

YAML = Psych
