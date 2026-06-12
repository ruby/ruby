#!/usr/bin/env ruby
# frozen_string_literal: true

module RubyTimelineTool
  class Converter
    def convert_arg(value)
      raise "Not implemented"
    end
  end

  class EnumConverter < Converter
    def initialize(hash)
      @hash = hash
      @ihash = hash.invert
    end

    def convert_arg(value)
      value_i = value.to_i
      @ihash[value_i]
    end
  end

  class FlagsConverter < Converter
    def initialize(hash)
      @hash = hash
    end

    def convert_arg(value)
      value_i = value.to_i
      # Output {foo: true, bar: false, ...}
      @hash.transform_values do |bit_value|
        (value & bit_value) != 0
      end
    end
  end

  def self.convert_arg(value, converter)
    case
    when converter.is_a?(Converter) then
      converter.convert_arg(value)
    when converter.is_a?(Symbol) then
      value.send(converter)
    when converter.respond_to?(:call) then
      converter.call(value)
    else
      raise "Unexpected converter #{@converter.inspect}"
    end
  end
end
