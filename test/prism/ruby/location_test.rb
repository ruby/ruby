# frozen_string_literal: true

require_relative "../test_helper"

module Prism
  class LocationTest < TestCase
    def test_join
      call = Prism.parse_statement("1234 + 567")
      receiver = call.receiver
      argument = call.arguments.arguments.first

      joined = receiver.location.join(argument.location)
      assert_equal 0, joined.start_offset
      assert_equal 10, joined.length

      assert_raise(RuntimeError, "Incompatible locations") do
        argument.location.join(receiver.location)
      end

      other_argument = Prism.parse_statement("1234 + 567").arguments.arguments.first

      assert_raise(RuntimeError, "Incompatible sources") do
        other_argument.location.join(receiver.location)
      end

      assert_raise(RuntimeError, "Incompatible sources") do
        receiver.location.join(other_argument.location)
      end
    end

    def test_character_offsets
      program = Prism.parse("😀 + 😀\n😍 ||= 😍").value

      # first 😀
      location = program.statements.body.first.receiver.location
      assert_equal 0, location.start_character_offset
      assert_equal 1, location.end_character_offset
      assert_equal 0, location.start_character_column
      assert_equal 1, location.end_character_column

      # second 😀
      location = program.statements.body.first.arguments.arguments.first.location
      assert_equal 4, location.start_character_offset
      assert_equal 5, location.end_character_offset
      assert_equal 4, location.start_character_column
      assert_equal 5, location.end_character_column

      # first 😍
      location = program.statements.body.last.name_loc
      assert_equal 6, location.start_character_offset
      assert_equal 7, location.end_character_offset
      assert_equal 0, location.start_character_column
      assert_equal 1, location.end_character_column

      # second 😍
      location = program.statements.body.last.value.location
      assert_equal 12, location.start_character_offset
      assert_equal 13, location.end_character_offset
      assert_equal 6, location.start_character_column
      assert_equal 7, location.end_character_column
    end

    def test_code_units
      program = Prism.parse("😀 + 😀\n😍 ||= 😍").value

      # first 😀
      location = program.statements.body.first.receiver.location

      assert_equal 0, location.start_code_units_offset(Encoding::UTF_8)
      assert_equal 0, location.start_code_units_offset(Encoding::UTF_16LE)
      assert_equal 0, location.start_code_units_offset(Encoding::UTF_32LE)

      assert_equal 1, location.end_code_units_offset(Encoding::UTF_8)
      assert_equal 2, location.end_code_units_offset(Encoding::UTF_16LE)
      assert_equal 1, location.end_code_units_offset(Encoding::UTF_32LE)

      assert_equal 0, location.start_code_units_column(Encoding::UTF_8)
      assert_equal 0, location.start_code_units_column(Encoding::UTF_16LE)
      assert_equal 0, location.start_code_units_column(Encoding::UTF_32LE)

      assert_equal 1, location.end_code_units_column(Encoding::UTF_8)
      assert_equal 2, location.end_code_units_column(Encoding::UTF_16LE)
      assert_equal 1, location.end_code_units_column(Encoding::UTF_32LE)

      # second 😀
      location = program.statements.body.first.arguments.arguments.first.location

      assert_equal 4, location.start_code_units_offset(Encoding::UTF_8)
      assert_equal 5, location.start_code_units_offset(Encoding::UTF_16LE)
      assert_equal 4, location.start_code_units_offset(Encoding::UTF_32LE)

      assert_equal 5, location.end_code_units_offset(Encoding::UTF_8)
      assert_equal 7, location.end_code_units_offset(Encoding::UTF_16LE)
      assert_equal 5, location.end_code_units_offset(Encoding::UTF_32LE)

      assert_equal 4, location.start_code_units_column(Encoding::UTF_8)
      assert_equal 5, location.start_code_units_column(Encoding::UTF_16LE)
      assert_equal 4, location.start_code_units_column(Encoding::UTF_32LE)

      assert_equal 5, location.end_code_units_column(Encoding::UTF_8)
      assert_equal 7, location.end_code_units_column(Encoding::UTF_16LE)
      assert_equal 5, location.end_code_units_column(Encoding::UTF_32LE)

      # first 😍
      location = program.statements.body.last.name_loc

      assert_equal 6, location.start_code_units_offset(Encoding::UTF_8)
      assert_equal 8, location.start_code_units_offset(Encoding::UTF_16LE)
      assert_equal 6, location.start_code_units_offset(Encoding::UTF_32LE)

      assert_equal 7, location.end_code_units_offset(Encoding::UTF_8)
      assert_equal 10, location.end_code_units_offset(Encoding::UTF_16LE)
      assert_equal 7, location.end_code_units_offset(Encoding::UTF_32LE)

      assert_equal 0, location.start_code_units_column(Encoding::UTF_8)
      assert_equal 0, location.start_code_units_column(Encoding::UTF_16LE)
      assert_equal 0, location.start_code_units_column(Encoding::UTF_32LE)

      assert_equal 1, location.end_code_units_column(Encoding::UTF_8)
      assert_equal 2, location.end_code_units_column(Encoding::UTF_16LE)
      assert_equal 1, location.end_code_units_column(Encoding::UTF_32LE)

      # second 😍
      location = program.statements.body.last.value.location

      assert_equal 12, location.start_code_units_offset(Encoding::UTF_8)
      assert_equal 15, location.start_code_units_offset(Encoding::UTF_16LE)
      assert_equal 12, location.start_code_units_offset(Encoding::UTF_32LE)

      assert_equal 13, location.end_code_units_offset(Encoding::UTF_8)
      assert_equal 17, location.end_code_units_offset(Encoding::UTF_16LE)
      assert_equal 13, location.end_code_units_offset(Encoding::UTF_32LE)

      assert_equal 6, location.start_code_units_column(Encoding::UTF_8)
      assert_equal 7, location.start_code_units_column(Encoding::UTF_16LE)
      assert_equal 6, location.start_code_units_column(Encoding::UTF_32LE)

      assert_equal 7, location.end_code_units_column(Encoding::UTF_8)
      assert_equal 9, location.end_code_units_column(Encoding::UTF_16LE)
      assert_equal 7, location.end_code_units_column(Encoding::UTF_32LE)
    end

    def test_cached_code_units
      result = Prism.parse("😀 + 😀\n😍 ||= 😍")

      utf8_cache = result.code_units_cache(Encoding::UTF_8)
      utf16_cache = result.code_units_cache(Encoding::UTF_16LE)
      utf32_cache = result.code_units_cache(Encoding::UTF_32LE)

      # first 😀
      location = result.value.statements.body.first.receiver.location

      assert_equal 0, location.cached_start_code_units_offset(utf8_cache)
      assert_equal 0, location.cached_start_code_units_offset(utf16_cache)
      assert_equal 0, location.cached_start_code_units_offset(utf32_cache)

      assert_equal 1, location.cached_end_code_units_offset(utf8_cache)
      assert_equal 2, location.cached_end_code_units_offset(utf16_cache)
      assert_equal 1, location.cached_end_code_units_offset(utf32_cache)

      assert_equal 0, location.cached_start_code_units_column(utf8_cache)
      assert_equal 0, location.cached_start_code_units_column(utf16_cache)
      assert_equal 0, location.cached_start_code_units_column(utf32_cache)

      assert_equal 1, location.cached_end_code_units_column(utf8_cache)
      assert_equal 2, location.cached_end_code_units_column(utf16_cache)
      assert_equal 1, location.cached_end_code_units_column(utf32_cache)

      # second 😀
      location = result.value.statements.body.first.arguments.arguments.first.location

      assert_equal 4, location.cached_start_code_units_offset(utf8_cache)
      assert_equal 5, location.cached_start_code_units_offset(utf16_cache)
      assert_equal 4, location.cached_start_code_units_offset(utf32_cache)

      assert_equal 5, location.cached_end_code_units_offset(utf8_cache)
      assert_equal 7, location.cached_end_code_units_offset(utf16_cache)
      assert_equal 5, location.cached_end_code_units_offset(utf32_cache)

      assert_equal 4, location.cached_start_code_units_column(utf8_cache)
      assert_equal 5, location.cached_start_code_units_column(utf16_cache)
      assert_equal 4, location.cached_start_code_units_column(utf32_cache)

      assert_equal 5, location.cached_end_code_units_column(utf8_cache)
      assert_equal 7, location.cached_end_code_units_column(utf16_cache)
      assert_equal 5, location.cached_end_code_units_column(utf32_cache)
    end

    def test_code_units_binary_valid_utf8
      program = Prism.parse(<<~RUBY).value
        # -*- encoding: binary -*-

        😀 + 😀
      RUBY

      receiver = program.statements.body.first.receiver
      assert_equal "😀".b.to_sym, receiver.name

      location = receiver.location
      assert_equal 1, location.end_code_units_column(Encoding::UTF_8)
      assert_equal 2, location.end_code_units_column(Encoding::UTF_16LE)
      assert_equal 1, location.end_code_units_column(Encoding::UTF_32LE)
    end

    def test_code_units_binary_invalid_utf8
      program = Prism.parse(<<~RUBY).value
        # -*- encoding: binary -*-

        \x90 + \x90
      RUBY

      receiver = program.statements.body.first.receiver
      assert_equal "\x90".b.to_sym, receiver.name

      location = receiver.location
      assert_equal 1, location.end_code_units_column(Encoding::UTF_8)
      assert_equal 1, location.end_code_units_column(Encoding::UTF_16LE)
      assert_equal 1, location.end_code_units_column(Encoding::UTF_32LE)
    end

    def test_chop
      location = Prism.parse("foo").value.location

      assert_equal "fo", location.chop.slice
      assert_equal "", location.chop.chop.chop.slice

      # Check that we don't go negative.
      10.times { location = location.chop }
      assert_equal "", location.slice
    end

    def test_slice_lines
      method = Prism.parse_statement("\nprivate def foo\nend\n").arguments.arguments.first

      assert_equal "private def foo\nend\n", method.slice_lines
    end

    def test_adjoin
      program = Prism.parse("foo.bar = 1").value

      location = program.statements.body.first.message_loc
      adjoined = location.adjoin("=")

      assert_kind_of Location, adjoined
      refute_equal location, adjoined

      assert_equal 4, adjoined.start_offset
      assert_equal 9, adjoined.end_offset
    end
  end
end
