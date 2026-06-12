#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'tracepoint.rb'
require_relative 'converter_defs.rb'

module RubyTimelineTool
  # All USDT trace points.
  USDT_DEFS = {
    'default' => [
      tp('gc__mark__begin',   "default",  'gc_mark',          'B'),
      tp('gc__mark__end',     "default",  'gc_mark',          'E'),
      tp('gc__sweep__begin',  "default",  'gc_sweep',         'B'),
      tp('gc__sweep__end',    "default",  'gc_sweep',         'E'),
      tp('gc__enter',         "default",  'GCEnterExit',      'B', args: {event: GCEnterEvent}),
      tp('gc__exit',          "default",  'GCEnterExit',      'E', args: {event: GCEnterEvent}),
    ],
    'obj_new' => [
      tp('gc__obj_new',       "ruby",     'gc_obj_new',       'i', args: {obj: :to_i, flags: RubyFlags}), # TODO: flags converter
    ],
    'obj_free' => [
      tp('gc__obj_free',      "ruby",     'gc_obj_free',      'i', args: {obj: :to_i, flags: RubyFlags}), # TODO: flags converter
    ],
    'xmalloc' => [
      tp('gc__xmalloc',       "ruby",     'gc_xmalloc',       'i', args: {n: :to_i, size: :to_i}),
      tp('gc__xcalloc',       "ruby",     'gc_xcalloc',       'i', args: {n: :to_i, size: :to_i}),
    ],
    'xfree' => [
      tp('gc__xfree',         "ruby",     'gc_xfree',         'i', args: {obj: :to_i, size: :to_i}),
    ],
    'gvl' => [
      tp('gvl__acquire',      "ruby",     'GVL',              'B'),
      tp('gvl__release',      "ruby",     'GVL',              'E'),
    ],
    'rts' => [ # ractor.thread.sched
      tp('rts__set_running',  "ruby",     'rts_set_running',  'i', args: {sched: :to_i, old_thread: :to_i, new_thread: :to_i}),
    ]
  }

  # The default groups are enabled by default
  DEFAULT_GROUPS = ['default']
end
