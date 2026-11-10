# frozen_string_literal: true

require_relative "../test_helper"

module Ruby::Prism
  class SourceTest < TestCase
    def test_byte_offset
      source = Ruby::Prism.parse(<<~SRC).source
      abcd
      efgh
      ijkl
      SRC

      assert_equal 0, source.byte_offset(1, 0)
      assert_equal 5, source.byte_offset(2, 0)
      assert_equal 10, source.byte_offset(3, 0)
      assert_equal 15, source.byte_offset(4, 0)

      error = assert_raise(ArgumentError) { source.byte_offset(5, 0) }
      assert_equal "line 5 is out of range", error.message

      error = assert_raise(ArgumentError) { source.byte_offset(0, 0) }
      assert_equal "line 0 is out of range", error.message

      error = assert_raise(ArgumentError) { source.byte_offset(-1, 0) }
      assert_equal "line -1 is out of range", error.message
    end

    def test_byte_offset_with_start_line
      source = Ruby::Prism.parse(<<~SRC, line: 11).source
      abcd
      efgh
      ijkl
      SRC

      assert_equal 0, source.byte_offset(11, 0)
      assert_equal 5, source.byte_offset(12, 0)
      assert_equal 10, source.byte_offset(13, 0)
      assert_equal 15, source.byte_offset(14, 0)

      error = assert_raise(ArgumentError) { source.byte_offset(15, 0) }
      assert_equal "line 15 is out of range", error.message

      error = assert_raise(ArgumentError) { source.byte_offset(10, 0) }
      assert_equal "line 10 is out of range", error.message

      error = assert_raise(ArgumentError) { source.byte_offset(9, 0) }
      assert_equal "line 9 is out of range", error.message
    end

    # These expectations generated via xxhsum -H3.
    def test_checksum
      assert_equal 0x2d06800538d394c2, Ruby::Prism.parse("").source.checksum

      {
        2 => 0x369242a646a19333,
        6 => 0x8a7787871647e141,
        12 => 0x6d13ee7fa0a78768,
        100 => 0x411d9368f9c30e07,
        200 => 0xac2bd404bce6c995,
        5000 => 0x86bab6aca5d8f5e9
      }.each do |length, expected|
        assert_equal expected, Ruby::Prism.parse("a" * length).source.checksum, "length #{length}"
      end
    end

    def test_checksum_excludes_data
      expected = Ruby::Prism.parse("puts 1\n__END__\n").source.checksum
      assert_equal 0x3326de5be62ee9e4, expected

      assert_equal expected, Ruby::Prism.parse("puts 1\n__END__\ndata\n").source.checksum
      assert_equal expected, Ruby::Prism.parse("puts 1\n__END__\nother data").source.checksum

      refute_equal expected, Ruby::Prism.parse("puts 1\n").source.checksum
      refute_equal expected, Ruby::Prism.parse("puts 2\n__END__\n").source.checksum
    end

    def test_checksum_across_apis
      source = "# comment\nputs 1\n__END__\ndata\n"
      expected = Ruby::Prism.parse(source).source.checksum

      assert_equal expected, Ruby::Prism.parse(source, freeze: true).source.checksum
      assert_equal expected, Ruby::Prism.lex(source).source.checksum
      assert_equal expected, Ruby::Prism.parse_lex(source).source.checksum
      if !ENV["PRISM_BUILD_MINIMAL"]
        assert_equal expected, Ruby::Prism.load(source, Ruby::Prism.dump(source)).source.checksum
      end
      assert_equal expected, Ruby::Prism.parse_stream(StringIO.new(source)).source.checksum

      comment = Ruby::Prism.parse_comments(source).first
      assert_equal expected, comment.location.send(:source).checksum
    end

    def test_checksum_without_parser
      assert_nil Source.for("puts 1", 1, [0]).checksum
      assert_equal 0x1234, Source.for("puts 1", 1, [0], [], [], [], 0x1234).checksum
      assert_equal 0x1234, Source.for("puts é", 1, [0], [], [], [], 0x1234).checksum
    end
  end
end
