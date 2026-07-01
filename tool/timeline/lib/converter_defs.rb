# frozen_string_literal: true

require_relative 'converter'

module RubyTimelineTool
  # Keep in sync with `enum gc_enter_event` in `gc/default/default.c`.
  GCEnterEvent = EnumConverter.new({
    start:      0,
    continue:   1,
    rest:       2,
    finalizer:  3,
  })

  # Keep in sync with `enum ruby_value_type` in `include/ruby/internal/value_type.h`.
  RubyBuiltinType = EnumConverter.new({
    RUBY_T_NONE:      0x00, # /**< Non-object (swept etc.) */:
    RUBY_T_OBJECT:    0x01, # /**< @see struct ::RObject */
    RUBY_T_CLASS:     0x02, # /**< @see struct ::RClass and ::rb_cClass */
    RUBY_T_MODULE:    0x03, # /**< @see struct ::RClass and ::rb_cModule */
    RUBY_T_FLOAT:     0x04, # /**< @see struct ::RFloat */
    RUBY_T_STRING:    0x05, # /**< @see struct ::RString */
    RUBY_T_REGEXP:    0x06, # /**< @see struct ::RRegexp */
    RUBY_T_ARRAY:     0x07, # /**< @see struct ::RArray */
    RUBY_T_HASH:      0x08, # /**< @see struct ::RHash */
    RUBY_T_STRUCT:    0x09, # /**< @see struct ::RStruct */
    RUBY_T_BIGNUM:    0x0a, # /**< @see struct ::RBignum */
    RUBY_T_FILE:      0x0b, # /**< @see struct ::RFile */
    RUBY_T_DATA:      0x0c, # /**< @see struct ::RTypedData */
    RUBY_T_MATCH:     0x0d, # /**< @see struct ::RMatch */
    RUBY_T_COMPLEX:   0x0e, # /**< @see struct ::RComplex */
    RUBY_T_RATIONAL:  0x0f, # /**< @see struct ::RRational */:
    RUBY_T_NIL:       0x11, # /**< @see ::RUBY_Qnil */
    RUBY_T_TRUE:      0x12, # /**< @see ::RUBY_Qtrue */
    RUBY_T_FALSE:     0x13, # /**< @see ::RUBY_Qfalse */
    RUBY_T_SYMBOL:    0x14, # /**< @see struct ::RSymbol */
    RUBY_T_FIXNUM:    0x15, # /**< Integers formerly known as Fixnums. */
    RUBY_T_UNDEF:     0x16, # /**< @see ::RUBY_Qundef */:
    RUBY_T_IMEMO:     0x1a, # /**< @see struct ::RIMemo */
    RUBY_T_NODE:      0x1b, # /**< @see struct ::RNode */
    RUBY_T_ICLASS:    0x1c, # /**< Hidden classes known as IClasses. */
    RUBY_T_ZOMBIE:    0x1d, # /**< @see struct ::RZombie */
    RUBY_T_MOVED:     0x1e, # /**< @see struct ::RMoved */
  })

  # Keep in sync with `enum ruby_value_type` in `include/ruby/internal/value_type.h`.
  RUBY_T_MASK = 0x1f

  # Keep in sync with `enum ruby_fl_type` in `include/ruby/internal/fl_type.h`.
  RubyFlType = FlagsConverter.new({
    RUBY_FL_PROMOTED:       (1 << 5),
    RUBY_FL_UNUSED6:        (1 << 6),
    RUBY_FL_FINALIZE:       (1 << 7),
    RUBY_FL_SHAREABLE:      (1 << 8),
    RUBY_FL_WEAK_REFERENCE: (1 << 9),
    RUBY_FL_UNUSED10:       (1 << 10),
    RUBY_FL_FREEZE:         (1 << 11),
  })

  # Keep in sync with `enum ruby_fl_ushift` in `include/ruby/internal/fl_type.h`.
  RUBY_FL_USHIFT = 12

  # Keep in sync with `include/ruby/internal/fl_type.h`
  def self.FL_USER_N(n)
    1 << (RUBY_FL_USHIFT + n)
  end

  # Keep in sync with `enum imemo_type` in `internal/imemo.h`.
  ImemoType = EnumConverter.new({
    imemo_env:           0,
    imemo_cref:          1, # /*!< class reference */
    imemo_svar:          2, # /*!< special variable */
    imemo_throw_data:    3,
    imemo_ifunc:         4, # /*!< iterator function */
    imemo_memo:          5,
    imemo_ment:          6,
    imemo_iseq:          7,
    imemo_tmpbuf:        8,
    imemo_cvar_entry:    9,
    imemo_callinfo:     10,
    imemo_callcache:    11,
    imemo_constcache:   12,
    imemo_fields:       13,
    imemo_subclasses:   14,
    imemo_cdhash:       15,
  })

  # Keep in sync with `IMEMO_MASK` in `internal/imemo.h`.
  IMEMO_MASK = 0x0f

  # Keep in sync with both `internal/string.h` and `include/ruby/internal/core/rstring.h`.
  StringFlags = FlagsConverter.new({
    STR_SHARED:               FL_USER_N(0),
    RSTRING_NOEMBED:          FL_USER_N(1),
    STR_CHILLED_LITERAL:      FL_USER_N(2),
    STR_CHILLED_SYMBOL_TO_S:  FL_USER_N(3),
    RSTRING_FSTR:             FL_USER_N(17),
  })

  # Keep in sync with both `internal/array.h` and `include/ruby/internal/core/rarray.h`.
  ArrayFlags = FlagsConverter.new({
    RARRAY_SHARED_FLAG:       FL_USER_N(0),
    RARRAY_EMBED_FLAG:        FL_USER_N(1),
    RARRAY_SHARED_ROOT_FLAG:  FL_USER_N(12),
    RARRAY_PTR_IN_USE_FLAG:   FL_USER_N(14),
  })

  RubyFlags = proc do |raw_value|
    value = raw_value.to_i
    builtin_type = RubyBuiltinType.convert_arg(value & RUBY_T_MASK)
    result = {
      raw_value: value,
      raw_value_binary: value.to_s(2),
      builtin_type:,
    }

    if builtin_type == :RUBY_T_IMEMO
      result[:imemo_type] = ImemoType.convert_arg((value >> RUBY_FL_USHIFT) & IMEMO_MASK)
    end

    result[:flags] = RubyFlType.convert_arg(value)

    case builtin_type
    when :RUBY_T_STRING
      result[:string_args] = StringFlags.convert_arg(value)
    when :RUBY_T_ARRAY
      result[:array_args] = ArrayFlags.convert_arg(value)

      # TODO: Decode the flags for more types of interest.
    end

    result
  end
end
