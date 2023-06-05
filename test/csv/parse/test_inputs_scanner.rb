require_relative "../helper"

class TestCSVParseInputsScanner < Test::Unit::TestCase
  include CSVHelper

  def test_scan_keep_over_chunks_nested_back
    input = CSV::Parser::UnoptimizedStringIO.new("abcdefghijklmnl")
    scanner = CSV::Parser::InputsScanner.new([input],
                                             Encoding::UTF_8,
                                             nil,
                                             chunk_size: 2)
    scanner.keep_start
    assert_equal("abc", scanner.scan_all(/[a-c]+/))
    scanner.keep_start
    assert_equal("def", scanner.scan_all(/[d-f]+/))
    scanner.keep_back
    scanner.keep_back
    assert_equal("abcdefg", scanner.scan_all(/[a-g]+/))
  end

  def test_scan_keep_over_chunks_nested_drop_back
    input = CSV::Parser::UnoptimizedStringIO.new("abcdefghijklmnl")
    scanner = CSV::Parser::InputsScanner.new([input],
                                             Encoding::UTF_8,
                                             nil,
                                             chunk_size: 3)
    scanner.keep_start
    assert_equal("ab", scanner.scan(/../))
    scanner.keep_start
    assert_equal("c", scanner.scan(/./))
    assert_equal("d", scanner.scan(/./))
    scanner.keep_drop
    scanner.keep_back
    assert_equal("abcdefg", scanner.scan_all(/[a-g]+/))
  end

  def test_each_line_keep_over_chunks_multibyte
    input = CSV::Parser::UnoptimizedStringIO.new("ab\n\u{3000}a\n")
    scanner = CSV::Parser::InputsScanner.new([input],
                                             Encoding::UTF_8,
                                             nil,
                                             chunk_size: 1)
    each_line = scanner.each_line("\n")
    assert_equal("ab\n", each_line.next)
    scanner.keep_start
    assert_equal("\u{3000}a\n", each_line.next)
    scanner.keep_back
    assert_equal("\u{3000}a\n", scanner.scan_all(/[^,]+/))
  end

  def test_each_line_keep_over_chunks_fit_chunk_size
    input = CSV::Parser::UnoptimizedStringIO.new("\na")
    scanner = CSV::Parser::InputsScanner.new([input],
                                             Encoding::UTF_8,
                                             nil,
                                             chunk_size: 1)
    each_line = scanner.each_line("\n")
    assert_equal("\n", each_line.next)
    scanner.keep_start
    assert_equal("a", each_line.next)
    scanner.keep_back
  end
end
