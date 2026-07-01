#!/usr/bin/env ruby
# frozen_string_literal: true

module RubyTimelineTool
  class TracePoint
    def initialize(probe_name, where, vis_name, ph, args: nil, visualize: true)
      @probe_name = probe_name
      @where = where
      @vis_name = vis_name
      @ph = ph
      @args = args || {}
      @visualize = visualize
    end

    attr_reader :probe_name, :where, :vis_name, :ph, :args, :visualize
  end

  def self.tp(*args, **kwargs)
    TracePoint.new(*args, **kwargs)
  end
end
