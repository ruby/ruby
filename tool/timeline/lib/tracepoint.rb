#!/usr/bin/env ruby
# frozen_string_literal: true

module RubyTimelineTool
  class TracePoint
    def initialize(probe, where, vis_id, vis_ph, args: nil)
      @probe = probe
      @where = where
      @vis_id = vis_id
      @vis_ph = vis_ph
      @args = args || {}
    end

    attr_reader :probe, :where, :vis_id, :vis_ph, :args
  end

  def self.tp(*args, **kwargs)
    TracePoint.new(*args, **kwargs)
  end
end
