# frozen_string_literal: true

require_relative 'tracepoint'
require_relative 'converter_defs'

module RubyTimelineTool
  # All USDT trace points.
  #
  # It maps each group to an array of trace points.  The `default` group is always enabled, and
  # other groups can be enabled using the `-g` command line option of `capture.rb`.
  #
  # `tp(...)` defines a trace point.  It has four compulsory arguments.
  #
  # 1.  The USDT probe name.  It is the `xxx` in `probe xxx()` in `probes.d`, and it is also the
  #     `Name:` field of the output of `readelf -n`.  The `capture.rb` tool assumes the "provider
  #     (the `Provider:` field of `readelf -n`) of the USDT is `ruby`, and we don't need to specify
  #     it here.
  # 2.  The place the probe is defined.  Possible values are:
  #     -   `ruby`: It is part of the Ruby runtime, and will always be compiled into the `ruby`
  #         executable.
  #     -   `default`: It is part of the default GC (`default.c`).  It will be compiled into the
  #         `ruby` executable and the default GC module if modular GC is enabled.
  # 3.  The event name in the output timeline.
  # 4.  The event type, as specified by the Trace Event Format.  Common types include
  #     -   'B' and 'E': The beginning and the end of a duration event.
  #     -   'i': An instant event.
  #     -   'c': A counter event.
  #
  #     It can also have a special value 'meta' (not specified in the Trace Event Format) which
  #     means it will not be added to the output JSON file, but will still be available for
  #     `visualize.rb` for post-processing.
  #
  #     For more information about the Trace Event Format, see:
  #     https://docs.google.com/document/d/1CvAClvFfyA5R-PhYUmn5OOQtYMH4h6I0nSsKchNAySU/edit?usp=sharing
  #
  # `tp(...)` also has some optional keyword argument.
  #
  # -   `args`: It is used by the `capture.rb` script to set up the arguments of the USDT probes,
  #     and used by `visualize.rb` to convert the argument values from string (read from the log) to
  #     JSON values.  It has the form:
  #
  #     ```ruby
  #     args: {arg1: converter1, arg2: converter2, ...}
  #     ```
  #
  #     The order of the key-value pairs must match the order of the arguments of the USDT trace
  #     points (as defined in `probes.d`).
  #
  #     Each converter can be one of the following
  #
  #     -   An instance of `Converter`.
  #     -   A symbol, such as `:to_i`, to be sent to the argument string.
  #     -   An object that responds to `call`.
  #
  #     There are some converters defined in `converter_defs.rb`.
  USDT_DEFS = {
    'default' => [
      # The default group visualizes the duration of each GC, each marking and each sweeping event.
      tp('gc__mark__begin',   'default',  'gc_mark',          'B'),
      tp('gc__mark__end',     'default',  'gc_mark',          'E'),
      tp('gc__sweep__begin',  'default',  'gc_sweep',         'B'),
      tp('gc__sweep__end',    'default',  'gc_sweep',         'E'),
      tp('gc__enter',         'default',  'GCEnterExit',      'B', args: {event: GCEnterEvent}),
      tp('gc__exit',          'default',  'GCEnterExit',      'E', args: {event: GCEnterEvent}),
    ].freeze,
    'mark_details' => [
      # This group collects more detals of marking events, such as the number of objects visited.
      tp('gc__mark_stacked_objects', 'default', 'gc_mark_stacked_objects', 'meta', args: {popped_count: :to_i}),
    ].freeze,
    'sweep_details' => [
      # This group collects more detals of sweeping events, such as the number of objects swept.
      tp('gc__sweep_page',    'default',  'gc_sweep_page',    'i', args: {slot_size: :to_i, final_slots: :to_i, freed_slots: :to_i, empty_slots: :to_i}),
    ].freeze,
    'obj_new' => [
      # This group traces the creation of GC-managed objects.
      tp('gc__obj_new',       'ruby',     'gc_obj_new',       'i', args: {obj: :to_i, flags: RubyFlags}),
    ].freeze,
    'obj_free' => [
      # This group traces the invocation of `rb_gc_obj_free` which finalizes the objects when they are swept.
      tp('gc__obj_free',      'ruby',     'gc_obj_free',      'i', args: {obj: :to_i, flags: RubyFlags}),
    ].freeze,
    'xmalloc' => [
      # This group traces the invocation of `xmalloc` and `xcalloc`.
      tp('gc__xmalloc',       'ruby',     'gc_xmalloc',       'i', args: {n: :to_i, size: :to_i}),
      tp('gc__xcalloc',       'ruby',     'gc_xcalloc',       'i', args: {n: :to_i, size: :to_i}),
    ].freeze,
    'xfree' => [
      # This group traces the invocation of `xfree`.
      tp('gc__xfree',         'ruby',     'gc_xfree',         'i', args: {obj: :to_i, size: :to_i}),
    ].freeze,
    'gvl' => [
      # This group visualizes the durations in which a thread holds the global VM lock.
      tp('gvl__acquire',      'ruby',     'GVL',              'B'),
      tp('gvl__release',      'ruby',     'GVL',              'E'),
    ].freeze,
    'rts' => [
      # This group visualizes the event where a thread is scheduled on or off a Ractor.
      # "RTS" stands for `ractor.thread.sched`.
      tp('rts__set_running',  'ruby',     'rts_set_running',  'i', args: {sched: :to_i, old_thread: :to_i, new_thread: :to_i}),
    ].freeze
  }.freeze

  # The default groups are enabled by default
  DEFAULT_GROUPS = ['default'].freeze
end
