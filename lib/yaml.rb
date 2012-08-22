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
  class EngineManager # :nodoc:
    attr_reader :yamler

    def initialize
      @yamler = 'psych'
    end

    def syck?
      false
    end

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
