require_relative "test_helper"
require "ruby/signature/test/test_helper"

class StringSingletonTest < Minitest::Test
  include Ruby::Signature::Test::TypeAssertions

  testing "singleton(::String)"

  def test_initialize
    assert_send_type "() -> String",
                     String, :new
    assert_send_type "(String) -> String",
                     String, :new, ""
    assert_send_type "(String, encoding: Encoding) -> String",
                     String, :new, "", encoding: Encoding::ASCII_8BIT
    assert_send_type "(String, encoding: Encoding, capacity: Integer) -> String",
                     String, :new, "", encoding: Encoding::ASCII_8BIT, capacity: 123
    assert_send_type "(encoding: Encoding, capacity: Integer) -> String",
                     String, :new, encoding: Encoding::ASCII_8BIT, capacity: 123
    assert_send_type "(ToStr) -> String",
                     String, :new, ToStr.new("")
    assert_send_type "(encoding: ToStr) -> String",
                     String, :new, encoding: ToStr.new('Shift_JIS')
    assert_send_type "(capacity: ToInt) -> String",
                     String, :new, capacity: ToInt.new(123)
  end

  def test_try_convert
    assert_send_type "(String) -> String",
                     String, :try_convert, "str"
    assert_send_type "(ToStr) -> String",
                     String, :try_convert, ToStr.new("str")
    assert_send_type "(Regexp) -> nil",
                     String, :try_convert, /re/
  end
end

class StringInstanceTest < Minitest::Test
  include Ruby::Signature::Test::TypeAssertions

  testing "::String"

  def test_format_m
    assert_send_type "(Integer) -> String",
                     "%05d", :%, 123
    assert_send_type "(Array[String | Integer]) -> String",
                     "%-5s: %016x", :%, [ "ID", self.object_id ]
    assert_send_type "(Hash[Symbol, untyped]) -> String",
                     "foo = %{foo}", :%, { :foo => 'bar' }
  end

  def test_times
    assert_send_type "(Integer) -> String",
                     "Ho! ", :*, 3
    assert_send_type "(ToInt) -> String",
                     "Ho! ", :*, ToInt.new(0)
  end

  def test_plus
    assert_send_type "(String) -> String",
                     "Hello from ", :+, self.to_s
    assert_send_type "(ToStr) -> String",
                     "Hello from ", :+, ToStr.new(self.to_s)
  end

  def test_unary_plus
    assert_send_type "() -> String",
                     '', :+@
  end

  def test_unary_minus
    assert_send_type "() -> String",
                     '', :-@
  end

  def test_concat_op
    a = "hello "
    assert_send_type "(String) -> String",
                     a, :<<, "world"
    assert_send_type "(ToStr) -> String",
                     a, :<<, ToStr.new("world")
    assert_send_type "(Integer) -> String",
                     a, :<<, 33
    refute_send_type "(ToInt) -> String",
                     a, :<<, ToInt.new(33)
  end

  def test_cmp
    assert_send_type "(String) -> Integer",
                     "abcdef", :<=>, "abcde"
    assert_send_type "(Integer) -> nil",
                     "abcdef", :<=>, 1
  end

  def test_eq
    assert_send_type "(String) -> true",
                     "a", :==, "a"
    assert_send_type "(nil) -> false",
                     "a", :==, nil
  end

  def test_eqq
    assert_send_type "(String) -> true",
                     "a", :===, "a"
    assert_send_type "(nil) -> false",
                     "a", :===, nil
  end

  def test_match_op
    assert_send_type "(Regexp) -> Integer",
                     "a", :=~, /a/
    assert_send_type "(nil) -> nil",
                     "a", :=~, nil
  end

  def test_aref
    assert_send_type "(Integer) -> String",
                     "a", :[], 0
    assert_send_type "(ToInt) -> String",
                     "a", :[], ToInt.new(0)
    assert_send_type "(Integer) -> nil",
                     "a", :[], 1
    assert_send_type "(ToInt) -> nil",
                     "a", :[], ToInt.new(1)
    assert_send_type "(Integer, Integer) -> String",
                     "a", :[], 0, 1
    assert_send_type "(Integer, Integer) -> nil",
                     "a", :[], 2, 1
    assert_send_type "(ToInt, ToInt) -> String",
                     "a", :[], ToInt.new(0), ToInt.new(1)
    assert_send_type "(ToInt, ToInt) -> nil",
                     "a", :[], ToInt.new(2), ToInt.new(1)
    assert_send_type "(Range[Integer]) -> String",
                     "a", :[], 0..1
    assert_send_type "(Range[Integer]) -> nil",
                     "a", :[], 2..1
    assert_send_type "(Range[Integer?]) -> String",
                     "a", :[], (0...)
    assert_send_type "(Range[Integer?]) -> nil",
                     "a", :[], (2...)
    if ::RUBY_27_OR_LATER
      eval(<<~RUBY)
        assert_send_type "(Range[Integer?]) -> String",
                         "a", :[], (...0)
      RUBY
    end
    assert_send_type "(Regexp) -> String",
                     "a", :[], /a/
    assert_send_type "(Regexp) -> nil",
                     "a", :[], /b/
    assert_send_type "(Regexp, Integer) -> String",
                     "a", :[], /a/, 0
    assert_send_type "(Regexp, Integer) -> nil",
                     "a", :[], /b/, 0
    assert_send_type "(Regexp, ToInt) -> String",
                     "a", :[], /a/, ToInt.new(0)
    assert_send_type "(Regexp, ToInt) -> nil",
                     "a", :[], /b/, ToInt.new(0)
    assert_send_type "(Regexp, String) -> String",
                     "a", :[], /(?<a>a)/, "a"
    assert_send_type "(Regexp, String) -> nil",
                     "a", :[], /(?<b>b)/, "b"
    assert_send_type "(String) -> String",
                     "a", :[], "a"
    assert_send_type "(String) -> nil",
                     "a", :[], "b"
  end

  def test_aset_m
    assert_send_type "(Integer, String) -> String",
                     "foo", :[]=, 0, "bar"
    assert_send_type "(ToInt, String) -> String",
                     "foo", :[]=, ToInt.new(0), "bar"
    assert_send_type "(Integer, Integer, String) -> String",
                     "foo", :[]=, 0, 3, "bar"
    assert_send_type "(ToInt, ToInt, String) -> String",
                     "foo", :[]=, ToInt.new(0), ToInt.new(3), "bar"
    assert_send_type "(Range[Integer], String) -> String",
                     "foo", :[]=, 0..3, "bar"
    assert_send_type "(Range[Integer?], String) -> String",
                    "foo", :[]=, (0..), "bar"
    assert_send_type "(Regexp, String) -> String",
                     "foo", :[]=, /foo/, "bar"
    assert_send_type "(Regexp, Integer, String) -> String",
                     "foo", :[]=, /(foo)/, 1, "bar"
    assert_send_type "(Regexp, ToInt, String) -> String",
                     "foo", :[]=, /(foo)/, ToInt.new(1), "bar"
    assert_send_type "(Regexp, String, String) -> String",
                     "foo", :[]=, /(?<foo>foo)/, "foo", "bar"
    assert_send_type "(String, String) -> String",
                     "foo", :[]=, "foo", "bar"
  end

  def test_ascii_only?
    assert_send_type "() -> true",
                     "abc".force_encoding("UTF-8"), :ascii_only?
    assert_send_type "() -> false",
                     "abc\u{6666}".force_encoding("UTF-8"), :ascii_only?
  end

  def test_b
    assert_send_type "() -> String",
                     "a", :b
  end

  def test_bytes
    assert_send_type "() -> Array[Integer]",
                     "a", :bytes
    assert_send_type "() { (Integer) -> void } -> String",
                     "a", :bytes do |b| b end
  end

  def test_bytesize
    assert_send_type "() -> Integer",
                     "string", :bytesize
  end

  def test_byteslice
    assert_send_type "(Integer) -> String",
                     "hello", :byteslice, 1
    assert_send_type "(ToInt) -> String",
                     "hello", :byteslice, ToInt.new(1)
    assert_send_type "(Integer) -> nil",
                     "hello", :byteslice, 10
    assert_send_type "(ToInt) -> nil",
                     "hello", :byteslice, ToInt.new(10)
    assert_send_type "(Integer, Integer) -> String",
                     "hello", :byteslice, 1, 2
    assert_send_type "(ToInt, ToInt) -> String",
                     "hello", :byteslice, ToInt.new(1), ToInt.new(2)
    assert_send_type "(Integer, Integer) -> nil",
                     "hello", :byteslice, 10, 2
    assert_send_type "(ToInt, ToInt) -> nil",
                     "hello", :byteslice, ToInt.new(10), ToInt.new(2)
    assert_send_type "(Range[Integer]) -> String",
                     "\x03\u3042\xff", :byteslice, 1..3
    assert_send_type "(Range[Integer?]) -> String",
                     "\x03\u3042\xff", :byteslice, (1..)
    assert_send_type "(Range[Integer]) -> nil",
                     "\x03\u3042\xff", :byteslice, 11..13
    assert_send_type "(Range[Integer?]) -> nil",
                     "\x03\u3042\xff", :byteslice, (11..)
  end

  def test_capitalize
    assert_send_type "() -> String",
                     "a", :capitalize
    assert_send_type "(:ascii) -> String",
                     "a", :capitalize, :ascii
    assert_send_type "(:lithuanian) -> String",
                     "a", :capitalize, :lithuanian
    assert_send_type "(:turkic) -> String",
                     "a", :capitalize, :turkic
    assert_send_type "(:lithuanian, :turkic) -> String",
                     "a", :capitalize, :lithuanian, :turkic
    assert_send_type "(:turkic, :lithuanian) -> String",
                     "a", :capitalize, :turkic, :lithuanian
  end

  def test_capitalize!
    assert_send_type "() -> String",
                     "a", :capitalize!
    assert_send_type "(:ascii) -> String",
                     "a", :capitalize!, :ascii
    assert_send_type "(:lithuanian) -> String",
                     "a", :capitalize!, :lithuanian
    assert_send_type "(:turkic) -> String",
                     "a", :capitalize!, :turkic
    assert_send_type "(:lithuanian, :turkic) -> String",
                     "a", :capitalize!, :lithuanian, :turkic
    assert_send_type "(:turkic, :lithuanian) -> String",
                     "a", :capitalize!, :turkic, :lithuanian
    assert_send_type "() -> nil",
                     "", :capitalize!
    assert_send_type "(:ascii) -> nil",
                     "", :capitalize!, :ascii
    assert_send_type "(:lithuanian) -> nil",
                     "", :capitalize!, :lithuanian
    assert_send_type "(:turkic) -> nil",
                     "", :capitalize!, :turkic
    assert_send_type "(:lithuanian, :turkic) -> nil",
                     "", :capitalize!, :lithuanian, :turkic
    assert_send_type "(:turkic, :lithuanian) -> nil",
                     "", :capitalize!, :turkic, :lithuanian
  end

  def test_casecmp
    assert_send_type "(String) -> 0",
                     "a", :casecmp, "A"
    assert_send_type "(String) -> -1",
                     "a", :casecmp, "B"
    assert_send_type "(String) -> 1",
                     "b", :casecmp, "A"
    assert_send_type "(String) -> nil",
                     "\u{e4 f6 fc}".encode("ISO-8859-1"), :casecmp, "\u{c4 d6 dc}"
    assert_send_type "(Integer) -> nil",
                     "a", :casecmp , 42
  end

  def test_casecmp?
    assert_send_type "(String) -> false",
                     "aBcDeF", :casecmp?, "abcde"
    assert_send_type "(String) -> true",
                     "aBcDeF", :casecmp?, "abcdef"
    assert_send_type "(String) -> nil",
                     "\u{e4 f6 fc}".encode("ISO-8859-1"), :casecmp?, "\u{c4 d6 dc}"
    assert_send_type "(Integer) -> nil",
                     "foo", :casecmp?, 2
  end

  def test_center
    assert_send_type "(Integer) -> String",
                     "hello", :center, 4
    assert_send_type "(ToInt) -> String",
                     "hello", :center, ToInt.new(4)
    assert_send_type "(Integer, String) -> String",
                     "hello", :center, 20, '123'
    assert_send_type "(ToInt, ToStr) -> String",
                     "hello", :center, ToInt.new(20), ToStr.new('123')
  end

  def test_chars
    assert_send_type "() -> Array[String]",
                     "a", :chars
    assert_send_type "() { (String) -> void } -> String",
                     "a", :chars do |c| c end
  end

  def test_chomp
    assert_send_type "() -> String",
                     "a", :chomp
    assert_send_type "(String) -> String",
                     "a", :chomp, ""
    assert_send_type "(ToStr) -> String",
                     "a", :chomp, ToStr.new("")
  end

  def test_chomp!
    assert_send_type "() -> String",
                     "a\n", :chomp!
    assert_send_type "(String) -> String",
                     "a\n", :chomp!, "\n"
    assert_send_type "(String) -> nil",
                     "a\n", :chomp!, "\r"
    assert_send_type "(ToStr) -> String",
                     "a\n", :chomp!, ToStr.new("\n")
    assert_send_type "(ToStr) -> nil",
                     "a\n", :chomp!, ToStr.new("\r")
  end

  def test_chop
    assert_send_type "() -> String",
                     "a", :chop
  end

  def test_chop!
    assert_send_type "() -> String",
                     "a", :chop!
    assert_send_type "() -> nil",
                     "", :chop!
  end

  def test_chr
    assert_send_type "() -> String",
                     "a", :chr
  end

  def test_clear
    assert_send_type "() -> String",
                     "a", :clear
  end

  def test_codepoints
    assert_send_type "() -> Array[Integer]",
                     "a", :codepoints
    assert_send_type "() { (Integer) -> void } -> String",
                     "a", :codepoints do |cp| cp end
  end

  def test_concat
    assert_send_type "() -> String",
                     "hello", :concat
    assert_send_type "(String) -> String",
                     "hello", :concat, " "
    assert_send_type "(ToStr) -> String",
                     "hello", :concat, ToStr.new(" ")
    assert_send_type "(String, Integer) -> String",
                     "hello", :concat, "world", 33
    refute_send_type "(ToInt) -> String",
                     "hello", :concat, ToInt.new
  end

  def test_count
    assert_send_type "(String) -> Integer",
                     "hello world", :count, "lo"
    assert_send_type "(ToStr) -> Integer",
                     "hello world", :count, ToStr.new("lo")
    assert_send_type "(String, String) -> Integer",
                     "hello world", :count, "lo", "o"
    assert_send_type "(ToStr, ToStr) -> Integer",
                     "hello world", :count, ToStr.new("lo"), ToStr.new("o")
    assert_send_type "(String, String, String) -> Integer",
                     "hello world", :count, "lo", "o", "o"
    assert_send_type "(ToStr, ToStr, ToStr) -> Integer",
                     "hello world", :count, ToStr.new("lo"), ToStr.new("o"), ToStr.new("o")
  end

  def test_crypt
    assert_send_type "(String) -> String",
                     "foo", :crypt, "bar"
    assert_send_type "(ToStr) -> String",
                     "foo", :crypt, ToStr.new("bar")
  end

  def test_delete
    assert_send_type "(String, String) -> String",
                     "hello", :delete, "l", "lo"
    assert_send_type "(ToStr, ToStr) -> String",
                     "hello", :delete, ToStr.new("l"), ToStr.new("lo")
    assert_send_type "(String) -> String",
                     "hello", :delete, "lo"
    assert_send_type "(ToStr) -> String",
                     "hello", :delete, ToStr.new("lo")
  end

  def test_delete!
    assert_send_type "(String, String) -> String",
                     "hello", :delete!, "l", "lo"
    assert_send_type "(ToStr, ToStr) -> String",
                     "hello", :delete!, ToStr.new("l"), ToStr.new("lo")
    assert_send_type "(String) -> String",
                     "hello", :delete!, "lo"
    assert_send_type "(ToStr) -> String",
                     "hello", :delete!, ToStr.new("lo")
    assert_send_type "(String) -> nil",
                     "hello", :delete!, "a"
    assert_send_type "(ToStr) -> nil",
                     "hello", :delete!, ToStr.new("a")
  end

  def test_delete_prefix
    assert_send_type "(String) -> String",
                     "foo", :delete_prefix, "f"
    assert_send_type "(ToStr) -> String",
                     "foo", :delete_prefix, ToStr.new("f")
  end

  def test_delete_prefix!
    assert_send_type "(String) -> String",
                     "foo", :delete_prefix!, "f"
    assert_send_type "(ToStr) -> String",
                     "foo", :delete_prefix!, ToStr.new("f")
    assert_send_type "(String) -> nil",
                     "foo", :delete_prefix!, "a"
    assert_send_type "(ToStr) -> nil",
                     "foo", :delete_prefix!, ToStr.new("a")
  end

  def test_delete_suffix
    assert_send_type "(String) -> String",
                     "foo", :delete_suffix, "o"
    assert_send_type "(ToStr) -> String",
                     "foo", :delete_suffix, ToStr.new("o")
  end

  def test_delete_suffix!
    assert_send_type "(String) -> String",
                     "foo", :delete_suffix!, "o"
    assert_send_type "(ToStr) -> String",
                     "foo", :delete_suffix!, ToStr.new("o")
    assert_send_type "(String) -> nil",
                     "foo", :delete_suffix!, "a"
    assert_send_type "(ToStr) -> nil",
                     "foo", :delete_suffix!, ToStr.new("a")
  end

  def test_downcase
    assert_send_type "() -> String",
                     "a", :downcase
    assert_send_type "(:ascii) -> String",
                     "a", :downcase, :ascii
    assert_send_type "(:fold) -> String",
                     "a", :downcase, :fold
    assert_send_type "(:lithuanian) -> String",
                     "a", :downcase, :lithuanian
    assert_send_type "(:turkic) -> String",
                     "a", :downcase, :turkic
    assert_send_type "(:lithuanian, :turkic) -> String",
                     "a", :downcase, :lithuanian, :turkic
    assert_send_type "(:turkic, :lithuanian) -> String",
                     "a", :downcase, :turkic, :lithuanian
  end

  def test_downcase!
    assert_send_type "() -> nil",
                     "a", :downcase!
    assert_send_type "(:ascii) -> nil",
                     "a", :downcase!, :ascii
    assert_send_type "(:fold) -> nil",
                     "a", :downcase!, :fold
    assert_send_type "(:lithuanian) -> nil",
                     "a", :downcase!, :lithuanian
    assert_send_type "(:turkic) -> nil",
                     "a", :downcase!, :turkic
    assert_send_type "(:lithuanian, :turkic) -> nil",
                     "a", :downcase!, :lithuanian, :turkic
    assert_send_type "(:turkic, :lithuanian) -> nil",
                     "a", :downcase!, :turkic, :lithuanian
    assert_send_type "() -> String",
                     "A", :downcase!
    assert_send_type "(:ascii) -> String",
                     "A", :downcase!, :ascii
    assert_send_type "(:fold) -> String",
                     "A", :downcase!, :fold
    assert_send_type "(:lithuanian) -> String",
                     "A", :downcase!, :lithuanian
    assert_send_type "(:turkic) -> String",
                     "A", :downcase!, :turkic
    assert_send_type "(:lithuanian, :turkic) -> String",
                     "A", :downcase!, :lithuanian, :turkic
    assert_send_type "(:turkic, :lithuanian) -> String",
                     "A", :downcase!, :turkic, :lithuanian
  end

  def test_dump
    assert_send_type "() -> String",
                     "foo", :dump
  end

  def test_each_byte
    assert_send_type "() -> Enumerator[Integer, self]",
                     "hello", :each_byte
    assert_send_type "() { (Integer) -> void } -> self",
                     "hello", :each_byte do |c| c end
  end

  def test_each_char
    assert_send_type "() -> Enumerator[String, self]",
                     "hello", :each_char
    assert_send_type "() { (String) -> void } -> self",
                     "hello", :each_char do |c| c end
  end

  def test_each_codepoint
    assert_send_type "() -> Enumerator[Integer, self]",
                     "hello", :each_codepoint
    assert_send_type "() { (Integer) -> void } -> self",
                     "hello", :each_codepoint do |c| c end
  end

  def test_each_grapheme_cluster
    assert_send_type "() -> Enumerator[String, self]",
                     "hello", :each_grapheme_cluster
    assert_send_type "() { (String) -> void } -> self",
                     "hello", :each_grapheme_cluster do |c| c end
  end

  def test_each_line
    assert_send_type "() -> Enumerator[String, self]",
                     "hello", :each_line
    assert_send_type "() { (String) -> void } -> self",
                     "hello", :each_line do |line| line end
    assert_send_type "(String) -> Enumerator[String, self]",
                     "hello", :each_line, "l"
    assert_send_type "(ToStr) -> Enumerator[String, self]",
                     "hello", :each_line, ToStr.new("l")
    assert_send_type "(String) { (String) -> void } -> self",
                     "hello", :each_line, "l" do |line| line end
    assert_send_type "(ToStr) { (String) -> void } -> self",
                     "hello", :each_line, ToStr.new("l") do |line| line end
    assert_send_type "(chomp: true) -> Enumerator[String, self]",
                     "hello", :each_line, chomp: true
    assert_send_type "(chomp: false) -> Enumerator[String, self]",
                     "hello", :each_line, chomp: false
    assert_send_type "(chomp: true) { (String) -> void } -> self",
                     "hello", :each_line, chomp: true do |line| line end
    assert_send_type "(chomp: false){ (String)  -> void } -> self",
                     "hello", :each_line, chomp: false do |line| line end
    assert_send_type "(String, chomp: true) -> Enumerator[String, self]",
                     "hello", :each_line, "l", chomp: true
    assert_send_type "(ToStr, chomp: true) -> Enumerator[String, self]",
                     "hello", :each_line, ToStr.new("l"), chomp: true
    assert_send_type "(String, chomp: false) -> Enumerator[String, self]",
                     "hello", :each_line, "l", chomp: false
    assert_send_type "(ToStr, chomp: false) -> Enumerator[String, self]",
                     "hello", :each_line, ToStr.new("l"), chomp: false
    assert_send_type "(String, chomp: true) { (String) -> void } -> self",
                     "hello", :each_line, "l", chomp: true do |line| line end
    assert_send_type "(ToStr, chomp: true) { (String) -> void } -> self",
                     "hello", :each_line, ToStr.new("l"), chomp: true do |line| line end
    assert_send_type "(String, chomp: false) { (String) -> void } -> self",
                     "hello", :each_line, "l", chomp: false do |line| line end
    assert_send_type "(ToStr, chomp: false) { (String) -> void } -> self",
                     "hello", :each_line, ToStr.new("l"), chomp: false do |line| line end
  end

  def test_empty?
    assert_send_type "() -> true",
                     "", :empty?
    assert_send_type "() -> false",
                     " ", :empty?
  end

  def test_encode
    assert_send_type "(String) -> String",
                     "string", :encode, "ascii"
    assert_send_type "(String, Encoding) -> String",
                     "string", :encode, "ascii", Encoding::ASCII_8BIT
    assert_send_type "(Encoding, String) -> String",
                     "string", :encode, Encoding::ASCII_8BIT, "ascii"
    assert_send_type "(String, invalid: :replace) -> String",
                     "string", :encode, "ascii", invalid: :replace
    assert_send_type "(Encoding, Encoding, undef: nil) -> String",
                     "string", :encode, Encoding::ASCII_8BIT, Encoding::ASCII_8BIT, undef: nil
    assert_send_type "(invalid: nil, undef: :replace, replace: String, fallback: Hash[String, String], xml: :text, universal_newline: true) -> String",
                     "string", :encode,
                     invalid: nil,
                     undef: :replace,
                     replace: "foo",
                     fallback: {"a" => "a"},
                     xml: :text,
                     universal_newline: true
    assert_send_type "(xml: :attr) -> String",
                     "string", :encode, xml: :attr
    assert_send_type "(fallback: Proc) -> String",
                     "string", :encode, fallback: proc { |s| s }
    assert_send_type "(fallback: Method) -> String",
                     "string", :encode, fallback: "test".method(:+)
    assert_send_type "(fallback: ArefFromStringToString) -> String",
                     "string", :encode, fallback: ArefFromStringToString.new
    assert_send_type "(cr_newline: true) -> String",
                     "string", :encode, cr_newline: true
    assert_send_type "(crlf_newline: true) -> String",
                     "string", :encode, crlf_newline: true
    assert_send_type "(ToStr, ToStr) -> String",
                     "string", :encode, ToStr.new("ascii"), ToStr.new("ascii")
  end

  def test_encode!
    assert_send_type "(String) -> self",
                     "string", :encode!, "ascii"
    assert_send_type "(String, Encoding) -> self",
                     "string", :encode!, "ascii", Encoding::ASCII_8BIT
    assert_send_type "(Encoding, String) -> self",
                     "string", :encode!, Encoding::ASCII_8BIT, "ascii"
    assert_send_type "(String, invalid: :replace) -> self",
                     "string", :encode!, "ascii", invalid: :replace
    assert_send_type "(Encoding, Encoding, undef: nil) -> self",
                     "string", :encode!, Encoding::ASCII_8BIT, Encoding::ASCII_8BIT, undef: nil
    assert_send_type "(invalid: nil, undef: :replace, replace: String, fallback: Hash[String, String], xml: :text, universal_newline: true) -> self",                 
                     "string", :encode!, 
                     invalid: nil,
                     undef: :replace,
                     replace: "foo",
                     fallback: {"a" => "a"},
                     xml: :text,
                     universal_newline: true
    assert_send_type "(xml: :attr) -> self",
                     "string", :encode!, xml: :attr
    assert_send_type "(fallback: Proc) -> self",
                     "string", :encode!, fallback: proc { |s| s }
    assert_send_type "(fallback: Method) -> self",
                     "string", :encode!, fallback: "test".method(:+)
    assert_send_type "(fallback: ArefFromStringToString) -> String",
                     "string", :encode, fallback: ArefFromStringToString.new
    assert_send_type "(cr_newline: true) -> self",
                     "string", :encode!, cr_newline: true
    assert_send_type "(crlf_newline: true) -> self",
                     "string", :encode!, crlf_newline: true
    assert_send_type "(ToStr, ToStr) -> self",
                     "string", :encode!, ToStr.new("ascii"), ToStr.new("ascii")
  end

  def test_encoding
    assert_send_type "() -> Encoding",
                     "test", :encoding
  end

  def test_end_with?
    assert_send_type "() -> false",
                     "string", :end_with?
    assert_send_type "(String) -> true",
                     "string", :end_with?, "string"
    assert_send_type "(String, String) -> false",
                     "string", :end_with?, "foo", "bar"
    assert_send_type "(ToStr) -> true",
                     "string", :end_with?, ToStr.new("string")
  end

  def test_eql?
    str = "string"
    assert_send_type "(String) -> true",
                     str, :eql?, str
    assert_send_type "(Integer) -> false",
                     "string", :eql?, 42
  end

  def test_force_encoding
    assert_send_type "(String) -> self",
                     "", :force_encoding, "ASCII-8BIT"
    assert_send_type "(Encoding) -> self",
                     "", :force_encoding, Encoding::ASCII_8BIT
    assert_send_type "(ToStr) -> self",
                     "", :force_encoding, ToStr.new("ASCII-8BIT")
  end

  def test_freeze
    assert_send_type "() -> self",
                     "test", :freeze
  end

  def test_getbyte
    assert_send_type "(Integer) -> Integer",
                     "a", :getbyte, 0
    assert_send_type "(Integer) -> nil",
                     "a", :getbyte, 1
    assert_send_type "(ToInt) -> Integer",
                     "a", :getbyte, ToInt.new(0)
    assert_send_type "(ToInt) -> nil",
                     "a", :getbyte, ToInt.new(1)
  end

  def test_grapheme_clusters
    assert_send_type "() -> Array[String]",
                     "\u{1F1EF}\u{1F1F5}", :grapheme_clusters
  end

  def test_gsub
    assert_send_type "(Regexp, String) -> String",
                     "string", :gsub, /./, ""
    assert_send_type "(String, String) -> String",
                     "string", :gsub, "a", "b"
    assert_send_type "(Regexp) { (String) -> String } -> String",
                     "string", :gsub, /./ do |x| "" end
    assert_send_type "(Regexp) { (String) -> ToS } -> String",
                     "string", :gsub, /./ do |x| ToS.new("") end
    assert_send_type "(Regexp, Hash[String, String]) -> String",
                     "string", :gsub, /./, {"foo" => "bar"}
    assert_send_type "(Regexp) -> Enumerator[String, self]",
                     "string", :gsub, /./
    assert_send_type "(String) -> Enumerator[String, self]",
                     "string", :gsub, ""
    assert_send_type "(ToStr, ToStr) -> String",
                     "string", :gsub, ToStr.new("a"), ToStr.new("b")
  end

  def test_gsub!
    assert_send_type "(Regexp, String) -> nil",
                     "string", :gsub!, /z/, "s"
    assert_send_type "(Regexp, String) -> self",
                     "string", :gsub!, /s/, "s"
    assert_send_type "(String, String) -> nil",
                     "string", :gsub!, "z", "s"
    assert_send_type "(String, String) -> self",
                     "string", :gsub!, "s", "s"
    assert_send_type "(Regexp) { (String) -> String } -> nil",
                     "string", :gsub!, /z/ do |x| "s" end
    assert_send_type "(Regexp) { (String) -> String } -> self",
                     "string", :gsub!, /s/ do |x| "s" end
    assert_send_type "(Regexp) { (String) -> ToS } -> self",
                     "string", :gsub!, /s/ do |x| ToS.new("s") end
    assert_send_type "(Regexp, Hash[String, String]) -> nil",
                     "string", :gsub!, /z/, {"z" => "s"}
    assert_send_type "(Regexp, Hash[String, String]) -> self",
                     "string", :gsub!, /s/, {"s" => "s"}
    # assert_send_type "(Regexp) -> Enumerator[String, self]",
    #                  "string", :gsub!, /s/
    # assert_send_type "(String) -> Enumerator[String, self]",
    #                  "string", :gsub!, "s"
    assert_send_type "(ToStr, ToStr) -> String",
                     "string", :gsub!, ToStr.new("s"), ToStr.new("s")
  end

  def test_hash
    assert_send_type "() -> Integer",
                     "", :hash
  end

  def test_hex
    assert_send_type "() -> Integer",
                     "0x0a", :hex
  end

  def test_include?
    assert_send_type "(String) -> true",
                     "", :include?, ""
    assert_send_type "(String) -> false",
                     "", :include?, "a"
    assert_send_type "(ToStr) -> true",
                     "", :include?, ToStr.new("")
    assert_send_type "(ToStr) -> false",
                     "", :include?, ToStr.new("a")
  end

  def test_index
    assert_send_type "(String) -> Integer",
                     "a", :index, "a"
    assert_send_type "(String, Integer) -> Integer",
                     "a", :index, "a", 0
    assert_send_type "(String) -> nil",
                     "a", :index, "b"
    assert_send_type "(Regexp) -> Integer",
                     "a", :index, /a/
    assert_send_type "(Regexp, Integer) -> Integer",
                     "a", :index, /a/, 0
    assert_send_type "(ToStr) -> Integer",
                     "a", :index, ToStr.new("a")
    assert_send_type "(ToStr, ToInt) -> nil",
                     "a", :index, ToStr.new("a"), ToInt.new(1)
  end

  def test_insert
    assert_send_type "(Integer, String) -> String",
                     "abcd", :insert, 0, "X"
    assert_send_type "(ToInt, ToStr) -> String",
                     "abcd", :insert, ToInt.new(0), ToStr.new("X")
  end

  def test_inspect
    assert_send_type "() -> String",
                     "", :inspect
  end

  def test_intern
    assert_send_type "() -> Symbol",
                     "", :intern
  end

  def test_length
    assert_send_type "() -> Integer",
                     "", :length
  end

  def test_lines
    assert_send_type "() -> Array[String]",
                     "", :lines
    assert_send_type "(chomp: true) -> Array[String]",
                     "", :lines, chomp: true
    assert_send_type "(chomp: false) -> Array[String]",
                     "", :lines, chomp: false
    assert_send_type "(String) -> Array[String]",
                     "", :lines, "\n"
    assert_send_type "(String, chomp: true) -> Array[String]",
                     "", :lines, "\n", chomp: true
    assert_send_type "(String, chomp: false) -> Array[String]",
                     "", :lines, "\n", chomp: false
    assert_send_type "(ToStr) -> Array[String]",
                     "", :lines, ToStr.new("\n")
  end

  def test_ljust
    assert_send_type "(Integer) -> String",
                     "hello", :ljust, 20
    assert_send_type "(Integer, String) -> String",
                     "hello", :ljust, 20, " "
    assert_send_type "(ToInt, ToStr) -> String",
                     "hello", :ljust, ToInt.new(20), ToStr.new(" ")
  end

  def test_lstrip
    assert_send_type "() -> String",
                     "", :lstrip
  end

  def test_lstrip!
    assert_send_type "() -> nil",
                     "", :lstrip!
    assert_send_type "() -> self",
                     " test ", :lstrip!
  end

  def test_match
    assert_send_type "(Regexp) -> MatchData",
                     "a", :match, /a/
    assert_send_type "(Regexp) -> nil",
                     "a", :match, /b/
    assert_send_type "(String) -> MatchData",
                     "a", :match, "a"
    assert_send_type "(String) -> nil",
                     "a", :match, "b"
    assert_send_type "(ToStr) -> MatchData",
                     "a", :match, ToStr.new("a")
    assert_send_type "(ToStr) -> nil",
                     "a", :match, ToStr.new("b")
    assert_send_type "(Regexp, Integer) -> MatchData",
                     "a", :match, /a/, 0
    assert_send_type "(Regexp, Integer) -> nil",
                     "a", :match, /a/, 1
    assert_send_type "(String, Integer) -> MatchData",
                     "a", :match, "a", 0
    assert_send_type "(String, Integer) -> nil",
                     "a", :match, "a", 1
    assert_send_type "(ToStr, Integer) -> MatchData",
                     "a", :match, ToStr.new("a"), 0
    assert_send_type "(ToStr, Integer) -> nil",
                     "a", :match, ToStr.new("a"), 1
    assert_send_type "(Regexp, ToInt) -> MatchData",
                     "a", :match, /a/, ToInt.new(0)
    assert_send_type "(Regexp, ToInt) -> nil",
                     "a", :match, /a/, ToInt.new(1)
    assert_send_type "(String, ToInt) -> MatchData",
                     "a", :match, "a", ToInt.new(0)
    assert_send_type "(String, ToInt) -> nil",
                     "a", :match, "a", ToInt.new(1)
    assert_send_type "(ToStr, ToInt) -> MatchData",
                     "a", :match, ToStr.new("a"), ToInt.new(0)
    assert_send_type "(ToStr, ToInt) -> nil",
                     "a", :match, ToStr.new("a"), ToInt.new(1)
  end

  def test_match?
    assert_send_type "(Regexp) -> true",
                     "a", :match?, /a/
    assert_send_type "(Regexp) -> false",
                     "a", :match?, /b/
    assert_send_type "(String) -> true",
                     "a", :match?, "a"
    assert_send_type "(String) -> false",
                     "a", :match?, "b"
    assert_send_type "(ToStr) -> true",
                     "a", :match?, ToStr.new("a")
    assert_send_type "(ToStr) -> false",
                     "a", :match?, ToStr.new("b")
    assert_send_type "(Regexp, Integer) -> true",
                     "a", :match?, /a/, 0
    assert_send_type "(Regexp, Integer) -> false",
                     "a", :match?, /a/, 1
    assert_send_type "(String, Integer) -> true",
                     "a", :match?, "a", 0
    assert_send_type "(String, Integer) -> false",
                     "a", :match?, "a", 1
    assert_send_type "(ToStr, Integer) -> true",
                     "a", :match?, ToStr.new("a"), 0
    assert_send_type "(ToStr, Integer) -> false",
                     "a", :match?, ToStr.new("a"), 1
    assert_send_type "(Regexp, ToInt) -> true",
                     "a", :match?, /a/, ToInt.new(0)
    assert_send_type "(Regexp, ToInt) -> false",
                     "a", :match?, /a/, ToInt.new(1)
    assert_send_type "(String, ToInt) -> true",
                     "a", :match?, "a", ToInt.new(0)
    assert_send_type "(String, ToInt) -> false",
                     "a", :match?, "a", ToInt.new(1)
    assert_send_type "(ToStr, ToInt) -> true",
                     "a", :match?, ToStr.new("a"), ToInt.new(0)
    assert_send_type "(ToStr, ToInt) -> false",
                     "a", :match?, ToStr.new("a"), ToInt.new(1)
  end

  def test_next
    assert_send_type "() -> String",
                     "a", :next
  end

  def test_next!
    assert_send_type "() -> self",
                     "a", :next!
  end

  def test_oct
    assert_send_type "() -> Integer",
                     "123", :oct
  end

  def test_ord
    assert_send_type "() -> Integer",
                     "a", :ord
  end

  def test_partition
    assert_send_type "(String) -> [ String, String, String ]",
                     "hello", :partition, "l"
    assert_send_type "(ToStr) -> [ String, String, String ]",
                     "hello", :partition, ToStr.new("l")
    assert_send_type "(Regexp) -> [ String, String, String ]",
                     "hello", :partition, /.l/
  end

  def test_prepend
    assert_send_type "() -> String",
                     "a", :prepend
    assert_send_type "(String) -> String",
                     "a", :prepend, "b"
    assert_send_type "(String, String) -> String",
                     "a", :prepend, "b", "c"
    assert_send_type "(ToStr) -> String",
                     "a", :prepend, ToStr.new("b")
    assert_send_type "(ToStr, ToStr) -> String",
                     "a", :prepend, ToStr.new("b"), ToStr.new("c")
  end

  def test_replace
    assert_send_type "(String) -> String",
                     "a", :replace, "b"
    assert_send_type "(ToStr) -> String",
                     "a", :replace, ToStr.new("b")
  end

  def test_reverse
    assert_send_type "() -> String",
                     "test", :reverse
  end

  def test_reverse!
    assert_send_type "() -> self",
                     "test", :reverse!
  end

  def test_rindex
    assert_send_type "(String) -> Integer",
                     "a", :rindex, "a"
    assert_send_type "(String, Integer) -> Integer",
                     "a", :rindex, "a", 0
    assert_send_type "(String) -> nil",
                     "a", :rindex, "b"
    assert_send_type "(Regexp) -> Integer",
                     "a", :rindex, /a/
    assert_send_type "(Regexp, Integer) -> Integer",
                     "a", :rindex, /a/, 0
    assert_send_type "(ToStr) -> Integer",
                     "a", :rindex, ToStr.new("a")
    assert_send_type "(ToStr, ToInt) -> nil",
                     "a", :rindex, ToStr.new("a"), ToInt.new(-2)
  end

  def test_rjust
    assert_send_type "(Integer) -> String",
                     "hello", :rjust, 20
    assert_send_type "(ToInt) -> String",
                     "hello", :rjust, ToInt.new(20)
    assert_send_type "(Integer, String) -> String",
                     "hello", :rjust, 20, " "
    assert_send_type "(ToInt, ToStr) -> String",
                     "hello", :rjust, ToInt.new(20), ToStr.new(" ")
  end

  def test_rpartition
    assert_send_type "(String) -> [ String, String, String ]",
                     "hello", :rpartition, "l"
    assert_send_type "(ToStr) -> [ String, String, String ]",
                     "hello", :rpartition, ToStr.new("l")
    assert_send_type "(Regexp) -> [ String, String, String ]",
                     "hello", :rpartition, /.l/
  end

  def test_rstrip
    assert_send_type "() -> String",
                     " hello ", :rstrip
  end

  def test_rstrip!
    assert_send_type "() -> self",
                     " hello ", :rstrip!
    assert_send_type "() -> nil",
                     "", :rstrip!
  end

  def test_scan
    assert_send_type "(Regexp) -> Array[String]",
                     "a", :scan, /a/
    assert_send_type "(Regexp) -> Array[Array[String]]",
                     "a", :scan, /(a)/
    assert_send_type "(String) -> Array[String]",
                     "a", :scan, "a"
    assert_send_type "(ToStr) -> Array[String]",
                     "a", :scan, ToStr.new("a")
    assert_send_type "(Regexp) { (String) -> void } -> self",
                     "a", :scan, /a/ do |arg| arg end
    assert_send_type "(Regexp) { (Array[String]) -> void } -> self",
                     "a", :scan, /(a)/ do |arg| arg end
    assert_send_type "(String) { (String) -> void } -> self",
                     "a", :scan, "a" do |arg| arg end
    assert_send_type "(ToStr) { (String) -> void } -> self",
                     "a", :scan, ToStr.new("a") do |arg| arg end
  end

  def test_scrub
    assert_send_type "() -> String",
                     "\x81", :scrub
    assert_send_type "(String) -> String",
                     "\x81", :scrub, "*"
    assert_send_type "(ToStr) -> String",
                     "\x81", :scrub, ToStr.new("*")
    assert_send_type "() { (String) -> String } -> String",
                     "\x81", :scrub do |s| "*" end
    assert_send_type "() { (String) -> ToStr } -> String",
                     "\x81", :scrub do |s| ToStr.new("*") end
  end

  def test_scrub!
    assert_send_type "() -> self",
                     "\x81", :scrub!
    assert_send_type "(String) -> self",
                     "\x81", :scrub!, "*"
    assert_send_type "(ToStr) -> self",
                     "\x81", :scrub!, ToStr.new("*")
    assert_send_type "() { (String) -> String } -> self",
                     "\x81", :scrub! do |s| "*" end
    assert_send_type "() { (String) -> ToStr } -> self",
                     "\x81", :scrub! do |s| ToStr.new("*") end
  end

  def test_setbyte
    assert_send_type "(Integer, Integer) -> Integer",
                     " ", :setbyte, 0, 0x20
    assert_send_type "(ToInt, ToInt) -> ToInt",
                     " ", :setbyte, ToInt.new(0), ToInt.new(0x20)
  end

  def test_slice!
    assert_send_type "(Integer) -> String",
                     "a", :slice!, 0
    assert_send_type "(ToInt) -> String",
                     "a", :slice!, ToInt.new(0)
    assert_send_type "(Integer) -> nil",
                     "a", :slice!, 1
    assert_send_type "(ToInt) -> nil",
                     "a", :slice!, ToInt.new(1)
    assert_send_type "(Integer, Integer) -> String",
                     "a", :slice!, 0, 1
    assert_send_type "(ToInt, ToInt) -> String",
                     "a", :slice!, ToInt.new(0), ToInt.new(1)
    assert_send_type "(Integer, Integer) -> nil",
                     "a", :slice!, 2, 1
    assert_send_type "(ToInt, ToInt) -> nil",
                     "a", :slice!, ToInt.new(2), ToInt.new(1)
    assert_send_type "(Range[Integer]) -> String",
                     "a", :slice!, 0..1
    assert_send_type "(Range[Integer]) -> nil",
                     "a", :slice!, 2..3
    assert_send_type "(Range[Integer?]) -> String",
                     "a", :slice!, (0..)
    assert_send_type "(Range[Integer?]) -> String",
                     "a", :slice!, (..1)
    assert_send_type "(Regexp) -> String",
                     "a", :slice!, /a/
    assert_send_type "(Regexp, Integer) -> String",
                     "a", :slice!, /(a)/, 1
    assert_send_type "(Regexp, ToInt) -> String",
                     "a", :slice!, /(a)/, ToInt.new(1)
    assert_send_type "(Regexp, String) -> String",
                     "a", :slice!, /(?<a>a)/, "a"
    assert_send_type "(Regexp) -> nil",
                     "a", :slice!, /b/
    assert_send_type "(String) -> String",
                     "a", :slice!, "a"
    assert_send_type "(String) -> nil",
                     "a", :slice!, "b"
  end

  def test_split
    assert_send_type "() -> Array[String]",
                     "a b c", :split
    assert_send_type "(String) -> Array[String]",
                     "a b c", :split, " "
    assert_send_type "(ToStr) -> Array[String]",
                     "a b c", :split, ToStr.new(" ")
    assert_send_type "(Regexp) -> Array[String]",
                     "a b c", :split, / /
    assert_send_type "(String, Integer) -> Array[String]",
                     "a b c", :split, " ", 2
    assert_send_type "(ToStr, Integer) -> Array[String]",
                     "a b c", :split, ToStr.new(" "), 2
    assert_send_type "(Regexp, Integer) -> Array[String]",
                     "a b c", :split, / /, 2
    assert_send_type "(String, ToInt) -> Array[String]",
                     "a b c", :split, " ", ToInt.new(2)
    assert_send_type "(ToStr, ToInt) -> Array[String]",
                     "a b c", :split, ToStr.new(" "), ToInt.new(2)
    assert_send_type "(Regexp, ToInt) -> Array[String]",
                     "a b c", :split, / /, ToInt.new(2)
    assert_send_type "() { (String) -> void } -> self",
                     "a b c", :split do |str| str end
    assert_send_type "(String) { (String) -> void } -> self",
                     "a b c", :split, " " do |str| str end
    assert_send_type "(ToStr) { (String) -> void } -> self",
                     "a b c", :split, ToStr.new(" ") do |str| str end
    assert_send_type "(Regexp) { (String) -> void } -> self",
                     "a b c", :split, / / do |str| str end
    assert_send_type "(String, Integer) { (String) -> void } -> self",
                     "a b c", :split, " ", 2 do |str| str end
    assert_send_type "(ToStr, Integer) { (String) -> void } -> self",
                     "a b c", :split, ToStr.new(" "), 2 do |str| str end
    assert_send_type "(Regexp, Integer) { (String) -> void } -> self",
                     "a b c", :split, / /, 2 do |str| str end
    assert_send_type "(String, ToInt) { (String) -> void } -> self",
                     "a b c", :split, " ", ToInt.new(2) do |str| str end
    assert_send_type "(ToStr, ToInt) { (String) -> void } -> self",
                     "a b c", :split, ToStr.new(" "), ToInt.new(2) do |str| str end
    assert_send_type "(Regexp, ToInt) { (String) -> void } -> self",
                     "a b c", :split, / /, ToInt.new(2) do |str| str end
  end

  def test_squeeze
    assert_send_type "() -> String",
                     "aa  bb  cc", :squeeze
    assert_send_type "(String) -> String",
                     "aa  bb  cc", :squeeze, " "
    assert_send_type "(ToStr) -> String",
                     "aa  bb  cc", :squeeze, ToStr.new(" ")
    assert_send_type "(String, String) -> String",
                     "aa  bb  cc", :squeeze, "a-z", "b"
    assert_send_type "(ToStr, ToStr) -> String",
                     "aa  bb  cc", :squeeze, ToStr.new("a-z"), ToStr.new("b")
  end

  def test_squeeze!
    assert_send_type "() -> self",
                     "aa  bb  cc", :squeeze!
    assert_send_type "(String) -> self",
                     "aa  bb  cc", :squeeze!, " "
    assert_send_type "(ToStr) -> self",
                     "aa  bb  cc", :squeeze!, ToStr.new(" ")
    assert_send_type "(String, String) -> self",
                     "aa  bb  cc", :squeeze!, "a-z", "b"
    assert_send_type "(ToStr, ToStr) -> self",
                     "aa  bb  cc", :squeeze!, ToStr.new("a-z"), ToStr.new("b")
    assert_send_type "() -> nil",
                     "", :squeeze!
    assert_send_type "(String) -> nil",
                     "", :squeeze!, " "
    assert_send_type "(ToStr) -> nil",
                     "", :squeeze!, ToStr.new(" ")
    assert_send_type "(String, String) -> nil",
                     "", :squeeze!, "a-z", "b"
    assert_send_type "(ToStr, ToStr) -> nil",
                     "", :squeeze!, ToStr.new("a-z"), ToStr.new("b")
  end

  def test_start_with?
    assert_send_type "() -> false",
                     "a", :start_with?
    assert_send_type "(String) -> true",
                     "a", :start_with?, "a"
    assert_send_type "(String) -> false",
                     "a", :start_with?, "b"
    assert_send_type "(String, String) -> true",
                     "a", :start_with?, "b", "a"
    assert_send_type "(ToStr) -> true",
                     "a", :start_with?, ToStr.new("a")
    assert_send_type "(ToStr) -> false",
                     "a", :start_with?, ToStr.new("b")
    assert_send_type "(ToStr, ToStr) -> true",
                     "a", :start_with?, ToStr.new("b"), ToStr.new("a")
  end

  def test_strip
    assert_send_type "() -> String",
                     " a ", :strip
  end

  def test_strip!
    assert_send_type "() -> self",
                     " a ", :strip!
    assert_send_type "() -> nil",
                     "a", :strip!
  end

  def test_sub
    assert_send_type "(Regexp, String) -> String",
                     "a", :sub, /a/, "a"
    assert_send_type "(String, String) -> String",
                     "a", :sub, "a", "a"
    assert_send_type "(ToStr, String) -> String",
                     "a", :sub, ToStr.new("a"), "a"
    assert_send_type "(Regexp, ToStr) -> String",
                     "a", :sub, /a/, ToStr.new("a")
    assert_send_type "(String, ToStr) -> String",
                     "a", :sub, "a", ToStr.new("a")
    assert_send_type "(ToStr, ToStr) -> String",
                     "a", :sub, ToStr.new("a"), ToStr.new("a")
    assert_send_type "(Regexp, Hash[String, String]) -> String",
                     "a", :sub, /a/, { "a" => "a" }
    assert_send_type "(String, Hash[String, String]) -> String",
                     "a", :sub, "a", { "a" => "a" }
    assert_send_type "(ToStr, Hash[String, String]) -> String",
                     "a", :sub, ToStr.new("a"), { "a" => "a" }
    assert_send_type "(Regexp) { (String) -> ToS } -> String",
                     "a", :sub, /a/ do |str| ToS.new(str) end
    assert_send_type "(String) { (String) -> ToS } -> String",
                     "a", :sub, "a" do |str| ToS.new(str) end
    assert_send_type "(ToStr) { (String) -> ToS } -> String",
                     "a", :sub, ToStr.new("a") do |str| ToS.new(str) end
  end


  def test_sub!
    assert_send_type "(Regexp, String) -> self",
                     "a", :sub!, /a/, "a"
    assert_send_type "(String, String) -> self",
                     "a", :sub!, "a", "a"
    assert_send_type "(ToStr, String) -> self",
                     "a", :sub!, ToStr.new("a"), "a"
    assert_send_type "(Regexp, ToStr) -> self",
                     "a", :sub!, /a/, ToStr.new("a")
    assert_send_type "(String, ToStr) -> self",
                     "a", :sub!, "a", ToStr.new("a")
    assert_send_type "(ToStr, ToStr) -> self",
                     "a", :sub!, ToStr.new("a"), ToStr.new("a")
    assert_send_type "(Regexp, Hash[String, String]) -> self",
                     "a", :sub!, /a/, { "a" => "a" }
    assert_send_type "(String, Hash[String, String]) -> self",
                     "a", :sub!, "a", { "a" => "a" }
    assert_send_type "(ToStr, Hash[String, String]) -> self",
                     "a", :sub!, ToStr.new("a"), { "a" => "a" }
    assert_send_type "(Regexp) { (String) -> ToS } -> self",
                     "a", :sub!, /a/ do |str| ToS.new(str) end
    assert_send_type "(String) { (String) -> ToS } -> self",
                     "a", :sub!, "a" do |str| ToS.new(str) end
    assert_send_type "(ToStr) { (String) -> ToS } -> self",
                     "a", :sub!, ToStr.new("a") do |str| ToS.new(str) end
    assert_send_type "(Regexp, String) -> nil",
                     "a", :sub!, /b/, "a"
    assert_send_type "(String, String) -> nil",
                     "a", :sub!, "b", "a"
    assert_send_type "(ToStr, String) -> nil",
                     "a", :sub!, ToStr.new("b"), "a"
    assert_send_type "(Regexp, ToStr) -> nil",
                     "a", :sub!, /b/, ToStr.new("a")
    assert_send_type "(String, ToStr) -> nil",
                     "a", :sub!, "b", ToStr.new("a")
    assert_send_type "(ToStr, ToStr) -> nil",
                     "a", :sub!, ToStr.new("b"), ToStr.new("a")
    assert_send_type "(Regexp, Hash[String, String]) -> nil",
                     "a", :sub!, /b/, { "a" => "a" }
    assert_send_type "(String, Hash[String, String]) -> nil",
                     "a", :sub!, "b", { "a" => "a" }
    assert_send_type "(ToStr, Hash[String, String]) -> nil",
                     "a", :sub!, ToStr.new("b"), { "a" => "a" }
    assert_send_type "(Regexp) { (String) -> ToS } -> nil",
                     "a", :sub!, /b/ do |str| ToS.new(str) end
    assert_send_type "(String) { (String) -> ToS } -> nil",
                     "a", :sub!, "b" do |str| ToS.new(str) end
    assert_send_type "(ToStr) { (String) -> ToS } -> nil",
                     "a", :sub!, ToStr.new("b") do |str| ToS.new(str) end
  end

  def test_succ
    assert_send_type "() -> String",
                     "", :succ
  end

  def test_succ!
    assert_send_type "() -> self",
                     "", :succ!
  end

  def test_sum
    assert_send_type "() -> Integer",
                     " ", :sum
    assert_send_type "(Integer) -> Integer",
                     " ", :sum, 16
    assert_send_type "(ToInt) -> Integer",
                     " ", :sum, ToInt.new(16)
  end

  def test_swapcase
    assert_send_type "() -> String",
                     "a", :swapcase
    assert_send_type "(Symbol) -> String",
                     "a", :swapcase, :ascii
    assert_send_type "(Symbol) -> String",
                     "a", :swapcase, :lithuanian
    assert_send_type "(Symbol) -> String",
                     "a", :swapcase, :turkic
    assert_send_type "(Symbol, Symbol) -> String",
                     "a", :swapcase, :lithuanian, :turkic
    assert_send_type "(Symbol, Symbol) -> String",
                     "a", :swapcase, :turkic, :lithuanian
  end

  def test_swapcase!
    assert_send_type "() -> self",
                     "a", :swapcase!
    assert_send_type "(Symbol) -> self",
                     "a", :swapcase!, :ascii
    assert_send_type "(Symbol) -> self",
                     "a", :swapcase!, :lithuanian
    assert_send_type "(Symbol) -> self",
                     "a", :swapcase!, :turkic
    assert_send_type "(Symbol, Symbol) -> self",
                     "a", :swapcase!, :lithuanian, :turkic
    assert_send_type "(Symbol, Symbol) -> self",
                     "a", :swapcase!, :turkic, :lithuanian
    assert_send_type "() -> nil",
                     "", :swapcase!
    assert_send_type "(Symbol) -> nil",
                     "", :swapcase!, :ascii
    assert_send_type "(Symbol) -> nil",
                     "", :swapcase!, :lithuanian
    assert_send_type "(Symbol) -> nil",
                     "", :swapcase!, :turkic
    assert_send_type "(Symbol, Symbol) -> nil",
                     "", :swapcase!, :lithuanian, :turkic
    assert_send_type "(Symbol, Symbol) -> nil",
                     "", :swapcase!, :turkic, :lithuanian
  end

  def test_to_c
    assert_send_type "() -> Complex",
                     "ruby", :to_c
  end

  def test_to_f
    assert_send_type "() -> Float",
                     "ruby", :to_f
  end

  def test_to_i
    assert_send_type "() -> Integer",
                     "ruby", :to_i
    assert_send_type "(Integer) -> Integer",
                     "ruby", :to_i, 10
    assert_send_type "(ToInt) -> Integer",
                     "ruby", :to_i, ToInt.new(10)
  end

  def test_to_r
    assert_send_type "() -> Rational",
                     "ruby", :to_r
  end

  def test_to_s
    assert_send_type "() -> String",
                     "ruby", :to_s
  end

  def test_to_str
    assert_send_type "() -> String",
                     "ruby", :to_str
  end

  def test_to_sym
    assert_send_type "() -> Symbol",
                     "ruby", :to_sym
  end

  def test_tr
    assert_send_type "(String, String) -> String",
                     "ruby", :tr, "r", "j"
    assert_send_type "(ToStr, ToStr) -> String",
                     "ruby", :tr, ToStr.new("r"), ToStr.new("j")
  end

  def test_tr!
    assert_send_type "(String, String) -> self",
                     "ruby", :tr!, "r", "j"
    assert_send_type "(ToStr, ToStr) -> self",
                     "ruby", :tr!, ToStr.new("r"), ToStr.new("j")
    assert_send_type "(String, String) -> nil",
                     "", :tr!, "r", "j"
    assert_send_type "(ToStr, ToStr) -> nil",
                     "", :tr!, ToStr.new("r"), ToStr.new("j")
  end

  def test_tr_s
    assert_send_type "(String, String) -> String",
                     "ruby", :tr_s, "r", "j"
    assert_send_type "(ToStr, ToStr) -> String",
                     "ruby", :tr_s, ToStr.new("r"), ToStr.new("j")
  end

  def test_tr_s!
    assert_send_type "(String, String) -> self",
                     "ruby", :tr_s!, "r", "j"
    assert_send_type "(ToStr, ToStr) -> self",
                     "ruby", :tr_s!, ToStr.new("r"), ToStr.new("j")
    assert_send_type "(String, String) -> nil",
                     "", :tr_s!, "r", "j"
    assert_send_type "(ToStr, ToStr) -> nil",
                     "", :tr_s!, ToStr.new("r"), ToStr.new("j")
  end

  def test_undump
    assert_send_type "() -> String",
                     "\"hello \\n ''\"", :undump
  end

  def test_unicode_normalize
    assert_send_type "() -> String",
                     "a\u0300", :unicode_normalize
    assert_send_type "(:nfc) -> String",
                     "a\u0300", :unicode_normalize, :nfc
    assert_send_type "(:nfd) -> String",
                     "a\u0300", :unicode_normalize, :nfd
    assert_send_type "(:nfkc) -> String",
                     "a\u0300", :unicode_normalize, :nfkc
    assert_send_type "(:nfkd) -> String",
                     "a\u0300", :unicode_normalize, :nfkd
  end

  def test_unicode_normalize!
    assert_send_type "() -> String",
                     "a\u0300", :unicode_normalize!
    assert_send_type "(:nfc) -> String",
                     "a\u0300", :unicode_normalize!, :nfc
    assert_send_type "(:nfd) -> String",
                     "a\u0300", :unicode_normalize!, :nfd
    assert_send_type "(:nfkc) -> String",
                     "a\u0300", :unicode_normalize!, :nfkc
    assert_send_type "(:nfkd) -> String",
                     "a\u0300", :unicode_normalize!, :nfkd
  end

  def test_unicode_normalized?
    assert_send_type "() -> false",
                     "a\u0300", :unicode_normalized?
    assert_send_type "(:nfc) -> false",
                     "a\u0300", :unicode_normalized?, :nfc
    assert_send_type "(:nfd) -> true",
                     "a\u0300", :unicode_normalized?, :nfd
    assert_send_type "(:nfkc) -> false",
                     "a\u0300", :unicode_normalized?, :nfkc
    assert_send_type "(:nfkd) -> true",
                     "a\u0300", :unicode_normalized?, :nfkd
  end

  def test_unpack
    assert_send_type "(String) -> [ ]",
                     "a", :unpack, ""
    assert_send_type "(String) -> [ nil ]",
                     "", :unpack, "f"
    assert_send_type "(String) -> Array[Integer]",
                     "a", :unpack, "c"
    assert_send_type "(String) -> Array[String]",
                     "a", :unpack, "A"
    assert_send_type "(String) -> Array[Float]",
                     "\x00\x00\x00\x00", :unpack, "f"
  end

  def test_unpack1
    assert_send_type "(String) -> nil",
                     "a", :unpack1, ""
    assert_send_type "(String) -> nil",
                     "", :unpack1, "f"
    assert_send_type "(String) -> Integer",
                     "a", :unpack1, "c"
    assert_send_type "(String) -> String",
                     "a", :unpack1, "A"
    assert_send_type "(String) -> Float",
                     "\x00\x00\x00\x00", :unpack1, "f"
  end

  def test_upcase
    assert_send_type "() -> String",
                     "a", :upcase
    assert_send_type "(:ascii) -> String",
                     "a", :upcase, :ascii
    assert_send_type "(:lithuanian) -> String",
                     "a", :upcase, :lithuanian
    assert_send_type "(:turkic) -> String",
                     "a", :upcase, :turkic
    assert_send_type "(:lithuanian, :turkic) -> String",
                     "a", :upcase, :lithuanian, :turkic
    assert_send_type "(:turkic, :lithuanian) -> String",
                     "a", :upcase, :turkic, :lithuanian
  end

  def test_upcase!
    assert_send_type "() -> String",
                     "a", :upcase!
    assert_send_type "(:ascii) -> String",
                     "a", :upcase!, :ascii
    assert_send_type "(:lithuanian) -> String",
                     "a", :upcase!, :lithuanian
    assert_send_type "(:turkic) -> String",
                     "a", :upcase!, :turkic
    assert_send_type "(:lithuanian, :turkic) -> String",
                     "a", :upcase!, :lithuanian, :turkic
    assert_send_type "(:turkic, :lithuanian) -> String",
                     "a", :upcase!, :turkic, :lithuanian
    assert_send_type "() -> nil",
                     "", :upcase!
    assert_send_type "(:ascii) -> nil",
                     "", :upcase!, :ascii
    assert_send_type "(:lithuanian) -> nil",
                     "", :upcase!, :lithuanian
    assert_send_type "(:turkic) -> nil",
                     "", :upcase!, :turkic
    assert_send_type "(:lithuanian, :turkic) -> nil",
                     "", :upcase!, :lithuanian, :turkic
    assert_send_type "(:turkic, :lithuanian) -> nil",
                     "", :upcase!, :turkic, :lithuanian
  end

  def test_upto
    assert_send_type "(String) -> Enumerator[String, self]",
                     "1", :upto, "2"
    assert_send_type "(String, true) -> Enumerator[String, self]",
                     "1", :upto, "2", true
    assert_send_type "(String, false) -> Enumerator[String, self]",
                     "1", :upto, "2", false
    assert_send_type "(String) { (String) -> void } -> self",
                     "1", :upto, "2" do |s| s end
    assert_send_type "(String, true) { (String) -> void } -> self",
                     "1", :upto, "2", true do |s| s end
    assert_send_type "(String, false) { (String) -> void } -> self",
                     "1", :upto, "2", false do |s| s end
    assert_send_type "(ToStr) -> Enumerator[String, self]",
                     "1", :upto, ToStr.new("2")
    assert_send_type "(ToStr) { (String) -> void } -> self",
                     "1", :upto, ToStr.new("2") do |s| s end
  end

  def test_valid_encoding?
    assert_send_type "() -> true",
                     "", :valid_encoding?
    assert_send_type "() -> false",
                     "あ".force_encoding(Encoding::Shift_JIS), :valid_encoding?
  end
end
