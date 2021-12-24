require_relative "../helper"

class TestCSVParseInputsScanner < Test::Unit::TestCase
  include Helper

  def test_keep_over_chunks_nested_back
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


  def test_keep_over_chunks_nested_drop_back
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
end
