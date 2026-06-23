#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'converter.rb'

module RubyTimelineTool
  # Keep in sync with `enum gc_enter_event` in `gc/default/default.c`.
  GCEnterEvent = EnumConverter.new({
    :start        => 0,
    :continue     => 1,
    :rest         => 2,
    :finalizer    => 3,
  })

  # Keep in sync with `enum ruby_value_type` in `include/ruby/internal/value_type.h`.
  RubyBuiltinType = EnumConverter.new({
    :RUBY_T_NONE     => 0x00, # /**< Non-object (swept etc.) */:
    :RUBY_T_OBJECT   => 0x01, # /**< @see struct ::RObject */
    :RUBY_T_CLASS    => 0x02, # /**< @see struct ::RClass and ::rb_cClass */
    :RUBY_T_MODULE   => 0x03, # /**< @see struct ::RClass and ::rb_cModule */
    :RUBY_T_FLOAT    => 0x04, # /**< @see struct ::RFloat */
    :RUBY_T_STRING   => 0x05, # /**< @see struct ::RString */
    :RUBY_T_REGEXP   => 0x06, # /**< @see struct ::RRegexp */
    :RUBY_T_ARRAY    => 0x07, # /**< @see struct ::RArray */
    :RUBY_T_HASH     => 0x08, # /**< @see struct ::RHash */
    :RUBY_T_STRUCT   => 0x09, # /**< @see struct ::RStruct */
    :RUBY_T_BIGNUM   => 0x0a, # /**< @see struct ::RBignum */
    :RUBY_T_FILE     => 0x0b, # /**< @see struct ::RFile */
    :RUBY_T_DATA     => 0x0c, # /**< @see struct ::RTypedData */
    :RUBY_T_MATCH    => 0x0d, # /**< @see struct ::RMatch */
    :RUBY_T_COMPLEX  => 0x0e, # /**< @see struct ::RComplex */
    :RUBY_T_RATIONAL => 0x0f, # /**< @see struct ::RRational */:
    :RUBY_T_NIL      => 0x11, # /**< @see ::RUBY_Qnil */
    :RUBY_T_TRUE     => 0x12, # /**< @see ::RUBY_Qtrue */
    :RUBY_T_FALSE    => 0x13, # /**< @see ::RUBY_Qfalse */
    :RUBY_T_SYMBOL   => 0x14, # /**< @see struct ::RSymbol */
    :RUBY_T_FIXNUM   => 0x15, # /**< Integers formerly known as Fixnums. */
    :RUBY_T_UNDEF    => 0x16, # /**< @see ::RUBY_Qundef */:
    :RUBY_T_IMEMO    => 0x1a, # /**< @see struct ::RIMemo */
    :RUBY_T_NODE     => 0x1b, # /**< @see struct ::RNode */
    :RUBY_T_ICLASS   => 0x1c, # /**< Hidden classes known as IClasses. */
    :RUBY_T_ZOMBIE   => 0x1d, # /**< @see struct ::RZombie */
    :RUBY_T_MOVED    => 0x1e, # /**< @see struct ::RMoved */
  })

  # Keep in sync with `enum ruby_fl_type` in `include/ruby/internal/fl_type.h`.
  RubyFlType = FlagsConverter.new({
    :RUBY_FL_WB_PROTECTED   => (1 << 5),
    :RUBY_FL_UNUSED6        => (1 << 6),
    :RUBY_FL_FINALIZE       => (1 << 7),
    :RUBY_FL_SHAREABLE      => (1 << 8),
    :RUBY_FL_WEAK_REFERENCE => (1 << 9),
    :RUBY_FL_UNUSED10       => (1 << 10),
    :RUBY_FL_FREEZE         => (1 << 11),
  })

  RUBY_T_MASK = 0x1f

  RubyFlags = proc do |value|
    value_i = value.to_i
    builtin_type = RubyBuiltinType.convert_arg(value_i & RUBY_T_MASK)
    flags = RubyFlType.convert_arg(value_i)
    {
      raw_value: value_i,
      builtin_type:,
      flags:,
    }
  end
end

