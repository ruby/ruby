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

  ENGINE = YAML::EngineManager.new
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

module Syck
  ENGINE = YAML::ENGINE
end

module Psych
  ENGINE = YAML::ENGINE
end

YAML::ENGINE.yamler = engine
