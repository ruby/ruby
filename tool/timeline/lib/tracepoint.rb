#!/usr/bin/env ruby
# frozen_string_literal: true

module RubyTimelineTool
  class TracePointArg
    def initialize(name, converter)
      @name = name
      @converter = converter
    end

    def convert(value)
      if @converter.is_a?(Symbol) then
        value.send(@converter)
      elsif @converter.respond_to?(:call) then
        @converter.call(value)
      else
        raise "Unexpected converter #{@converter.inspect}"
      end
    end
  end

  class TracePoint
    def initialize(name, where, vis_id, vis_ph, &block)
      @name = name
      @where = where
      @vis_id = vis_id
      @vis_ph = vis_ph
      @args = []

      instance_eval(&block)
    end

    attr_reader :name, :where, :vis_id, :vis_ph, :args

    def arg(name, converter: nil)
      if block_given?
        converter = block
      elsif converter.nil?
        raise "Either provide a converter or a block"
      end
      a = TracePointArg

    end
  end

  class TracePointGroup
    def initialize(name)
      @name = name
      @trace_points = []
    end

    attr_reader :name, :trace_points

    def tp(*args, **kwargs)
      @trace_points << TracePoint.new(*args, **kwargs)
    end
  end

  class TracePointSet
    def initialize(&block)
      @groups = []
      instance_eval(&block)
    end

    attr_reader :groups

    def group(name, &block)
      group = TracePointGroup.new(name)
      group.instance_eval(&block)
      @groups << group
    end
  end
end
