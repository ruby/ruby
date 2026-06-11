#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "lib/tracepoint_defs.rb"

puts RubyTimelineTool::USDT_SET

RubyTimelineTool::USDT_SET.groups.each do |group|
  puts "Group: #{group.name}"
  group.trace_points.each do |tp|
    puts "  Trace point: #{tp.name} @ #{tp.where} -> #{tp.vis_id}:#{tp.vis_ph}"
    puts "    ARGS: #{tp.args}"
    tp.args.each do |name, converter|
      puts "    #{name}: #{converter}"
    end
  end
end
