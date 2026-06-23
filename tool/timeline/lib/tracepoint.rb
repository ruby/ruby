#!/usr/bin/env ruby
# frozen_string_literal: true

module RubyTimelineTool
  class TracePoint
    def initialize(probe_name, where, vis_name, vis_ph, args: nil)
      @probe_name = probe_name
      @where = where
      @vis_name = vis_name
      @vis_ph = vis_ph
      @args = args || {}
    end

    attr_reader :probe_name, :where, :vis_name, :vis_ph, :args
  end

  def self.tp(*args, **kwargs)
    TracePoint.new(*args, **kwargs)
  end
end
