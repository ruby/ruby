# frozen_string_literal: true

require_relative "helper"

require "date"
require "rubygems/safe_marshal"

class TestGemSafeMarshal < Gem::TestCase
  define_method("test_safe_load_marshal Date #<Date: 1994-12-09 ((2449696j,0s,0n),+0s,2299161j)>") { assert_safe_load_marshal "\x04\bU:\tDate[\vi\x00i\x03 a%i\x00i\x00i\x00f\f2299161" }
  define_method("test_safe_load_marshal Float 0.0") { assert_safe_load_marshal "\x04\bf\x060" }
  define_method("test_safe_load_marshal Float -0.0") { assert_safe_load_marshal "\x04\bf\a-0" }
  define_method("test_safe_load_marshal Float Infinity") { assert_safe_load_marshal "\x04\bf\binf" }
  define_method("test_safe_load_marshal Float -Infinity") { assert_safe_load_marshal "\x04\bf\t-inf" }
  define_method("test_safe_load_marshal Float NaN") { assert_safe_load_marshal "\x04\bf\bnan", equality: false }
  define_method("test_safe_load_marshal Float 1.1") { assert_safe_load_marshal "\x04\bf\b1.1" }
  define_method("test_safe_load_marshal Float -1.1") { assert_safe_load_marshal "\x04\bf\t-1.1" }
  define_method("test_safe_load_marshal Float 30000000.0") { assert_safe_load_marshal "\x04\bf\b3e7" }
  define_method("test_safe_load_marshal Float -30000000.0") { assert_safe_load_marshal "\x04\bf\t-3e7" }
  define_method("test_safe_load_marshal Gem::Version #<Gem::Version \"1.abc\">") { assert_safe_load_marshal "\x04\bU:\x11Gem::Version[\x06I\"\n1.abc\x06:\x06ET" }
  define_method("test_safe_load_marshal Hash {} default value") { assert_safe_load_marshal "\x04\b}\x00[\x00", additional_methods: [:default] }
  define_method("test_safe_load_marshal Hash {}") { assert_safe_load_marshal "\x04\b{\x00" }
  define_method("test_safe_load_marshal Array {}") { assert_safe_load_marshal "\x04\b[\x00" }
  define_method("test_safe_load_marshal Hash {:runtime=>:development}") { assert_safe_load_marshal "\x04\bI{\x06:\fruntime:\x10development\x06:\n@type[\x00", permitted_ivars: { "Hash" => %w[@type] } }
  define_method("test_safe_load_marshal Integer -1") { assert_safe_load_marshal "\x04\bi\xFA" }
  define_method("test_safe_load_marshal Integer -1048575") { assert_safe_load_marshal "\x04\bi\xFD\x01\x00\xF0" }
  define_method("test_safe_load_marshal Integer -122") { assert_safe_load_marshal "\x04\bi\x81" }
  define_method("test_safe_load_marshal Integer -123") { assert_safe_load_marshal "\x04\bi\x80" }
  define_method("test_safe_load_marshal Integer -124") { assert_safe_load_marshal "\x04\bi\xFF\x84" }
  define_method("test_safe_load_marshal Integer -127") { assert_safe_load_marshal "\x04\bi\xFF\x81" }
  define_method("test_safe_load_marshal Integer -128") { assert_safe_load_marshal "\x04\bi\xFF\x80" }
  define_method("test_safe_load_marshal Integer -2") { assert_safe_load_marshal "\x04\bi\xF9" }
  define_method("test_safe_load_marshal Integer -255") { assert_safe_load_marshal "\x04\bi\xFF\x01" }
  define_method("test_safe_load_marshal Integer -256") { assert_safe_load_marshal "\x04\bi\xFF\x00" }
  define_method("test_safe_load_marshal Integer -257") { assert_safe_load_marshal "\x04\bi\xFE\xFF\xFE" }
  define_method("test_safe_load_marshal Integer -268435455") { assert_safe_load_marshal "\x04\bi\xFC\x01\x00\x00\xF0" }
  define_method("test_safe_load_marshal Integer -268435456") { assert_safe_load_marshal "\x04\bi\xFC\x00\x00\x00\xF0" }
  define_method("test_safe_load_marshal Integer -3") { assert_safe_load_marshal "\x04\bi\xF8" }
  define_method("test_safe_load_marshal Integer -4") { assert_safe_load_marshal "\x04\bi\xF7" }
  define_method("test_safe_load_marshal Integer -4294967295") { assert_safe_load_marshal "\x04\bl-\a\xFF\xFF\xFF\xFF" }
  define_method("test_safe_load_marshal Integer -4294967296") { assert_safe_load_marshal "\x04\bl-\b\x00\x00\x00\x00\x01\x00" }
  define_method("test_safe_load_marshal Integer -5") { assert_safe_load_marshal "\x04\bi\xF6" }
  define_method("test_safe_load_marshal Integer -6") { assert_safe_load_marshal "\x04\bi\xF5" }
  define_method("test_safe_load_marshal Integer -65535") { assert_safe_load_marshal "\x04\bi\xFE\x01\x00" }
  define_method("test_safe_load_marshal Integer -65536") { assert_safe_load_marshal "\x04\bi\xFE\x00\x00" }
  define_method("test_safe_load_marshal Integer -9223372036854775807") { assert_safe_load_marshal "\x04\bl-\t\xFF\xFF\xFF\xFF\xFF\xFF\xFF\x7F" }
  define_method("test_safe_load_marshal Integer -9223372036854775808") { assert_safe_load_marshal "\x04\bl-\t\x00\x00\x00\x00\x00\x00\x00\x80" }
  define_method("test_safe_load_marshal Integer 0") { assert_safe_load_marshal "\x04\bi\x00" }
  define_method("test_safe_load_marshal Integer 1") { assert_safe_load_marshal "\x04\bi\x06" }
  define_method("test_safe_load_marshal Integer 1048574") { assert_safe_load_marshal "\x04\bi\x03\xFE\xFF\x0F" }
  define_method("test_safe_load_marshal Integer 1048575") { assert_safe_load_marshal "\x04\bi\x03\xFF\xFF\x0F" }
  define_method("test_safe_load_marshal Integer 1048576") { assert_safe_load_marshal "\x04\bi\x03\x00\x00\x10" }
  define_method("test_safe_load_marshal Integer 121") { assert_safe_load_marshal "\x04\bi~" }
  define_method("test_safe_load_marshal Integer 122") { assert_safe_load_marshal "\x04\bi\x7F" }
  define_method("test_safe_load_marshal Integer 123") { assert_safe_load_marshal "\x04\bi\x01{" }
  define_method("test_safe_load_marshal Integer 124") { assert_safe_load_marshal "\x04\bi\x01|" }
  define_method("test_safe_load_marshal Integer 125") { assert_safe_load_marshal "\x04\bi\x01}" }
  define_method("test_safe_load_marshal Integer 126") { assert_safe_load_marshal "\x04\bi\x01~" }
  define_method("test_safe_load_marshal Integer 127") { assert_safe_load_marshal "\x04\bi\x01\x7F" }
  define_method("test_safe_load_marshal Integer 128") { assert_safe_load_marshal "\x04\bi\x01\x80" }
  define_method("test_safe_load_marshal Integer 129") { assert_safe_load_marshal "\x04\bi\x01\x81" }
  define_method("test_safe_load_marshal Integer 2") { assert_safe_load_marshal "\x04\bi\a" }
  define_method("test_safe_load_marshal Integer 254") { assert_safe_load_marshal "\x04\bi\x01\xFE" }
  define_method("test_safe_load_marshal Integer 255") { assert_safe_load_marshal "\x04\bi\x01\xFF" }
  define_method("test_safe_load_marshal Integer 256") { assert_safe_load_marshal "\x04\bi\x02\x00\x01" }
  define_method("test_safe_load_marshal Integer 257") { assert_safe_load_marshal "\x04\bi\x02\x01\x01" }
  define_method("test_safe_load_marshal Integer 258") { assert_safe_load_marshal "\x04\bi\x02\x02\x01" }
  define_method("test_safe_load_marshal Integer 268435454") { assert_safe_load_marshal "\x04\bi\x04\xFE\xFF\xFF\x0F" }
  define_method("test_safe_load_marshal Integer 268435455") { assert_safe_load_marshal "\x04\bi\x04\xFF\xFF\xFF\x0F" }
  define_method("test_safe_load_marshal Integer 268435456") { assert_safe_load_marshal "\x04\bi\x04\x00\x00\x00\x10" }
  define_method("test_safe_load_marshal Integer 268435457") { assert_safe_load_marshal "\x04\bi\x04\x01\x00\x00\x10" }
  define_method("test_safe_load_marshal Integer 3") { assert_safe_load_marshal "\x04\bi\b" }
  define_method("test_safe_load_marshal Integer 4") { assert_safe_load_marshal "\x04\bi\t" }
  define_method("test_safe_load_marshal Integer 4294967294") { assert_safe_load_marshal "\x04\bl+\a\xFE\xFF\xFF\xFF" }
  define_method("test_safe_load_marshal Integer 4294967295") { assert_safe_load_marshal "\x04\bl+\a\xFF\xFF\xFF\xFF" }
  define_method("test_safe_load_marshal Integer 4294967296") { assert_safe_load_marshal "\x04\bl+\b\x00\x00\x00\x00\x01\x00" }
  define_method("test_safe_load_marshal Integer 4294967297") { assert_safe_load_marshal "\x04\bl+\b\x01\x00\x00\x00\x01\x00" }
  define_method("test_safe_load_marshal Integer 5") { assert_safe_load_marshal "\x04\bi\n" }
  define_method("test_safe_load_marshal Integer 6") { assert_safe_load_marshal "\x04\bi\v" }
  define_method("test_safe_load_marshal Integer 65534") { assert_safe_load_marshal "\x04\bi\x02\xFE\xFF" }
  define_method("test_safe_load_marshal Integer 65535") { assert_safe_load_marshal "\x04\bi\x02\xFF\xFF" }
  define_method("test_safe_load_marshal Integer 65536") { assert_safe_load_marshal "\x04\bi\x03\x00\x00\x01" }
  define_method("test_safe_load_marshal Integer 65537") { assert_safe_load_marshal "\x04\bi\x03\x01\x00\x01" }
  define_method("test_safe_load_marshal Integer 7") { assert_safe_load_marshal "\x04\bi\f" }
  define_method("test_safe_load_marshal Integer 9223372036854775806") { assert_safe_load_marshal "\x04\bl+\t\xFE\xFF\xFF\xFF\xFF\xFF\xFF\x7F" }
  define_method("test_safe_load_marshal Integer 9223372036854775807") { assert_safe_load_marshal "\x04\bl+\t\xFF\xFF\xFF\xFF\xFF\xFF\xFF\x7F" }
  define_method("test_safe_load_marshal Integer 9223372036854775808") { assert_safe_load_marshal "\x04\bl+\t\x00\x00\x00\x00\x00\x00\x00\x80" }
  define_method("test_safe_load_marshal Integer 9223372036854775809") { assert_safe_load_marshal "\x04\bl+\t\x01\x00\x00\x00\x00\x00\x00\x80" }
  define_method("test_safe_load_marshal Rational (1/3)") { assert_safe_load_marshal "\x04\bU:\rRational[\ai\x06i\b" }
  define_method("test_safe_load_marshal Array [[...]]") { assert_safe_load_marshal "\x04\b[\x06@\x00" }
  define_method("test_safe_load_marshal String \"hello\" ivar") { assert_safe_load_marshal "\x04\bI\"\nhello\a:\x06ET:\n@type@\x00", additional_methods: [:instance_variables], permitted_ivars: { "String" => %w[@type E] } }
  define_method("test_safe_load_marshal Array [\"hello\", [\"hello\"], \"hello\", [\"hello\"]]") { assert_safe_load_marshal "\x04\b[\tI\"\nhello\x06:\x06ET[\x06@\x06@\x06@\a" }
  define_method("test_safe_load_marshal Array [\"hello\", \"hello\"]") { assert_safe_load_marshal "\x04\b[\aI\"\nhello\x06:\x06ET@\x06" }
  define_method("test_safe_load_marshal Array [:development, :development]") { assert_safe_load_marshal "\x04\b[\a:\x10development;\x00" }
  define_method("test_safe_load_marshal String \"abc\" ascii") { assert_safe_load_marshal "\x04\bI\"\babc\x06:\x06EF", additional_methods: [:encoding] }
  define_method("test_safe_load_marshal Array [\"abc\", \"abc\"] ascii") { assert_safe_load_marshal "\x04\b[\aI\"\babc\x06:\x06EF@\x06", additional_methods: [->(x) { x.map(&:encoding) }] }
  define_method("test_safe_load_marshal String \"abc\" utf8") { assert_safe_load_marshal "\x04\bI\"\babc\x06:\x06ET", additional_methods: [:encoding] }
  define_method("test_safe_load_marshal Array [\"abc\", \"abc\"] utf8") { assert_safe_load_marshal "\x04\b[\aI\"\babc\x06:\x06ET@\x06", additional_methods: [->(x) { x.map(&:encoding) }] }
  define_method("test_safe_load_marshal String \"abc\" Windows-1256") { assert_safe_load_marshal "\x04\bI\"\babc\x06:\rencoding\"\x11Windows-1256", additional_methods: [:encoding] }
  define_method("test_safe_load_marshal Array [\"abc\", \"abc\"] Windows-1256") { assert_safe_load_marshal "\x04\b[\aI\"\babc\x06:\rencoding\"\x11Windows-1256@\x06", additional_methods: [->(x) { x.map(&:encoding) }] }
  define_method("test_safe_load_marshal String \"abc\" binary") { assert_safe_load_marshal "\x04\b\"\babc", additional_methods: [:encoding] }
  define_method("test_safe_load_marshal Array [\"abc\", \"abc\"] binary") { assert_safe_load_marshal "\x04\b[\a\"\babc@\x06", additional_methods: [->(x) { x.map(&:encoding) }] }
  define_method("test_safe_load_marshal String \"\\x61\\x62\\x63\" utf32") { assert_safe_load_marshal "\x04\bI\"\babc\x06:\rencoding\"\vUTF-32", additional_methods: [:encoding] }
  define_method("test_safe_load_marshal Array [\"\\x61\\x62\\x63\", \"\\x61\\x62\\x63\"] utf32") { assert_safe_load_marshal "\x04\b[\aI\"\babc\x06:\rencoding\"\vUTF-32@\x06", additional_methods: [->(x) { x.map(&:encoding) }] }
  define_method("test_safe_load_marshal String \"abc\" ivar") { assert_safe_load_marshal "\x04\bI\"\babc\a:\x06ET:\n@typeI\"\ttype\x06;\x00T", permitted_ivars: { "String" => %w[@type E] } }
  define_method("test_safe_load_marshal String \"\"") { assert_safe_load_marshal "\x04\bI\"\babc\x06:\x06ET" }
  define_method("test_safe_load_marshal Time 2000-12-31 20:07:59 -1152") { assert_safe_load_marshal "\x04\bIu:\tTime\r'@\x19\x80\x00\x00\xB0\xEF\a:\voffseti\xFE Y:\tzone0", additional_methods: [:ctime, :to_f, :to_r, :to_i, :zone, :subsec, :instance_variables, :dst?, :to_a] }
  define_method("test_safe_load_marshal Time 2000-12-31 23:59:59 -0800") { assert_safe_load_marshal "\x04\bIu:\tTime\r'@\x19\x80\x00\x00\xB0\xEF\a:\voffseti\xFE\x80\x8F:\tzoneI\"\bPST\x06:\x06EF", additional_methods: [:ctime, :to_f, :to_r, :to_i, :zone, :subsec, :instance_variables, :dst?, :to_a] }
  define_method("test_safe_load_marshal Time 2000-12-31 23:59:59 2254051613498933/2251799813685248000000000 -0800") { assert_safe_load_marshal "\x04\bIu:\tTime\r'@\x19\x80\x00\x00\xB0\xEF\n:\rnano_numl+\t5^\xBAI\f\x02\b\x00:\rnano_denl+\t\x00\x00\x00\x00\x00\x00\b\x00:\rsubmicro\"\a\x00\x10:\voffseti\xFE\x80\x8F:\tzoneI\"\bPST\x06:\x06EF", additional_methods: [:ctime, :to_f, :to_r, :to_i, :zone, :subsec, :instance_variables, :dst?, :to_a] }
  define_method("test_safe_load_marshal Time 2000-12-31 23:59:59 2476979795053773/2251799813685248000 -0800") { assert_safe_load_marshal "\x04\bIu:\tTime\r'@\x19\x80L\x04\xB0\xEF\t:\rnano_numi\x025\f:\rnano_denl+\b\x00\x00\x00\x00\x00 :\voffseti\xFE\x80\x8F:\tzoneI\"\bPST\x06:\x06EF", additional_methods: [:ctime, :to_f, :to_r, :to_i, :zone, :subsec, :instance_variables, :dst?, :to_a] }
  define_method("test_safe_load_marshal Time 2000-12-31 23:59:59 2476979795053773/2251799813685248000000 -0800") { assert_safe_load_marshal "\x04\bIu:\tTime\r'@\x19\x80\x01\x00\xB0\xEF\n:\rnano_numl+\t\x19\x00\x00\x00\x00\x00d\x00:\rnano_denl+\t\x00\x00\x00\x00\x00\x00\x01\x00:\rsubmicro\"\x06\x10:\voffseti\xFE\x80\x8F:\tzoneI\"\bPST\x06:\x06EF", additional_methods: [:ctime, :to_f, :to_r, :to_i, :zone, :subsec, :instance_variables, :dst?, :to_a] }
  define_method("test_safe_load_marshal Time 2000-12-31 23:59:59 2476979795053773/2251799813685248000000000 -0800") { assert_safe_load_marshal "\x04\bIu:\tTime\r'@\x19\x80\x00\x00\xB0\xEF\n:\rnano_numl+\t\xCD\xCC\xCC\xCC\xCC\xCC\b\x00:\rnano_denl+\t\x00\x00\x00\x00\x00\x00\b\x00:\rsubmicro\"\a\x00\x10:\voffseti\xFE\x80\x8F:\tzoneI\"\bPST\x06:\x06EF", additional_methods: [:ctime, :to_f, :to_r, :to_i, :zone, :subsec, :instance_variables, :dst?, :to_a] }
  define_method("test_safe_load_marshal Time 2000-12-31 23:59:59 450364466336677/450359962737049600000000 -0800") { assert_safe_load_marshal "\x04\bIu:\tTime\r'@\x19\x80\x00\x00\xB0\xEF\n:\rnano_numl+\t9b->\x05\x00\b\x00:\rnano_denl+\t\x00\x00\x00\x00\x00\x00\b\x00:\rsubmicro\"\a\x00\x10:\voffseti\xFE\x80\x8F:\tzoneI\"\bPST\x06:\x06EF", additional_methods: [:ctime, :to_f, :to_r, :to_i, :zone, :subsec, :instance_variables, :dst?, :to_a] }
  define_method("test_safe_load_marshal Time 2000-12-31 23:59:59 4548635623644201/4503599627370496000 -0800") { assert_safe_load_marshal "\x04\bIu:\tTime\r'@\x19\x80\xF2\x03\xB0\xEF\t:\rnano_numi\x02q\x02:\rnano_denl+\b\x00\x00\x00\x00\x00@:\voffseti\xFE\x80\x8F:\tzoneI\"\bPST\x06:\x06EF", additional_methods: [:ctime, :to_f, :to_r, :to_i, :zone, :subsec, :instance_variables, :dst?, :to_a] }
  define_method("test_safe_load_marshal Time 2000-12-31 23:59:59 4548635623644201/4503599627370496000000 -0800") { assert_safe_load_marshal "\x04\bIu:\tTime\r'@\x19\x80\x01\x00\xB0\xEF\n:\rnano_numl+\t\x05\x00\x00\x00\x00\x00\x14\x00:\rnano_denl+\t\x00\x00\x00\x00\x00\x00\x02\x00:\rsubmicro\"\x06\x01:\voffseti\xFE\x80\x8F:\tzoneI\"\bPST\x06:\x06EF", additional_methods: [:ctime, :to_f, :to_r, :to_i, :zone, :subsec, :instance_variables, :dst?, :to_a] }
  define_method("test_safe_load_marshal Time 2000-12-31 23:59:59 4548635623644201/4503599627370496000000000 -0800") { assert_safe_load_marshal "\x04\bIu:\tTime\r'@\x19\x80\x00\x00\xB0\xEF\n:\rnano_numl+\t)\\\x8F\xC2\xF5(\x10\x00:\rnano_denl+\t\x00\x00\x00\x00\x00\x00\x10\x00:\rsubmicro\"\a\x00\x10:\voffseti\xFE\x80\x8F:\tzoneI\"\bPST\x06:\x06EF", additional_methods: [:ctime, :to_f, :to_r, :to_i, :zone, :subsec, :instance_variables, :dst?, :to_a] }
  define_method("test_safe_load_marshal Time 2000-12-31 23:59:59.000000001 -0800") { assert_safe_load_marshal "\x04\bIu:\tTime\r'@\x19\x80\x00\x00\xB0\xEF\n:\rnano_numi\x06:\rnano_deni\x06:\rsubmicro\"\a\x00\x10:\voffseti\xFE\x80\x8F:\tzoneI\"\bPST\x06:\x06EF", additional_methods: [:ctime, :to_f, :to_r, :to_i, :zone, :subsec, :instance_variables, :dst?, :to_a] }
  define_method("test_safe_load_marshal Time 2000-12-31 23:59:59.000001 -0800") { assert_safe_load_marshal "\x04\bIu:\tTime\r'@\x19\x80\x01\x00\xB0\xEF\a:\voffseti\xFE\x80\x8F:\tzoneI\"\bPST\x06:\x06EF", additional_methods: [:ctime, :to_f, :to_r, :to_i, :zone, :subsec, :instance_variables, :dst?, :to_a] }
  define_method("test_safe_load_marshal Time 2000-12-31 23:59:59.001 -0800") { assert_safe_load_marshal "\x04\bIu:\tTime\r'@\x19\x80\xE8\x03\xB0\xEF\a:\voffseti\xFE\x80\x8F:\tzoneI\"\bPST\x06:\x06EF", additional_methods: [:ctime, :to_f, :to_r, :to_i, :zone, :subsec, :instance_variables, :dst?, :to_a] }
  define_method("test_safe_load_marshal Time 2001-01-01 07:59:59 +0000") { assert_safe_load_marshal "\x04\bIu:\tTime\r'@\x19\x80\x00\x00\xB0\xEF\a:\voffseti\x00:\tzone0", additional_methods: [:ctime, :to_f, :to_r, :to_i, :zone, :subsec, :instance_variables, :dst?, :to_a] }
  define_method("test_safe_load_marshal Time 2001-01-01 07:59:59 UTC") { assert_safe_load_marshal "\x04\bIu:\tTime\r'@\x19\xC0\x00\x00\xB0\xEF\x06:\tzoneI\"\bUTC\x06:\x06EF", additional_methods: [:ctime, :to_f, :to_r, :to_i, :zone, :subsec, :instance_variables, :dst?, :to_a] }
  define_method("test_safe_load_marshal Time 2001-01-01 11:59:59 +0400") { assert_safe_load_marshal "\x04\bIu:\tTime\r'@\x19\x80\x00\x00\xB0\xEF\a:\voffseti\x02@8:\tzone0", additional_methods: [:ctime, :to_f, :to_r, :to_i, :zone, :subsec, :instance_variables, :dst?, :to_a] }
  define_method("test_safe_load_marshal Time 2023-08-24 10:10:39.09565 -0700") { assert_safe_load_marshal "\x04\bIu:\tTime\r\x11\xDF\x1E\x80\xA2uq*\a:\voffseti\xFE\x90\x9D:\tzoneI\"\bPDT\x06:\x06EF" }
  define_method("test_safe_load_marshal Time 2023-08-24 10:10:39.098453 -0700") { assert_safe_load_marshal "\x04\bIu:\tTime\r\x11\xDF\x1E\x80\x95\x80q*\b:\n@typeI\"\fruntime\x06:\x06ET:\voffseti\xFE\x90\x9D:\tzoneI\"\bPDT\x06;\aF", permitted_ivars: { "Time" => %w[@type offset zone], "String" => %w[E @debug_created_info] }, marshal_dump_equality: (RUBY_ENGINE != "truffleruby" || RUBY_ENGINE_VERSION >= "23") }

  def test_repeated_symbol
    assert_safe_load_as [:development, :development]
  end

  def test_length_one_symbols
    with_const(Gem::SafeMarshal, :PERMITTED_SYMBOLS, %w[E A b 0] << "") do
      assert_safe_load_as [:A, :E, :E, :A, "".to_sym, "".to_sym], additional_methods: [:instance_variables]
    end
  end

  def test_repeated_string
    s = "hello"
    a = [s]
    assert_safe_load_as [s, a, s, a]
    assert_safe_load_as [s, s]
  end

  def test_recursive_string
    s = String.new("hello")
    s.instance_variable_set(:@type, s)
    with_const(Gem::SafeMarshal, :PERMITTED_IVARS, { "String" => %w[@type E] }) do
      assert_safe_load_as s, additional_methods: [:instance_variables]
    end
  end

  def test_recursive_array
    a = []
    a << a
    assert_safe_load_as a
  end

  def test_time_loads
    assert_safe_load_as Time.new
  end

  def test_string_with_encoding
    [
      String.new("abc", encoding: "US-ASCII"),
      String.new("abc", encoding: "UTF-8"),
      String.new("abc", encoding: "Windows-1256"),
      String.new("abc", encoding: Encoding::BINARY),
      String.new("abc", encoding: "UTF-32"),

      String.new("", encoding: "US-ASCII"),
      String.new("", encoding: "UTF-8"),
      String.new("", encoding: "Windows-1256"),
      String.new("", encoding: Encoding::BINARY),
      String.new("", encoding: "UTF-32"),
    ].each do |s|
      assert_safe_load_as s, additional_methods: [:encoding]
      assert_safe_load_as [s, s], additional_methods: [->(a) { a.map(&:encoding) }]
    end
  end

  def test_string_with_ivar
    str = String.new("abc")
    str.instance_variable_set :@type, "type"
    with_const(Gem::SafeMarshal, :PERMITTED_IVARS, { "String" => %w[@type E @debug_created_info] }) do
      assert_safe_load_as str
    end
  end

  def test_time_with_ivar
    pend "Marshal.load of Time with ivars is broken on jruby, see https://github.com/jruby/jruby/issues/7902" if RUBY_ENGINE == "jruby"

    with_const(Gem::SafeMarshal, :PERMITTED_IVARS, { "Time" => %w[@type offset zone nano_num nano_den submicro], "String" => %w[E @debug_created_info] }) do
      assert_safe_load_as Time.new.tap {|t| t.instance_variable_set :@type, "runtime" }, marshal_dump_equality: (RUBY_ENGINE != "truffleruby" || RUBY_ENGINE_VERSION >= "23")
    end
  end

  secs = Time.new(2000, 12, 31, 23, 59, 59).to_i
  [
    Time.at(secs),
    Time.at(secs, in: "+04:00"),
    Time.at(secs, in: "-11:52"),
    Time.at(secs, in: "+00:00"),
    Time.at(secs, in: "-00:00"),
    Time.at(secs, 1, :millisecond),
    Time.at(secs, 1.1, :millisecond),
    Time.at(secs, 1.01, :millisecond),
    Time.at(secs, 1, :microsecond),
    Time.at(secs, 1.1, :microsecond),
    Time.at(secs, 1.01, :microsecond),
    Time.at(secs, 1, :nanosecond),
    Time.at(secs, 1.1, :nanosecond),
    Time.at(secs, 1.01, :nanosecond),
    Time.at(secs, 1.001, :nanosecond),
    Time.at(secs, 1.00001, :nanosecond),
    Time.at(secs, 1.00001, :nanosecond),
  ].tap do |times|
    unless RUBY_ENGINE == "truffleruby" && RUBY_ENGINE_VERSION < "23" || RUBY_VERSION < "2.7"
      times.concat [
        Time.at(secs, in: "UTC"),
        Time.at(secs, in: "Z"),
      ]
    end
  end.each_with_index do |t, i|
    define_method("test_time_#{i} #{t.inspect}") do
      pend "Marshal.load of Time with custom zone is broken before Truffleruby 23" if t.zone.nil? && RUBY_ENGINE == "truffleruby" && RUBY_ENGINE_VERSION < "23"

      additional_methods = [:ctime, :to_f, :to_r, :to_i, :zone, :subsec, :instance_variables, :dst?, :to_a]
      assert_safe_load_as t, additional_methods: additional_methods
    end
  end

  def test_floats
    [0.0, Float::INFINITY, Float::NAN, 1.1, 3e7].each do |f|
      assert_safe_load_as f
      assert_safe_load_as(-f)
    end
  end

  def test_hash_with_ivar
    h = { runtime: :development }
    h.instance_variable_set :@type, []
    with_const(Gem::SafeMarshal, :PERMITTED_IVARS, { "Hash" => %w[@type] }) do
      assert_safe_load_as(h)
    end
  end

  def test_hash_with_default_value
    assert_safe_load_as Hash.new([])
  end

  def test_hash_with_compare_by_identity
    pend "`read_user_class` not yet implemented"

    assert_safe_load_as Hash.new.compare_by_identity
  end

  def test_frozen_object
    assert_safe_load_as Gem::Version.new("1.abc").freeze
  end

  def test_date
    assert_safe_load_as Date.new(1994, 12, 9)
  end

  def test_rational
    pend "truffleruby dumps rationals with ivars set on array, see https://github.com/oracle/truffleruby/issues/3228" if RUBY_ENGINE == "truffleruby"

    assert_safe_load_as Rational(1, 3)
  end

  [
    0, 1, 2, 3, 4, 5, 6, 122, 123, 124, 127, 128, 255, 256, 257,
    2**16, 2**16 - 1, 2**20 - 1,
    2**28, 2**28 - 1,
    2**32, 2**32 - 1,
    2**63, 2**63 - 1
  ].
  each do |i|
    define_method("test_int_ #{i}") do
      assert_safe_load_as i
      assert_safe_load_as(-i)
      assert_safe_load_as(i + 1)
      assert_safe_load_as(i - 1)
    end
  end

  def test_gem_spec_disallowed_symbol
    e = assert_raise(Gem::SafeMarshal::Visitors::ToRuby::UnpermittedSymbolError) do
      spec = Gem::Specification.new do |s|
        s.name = "hi"
        s.version = "1.2.3"

        s.dependencies << Gem::Dependency.new("rspec", Gem::Requirement.new([">= 1.2.3"]), :runtime).tap {|d| d.instance_variable_set(:@name, :rspec) }
      end
      Gem::SafeMarshal.safe_load(Marshal.dump(spec))
    end

    assert_equal e.message, "Attempting to load unpermitted symbol \"rspec\" @ root.[9].[0].@name"
  end

  def test_gem_spec_disallowed_ivar
    e = assert_raise(Gem::SafeMarshal::Visitors::ToRuby::UnpermittedIvarError) do
      spec = Gem::Specification.new do |s|
        s.name = "hi"
        s.version = "1.2.3"

        s.metadata.instance_variable_set(:@foobar, "rspec")
      end
      Gem::SafeMarshal.safe_load(Marshal.dump(spec))
    end

    assert_equal e.message, "Attempting to set unpermitted ivar \"@foobar\" on object of class Hash @ root.[18].ivar_0"
  end

  def assert_safe_load_marshal(dumped, additional_methods: [], permitted_ivars: nil, equality: true, marshal_dump_equality: true)
    loaded = Marshal.load(dumped)
    safe_loaded =
      if permitted_ivars
        with_const(Gem::SafeMarshal, :PERMITTED_IVARS, permitted_ivars) do
          Gem::SafeMarshal.safe_load(dumped)
        end
      else
        Gem::SafeMarshal.safe_load(dumped)
      end

    # NaN != NaN, for example
    if equality
      assert_equal loaded, safe_loaded, "should equal what Marshal.load returns"
    end

    assert_equal loaded.to_s, safe_loaded.to_s, "should have equal to_s"
    assert_equal loaded.inspect, safe_loaded.inspect, "should have equal inspect"
    additional_methods.each do |m|
      if m.is_a?(Proc)
        call = m
      else
        call = ->(obj) { obj.__send__(m) }
      end

      assert_equal call[loaded], call[safe_loaded], "should have equal #{m}"
    end
    if marshal_dump_equality
      assert_equal Marshal.dump(loaded).dump, Marshal.dump(safe_loaded).dump, "should Marshal.dump the same"
    end
  end

  def assert_safe_load_as(x, **kwargs)
    dumped = Marshal.dump(x)
    equality = x == x # rubocop:disable Lint/BinaryOperatorWithIdenticalOperands
    assert_safe_load_marshal(dumped, equality: equality, **kwargs)
  end

  def with_const(mod, name, new_value, &block)
    orig = mod.const_get(name)
    mod.send :remove_const, name
    mod.const_set name, new_value

    begin
      yield
    ensure
      mod.send :remove_const, name
      mod.const_set name, orig
      mod.send :private_constant, name
    end
  end
end
