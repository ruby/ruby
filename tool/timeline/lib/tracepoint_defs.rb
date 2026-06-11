#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'tracepoint.rb'

module RubyTimelineTool
  USDT_SET = TracePointSet.new do
    group('default') do
      tp('gc__mark__begin',   "default",  'gc_mark',          'B')
      tp('gc__mark__end',     "default",  'gc_mark',          'E')
      tp('gc__sweep__begin',  "default",  'gc_sweep',         'B')
      tp('gc__sweep__end',    "default",  'gc_sweep',         'E')
      tp('gc__enter',         "default",  'GCEnterExit',      'B', {event: :to_i})
      tp('gc__exit',          "default",  'GCEnterExit',      'E', {event: :to_i})
    end
    
    group('obj_new') do
      ['gc__obj_new',       "ruby",     'gc_obj_new',       'i',  2],
    end

    group('obj_free') do
      ['gc__obj_free',      "ruby",     'gc_obj_free',      'i',  2],
    end

    group('xmalloc') do
      ['gc__xmalloc',       "ruby",     'gc_xmalloc',       'i',  2],
      ['gc__xcalloc',       "ruby",     'gc_xcalloc',       'i',  2],
    end

    group('xfree') do
      ['gc__xfree',         "ruby",     'gc_xfree',         'i',  2],
    end

    group('gvl') do
      ['gvl__acquire',      "ruby",     'GVL',              'B',  0],
      ['gvl__release',      "ruby",     'GVL',              'E',  0],
    end

    group('rts') do
      ['rts__set_running',  "ruby",     'rts_set_running',  'i',  3],
    end

  end
end
