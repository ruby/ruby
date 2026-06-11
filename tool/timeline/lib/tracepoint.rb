#!/usr/bin/env ruby
# frozen_string_literal: true

module RubyTimelineTool
  class TracePoint
    def initialize(name, where, vis_id, vis_ph, args: nil)
      @name = name
      @where = where
      @vis_id = vis_id
      @vis_ph = vis_ph
      @args = args || {}
    end

    attr_reader :name, :where, :vis_id, :vis_ph, :args
  end

  def self.tp(*args, **kwargs)
    TracePoint.new(*args, **kwargs)
  end

  def self.convert_arg(value, converter)
    if @converter.is_a?(Symbol) then
      value.send(@converter)
    elsif @converter.respond_to?(:call) then
      @converter.call(value)
    else
      raise "Unexpected converter #{@converter.inspect}"
    end
  end
end
