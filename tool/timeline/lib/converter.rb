# frozen_string_literal: true

module RubyTimelineTool
  class Converter
    def convert_arg(_raw_value)
      raise 'Not implemented'
    end
  end

  class EnumConverter < Converter
    def initialize(hash)
      super()
      @hash = hash
      @ihash = hash.invert
    end

    def convert_arg(raw_value)
      value = raw_value.to_i
      @ihash[value]
    end
  end

  class FlagsConverter < Converter
    def initialize(hash)
      super()
      @hash = hash
    end

    def convert_arg(raw_value)
      value = raw_value.to_i
      # Output {foo: true, bar: false, ...}
      @hash.transform_values do |bit_value|
        (value & bit_value) != 0
      end
    end
  end

  def self.convert_arg(raw_value, converter)
    case
    when converter.is_a?(Converter)
      converter.convert_arg(raw_value)
    when converter.is_a?(Symbol)
      raw_value.send(converter)
    when converter.respond_to?(:call)
      converter.call(raw_value)
    else
      raise "Unexpected converter #{@converter.inspect}"
    end
  end
end
