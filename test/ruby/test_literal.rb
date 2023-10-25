# -*- coding: us-ascii -*-
# frozen_string_literal: false
require 'test/unit'

class TestRubyLiteral < Test::Unit::TestCase

  def test_special_const
    assert_equal 'true', true.inspect
    assert_instance_of TrueClass, true
    assert_equal 'false', false.inspect
    assert_instance_of FalseClass, false
    assert_equal 'nil', nil.inspect
    assert_instance_of NilClass, nil
    assert_equal ':sym', :sym.inspect
    assert_instance_of Symbol, :sym
    assert_equal '1234', 1234.inspect
    assert_instance_of Integer, 1234
    assert_equal '1234', 1_2_3_4.inspect
    assert_instance_of Integer, 1_2_3_4
    assert_equal '18', 0x12.inspect
    assert_instance_of Integer, 0x12
    assert_raise(SyntaxError) { eval("0x") }
    assert_equal '15', 0o17.inspect
    assert_instance_of Integer, 0o17
    assert_raise(SyntaxError) { eval("0o") }
    assert_equal '5', 0b101.inspect
    assert_instance_of Integer, 0b101
    assert_raise(SyntaxError) { eval("0b") }
    assert_equal '123456789012345678901234567890', 123456789012345678901234567890.to_s
    assert_instance_of Integer, 123456789012345678901234567890
    assert_instance_of Float, 1.3
    assert_equal '2', eval("0x00+2").inspect
  end

  def test_self
    assert_equal self, self
    assert_instance_of TestRubyLiteral, self
    assert_respond_to self, :test_self
  end

  def test_string
    assert_instance_of String, ?a
    assert_equal "a", ?a
    assert_instance_of String, ?A
    assert_equal "A", ?A
    assert_instance_of String, ?\n
    assert_equal "\n", ?\n
    assert_equal " ", ?\s
    assert_equal " ", ?\   # space
    assert_equal '', ''
    assert_equal 'string', 'string'
    assert_equal 'string string', 'string string'
    assert_equal ' ', ' '
    assert_equal ' ', " "
    assert_equal "\0", "\0"
    assert_equal "\1", "\1"
    assert_equal "3", "\x33"
    assert_equal "\n", "\n"
    bug2500 = '[ruby-core:27228]'
    bug5262 = '[ruby-core:39222]'
    %w[c C- M-].each do |pre|
      ["u", %w[u{ }]].each do |open, close|
        ["?", ['"', '"']].each do |qopen, qclose|
          str = "#{qopen}\\#{pre}\\#{open}5555#{close}#{qclose}"
          assert_raise(SyntaxError, "#{bug2500} eval(#{str})") {eval(str)}

          str = "#{qopen}\\#{pre}\\#{open}\u201c#{close}#{qclose}"
          assert_raise(SyntaxError, "#{bug5262} eval(#{str})") {eval(str)}

          str = "#{qopen}\\#{pre}\\#{open}\u201c#{close}#{qclose}".encode("euc-jp")
          assert_raise(SyntaxError, "#{bug5262} eval(#{str})") {eval(str)}

          str = "#{qopen}\\#{pre}\\#{open}\u201c#{close}#{qclose}".encode("iso-8859-13")
          assert_raise(SyntaxError, "#{bug5262} eval(#{str})") {eval(str)}

          str = "#{qopen}\\#{pre}\\#{open}\xe2\x7f#{close}#{qclose}".force_encoding("utf-8")
          assert_raise(SyntaxError, "#{bug5262} eval(#{str})") {eval(str)}
        end
      end
    end
    bug6069 = '[ruby-dev:45278]'
    assert_equal "\x13", "\c\x33"
    assert_equal "\x13", "\C-\x33"
    assert_equal "\xB3", "\M-\x33"
    assert_equal "\u201c", eval(%["\\\u{201c}"]), bug5262
    assert_equal "\u201c".encode("euc-jp"), eval(%["\\\u{201c}"].encode("euc-jp")), bug5262
    assert_equal "\u201c".encode("iso-8859-13"), eval(%["\\\u{201c}"].encode("iso-8859-13")), bug5262
    assert_equal "\\\u201c", eval(%['\\\u{201c}']), bug6069
    assert_equal "\\\u201c".encode("euc-jp"), eval(%['\\\u{201c}'].encode("euc-jp")), bug6069
    assert_equal "\\\u201c".encode("iso-8859-13"), eval(%['\\\u{201c}'].encode("iso-8859-13")), bug6069
    assert_equal "\u201c", eval(%[?\\\u{201c}]), bug6069
    assert_equal "\u201c".encode("euc-jp"), eval(%[?\\\u{201c}].encode("euc-jp")), bug6069
    assert_equal "\u201c".encode("iso-8859-13"), eval(%[?\\\u{201c}].encode("iso-8859-13")), bug6069

    assert_equal "ab", eval("?a 'b'")
    assert_equal "a\nb", eval("<<A 'b'\na\nA")
  end

  def test_dstring
    assert_equal '2', "#{1+1}"
    assert_equal '16', "#{2 ** 4}"
    s = "string"
    assert_equal s, "#{s}"
    a = 'Foo'
    b = "#{a}" << 'Bar'
    assert_equal('Foo', a, 'r3842')
    assert_equal('FooBar', b, 'r3842')
  end

  def test_dstring_encoding
    bug11519 = '[ruby-core:70703] [Bug #11519]'
    ['"foo#{}"', '"#{}foo"', '"#{}"'].each do |code|
      a = eval("#-*- coding: utf-8 -*-\n#{code}")
      assert_equal(Encoding::UTF_8, a.encoding,
                   proc{"#{bug11519}: #{code}.encoding"})
    end
  end

  def test_dsymbol
    assert_equal :a3c, :"a#{1+2}c"
  end

  def test_dsymbol_redefined_intern
    assert_separately([], "#{<<-"begin;"}\n#{<<-'end;'}")
    begin;
      class String
        alias _intern intern
        def intern
          "<#{upcase}>"
        end
      end
      mesg = "literal symbol should not be affected by method redefinition"
      str = "foo"
      assert_equal(:foo, :"#{str}", mesg)
    end;
  end

  def test_xstring
    assert_equal "foo\n", `echo foo`
    s = 'foo'
    assert_equal "foo\n", `echo #{s}`
  end

  def test_frozen_string
    all_assertions do |a|
      a.for("false with indicator") do
        str = eval("# -*- frozen-string-literal: false -*-\n""'foo'")
        assert_not_predicate(str, :frozen?)
      end
      a.for("true with indicator") do
        str = eval("# -*- frozen-string-literal: true -*-\n""'foo'")
        assert_predicate(str, :frozen?)
      end
      a.for("false without indicator") do
        str = eval("# frozen-string-literal: false\n""'foo'")
        assert_not_predicate(str, :frozen?)
      end
      a.for("true without indicator") do
        str = eval("# frozen-string-literal: true\n""'foo'")
        assert_predicate(str, :frozen?)
      end
      a.for("false with preceding garbage") do
        str = eval("# x frozen-string-literal: false\n""'foo'")
        assert_not_predicate(str, :frozen?)
      end
      a.for("true with preceding garbage") do
        str = eval("# x frozen-string-literal: true\n""'foo'")
        assert_not_predicate(str, :frozen?)
      end
      a.for("false with succeeding garbage") do
        str = eval("# frozen-string-literal: false x\n""'foo'")
        assert_not_predicate(str, :frozen?)
      end
      a.for("true with succeeding garbage") do
        str = eval("# frozen-string-literal: true x\n""'foo'")
        assert_not_predicate(str, :frozen?)
      end
    end
  end

  def test_frozen_string_in_array_literal
    list = eval("# frozen-string-literal: true\n""['foo', 'bar']")
    assert_equal 2, list.length
    list.each { |str| assert_predicate str, :frozen? }
  end

  if defined?(RubyVM::InstructionSequence.compile_option) and
    RubyVM::InstructionSequence.compile_option.key?(:debug_frozen_string_literal)
    def test_debug_frozen_string
      src = '_="foo-1"'; f = "test.rb"; n = 1
      opt = {frozen_string_literal: true, debug_frozen_string_literal: true}
      str = RubyVM::InstructionSequence.compile(src, f, f, n, **opt).eval
      assert_equal("foo-1", str)
      assert_predicate(str, :frozen?)
      assert_raise_with_message(FrozenError, /created at #{Regexp.quote(f)}:#{n}/) {
        str << "x"
      } unless ENV['RUBY_ISEQ_DUMP_DEBUG']
    end

    def test_debug_frozen_string_in_array_literal
      src = '["foo"]'; f = "test.rb"; n = 1
      opt = {frozen_string_literal: true, debug_frozen_string_literal: true}
      ary = RubyVM::InstructionSequence.compile(src, f, f, n, **opt).eval
      assert_equal("foo", ary.first)
      assert_predicate(ary.first, :frozen?)
      assert_raise_with_message(FrozenError, /created at #{Regexp.quote(f)}:#{n}/) {
        ary.first << "x"
      } unless ENV['RUBY_ISEQ_DUMP_DEBUG']
    end
  end

  def test_regexp
    assert_instance_of Regexp, //
    assert_match(//, 'a')
    assert_match(//, '')
    assert_instance_of Regexp, /a/
    assert_match(/a/, 'a')
    assert_no_match(/test/, 'tes')
    re = /test/
    assert_match re, 'test'
    str = 'test'
    assert_match re, str
    assert_match(/test/, str)
    assert_equal 0, (/test/ =~ 'test')
    assert_equal 0, (re =~ 'test')
    assert_equal 0, (/test/ =~ str)
    assert_equal 0, (re =~ str)
    assert_equal 0, ('test' =~ /test/)
    assert_equal 0, ('test' =~ re)
    assert_equal 0, (str =~ /test/)
    assert_equal 0, (str =~ re)
  end

  def test_dregexp
    assert_instance_of Regexp, /re#{'ge'}xp/
    assert_equal(/regexp/, /re#{'ge'}xp/)
    bug3903 = '[ruby-core:32682]'
    assert_raise(SyntaxError, bug3903) {eval('/[#{"\x80"}]/')}
  end

  def test_array
    assert_instance_of Array, []
    assert_equal [], []
    assert_equal 0, [].size
    assert_instance_of Array, [0]
    assert_equal [3], [3]
    assert_equal 1, [3].size
    a = [3]
    assert_equal 3, a[0]
    assert_instance_of Array, [1,2]
    assert_equal [1,2], [1,2]
    assert_instance_of Array, [1,2,3,4,5]
    assert_equal [1,2,3,4,5], [1,2,3,4,5]
    assert_equal 5, [1,2,3,4,5].size
    a = [1,2]
    assert_equal 1, a[0]
    assert_equal 2, a[1]
    a = [1 + 2, 3 + 4, 5 + 6]
    assert_instance_of Array, a
    assert_equal [3, 7, 11], a
    assert_equal 7, a[1]
    assert_equal 1, ([0][0] += 1)
    assert_equal 1, ([2][0] -= 1)
    a = [obj = Object.new]
    assert_instance_of Array, a
    assert_equal 1, a.size
    assert_equal obj, a[0]
    a = [1,2,3]
    a[1] = 5
    assert_equal 5, a[1]
  end

  def test_hash
    assert_instance_of Hash, {}
    assert_equal({}, {})
    assert_instance_of Hash, {1 => 2}
    assert_equal({1 => 2}, {1 => 2})
    h = {1 => 2}
    assert_equal 2, h[1]
    h = {"string" => "literal", "goto" => "hell"}
    assert_equal h, h
    assert_equal 2, h.size
    assert_equal h, h
    assert_equal "literal", h["string"]
  end

  def test_hash_literal_frozen
    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      def frozen_hash_literal_arg
        {0=>1,1=>4,2=>17}
      end

      ObjectSpace.each_object(Hash) do |a|
        if a.class == Hash and !a.default_proc and a.size == 3 &&
           a[0] == 1 && a[1] == 4 && a[2] == 17
          # should not be found.
          raise
        end
      end
      assert_not_include frozen_hash_literal_arg, 3
    end;
  end

  def test_big_array_and_hash_literal
    assert_normal_exit %q{GC.disable=true; x = nil; raise if eval("[#{(1..1_000_000).map{'x'}.join(", ")}]").size != 1_000_000}, "", timeout: 300, child_env: %[--disable-gems]
    assert_normal_exit %q{GC.disable=true; x = nil; raise if eval("[#{(1..1_000_000).to_a.join(", ")}]").size != 1_000_000}, "", timeout: 300, child_env: %[--disable-gems]
    assert_normal_exit %q{GC.disable=true; x = nil; raise if eval("{#{(1..1_000_000).map{|n| "#{n} => x"}.join(', ')}}").size != 1_000_000}, "", timeout: 300, child_env: %[--disable-gems]
    assert_normal_exit %q{GC.disable=true; x = nil; raise if eval("{#{(1..1_000_000).map{|n| "#{n} => #{n}"}.join(', ')}}").size != 1_000_000}, "", timeout: 300, child_env: %[--disable-gems]
  end

  def test_big_hash_literal
    bug7466 = '[ruby-dev:46658]'
    h = {
      0xFE042 => 0xE5CD,
      0xFE043 => 0xE5CD,
      0xFE045 => 0xEA94,
      0xFE046 => 0xE4E3,
      0xFE047 => 0xE4E2,
      0xFE048 => 0xEA96,
      0xFE049 => 0x3013,
      0xFE04A => 0xEB36,
      0xFE04B => 0xEB37,
      0xFE04C => 0xEB38,
      0xFE04D => 0xEB49,
      0xFE04E => 0xEB82,
      0xFE04F => 0xE4D2,
      0xFE050 => 0xEB35,
      0xFE051 => 0xEAB9,
      0xFE052 => 0xEABA,
      0xFE053 => 0xE4D4,
      0xFE054 => 0xE4CD,
      0xFE055 => 0xEABB,
      0xFE056 => 0xEABC,
      0xFE057 => 0xEB32,
      0xFE058 => 0xEB33,
      0xFE059 => 0xEB34,
      0xFE05A => 0xEB39,
      0xFE05B => 0xEB5A,
      0xFE190 => 0xE5A4,
      0xFE191 => 0xE5A5,
      0xFE192 => 0xEAD0,
      0xFE193 => 0xEAD1,
      0xFE194 => 0xEB47,
      0xFE195 => 0xE509,
      0xFE196 => 0xEAA0,
      0xFE197 => 0xE50B,
      0xFE198 => 0xEAA1,
      0xFE199 => 0xEAA2,
      0xFE19A => 0x3013,
      0xFE19B => 0xE4FC,
      0xFE19C => 0xE4FA,
      0xFE19D => 0xE4FC,
      0xFE19E => 0xE4FA,
      0xFE19F => 0xE501,
      0xFE1A0 => 0x3013,
      0xFE1A1 => 0xE5DD,
      0xFE1A2 => 0xEADB,
      0xFE1A3 => 0xEAE9,
      0xFE1A4 => 0xEB13,
      0xFE1A5 => 0xEB14,
      0xFE1A6 => 0xEB15,
      0xFE1A7 => 0xEB16,
      0xFE1A8 => 0xEB17,
      0xFE1A9 => 0xEB18,
      0xFE1AA => 0xEB19,
      0xFE1AB => 0xEB1A,
      0xFE1AC => 0xEB44,
      0xFE1AD => 0xEB45,
      0xFE1AE => 0xE4CB,
      0xFE1AF => 0xE5BF,
      0xFE1B0 => 0xE50E,
      0xFE1B1 => 0xE4EC,
      0xFE1B2 => 0xE4EF,
      0xFE1B3 => 0xE4F8,
      0xFE1B4 => 0x3013,
      0xFE1B5 => 0x3013,
      0xFE1B6 => 0xEB1C,
      0xFE1B9 => 0xEB7E,
      0xFE1D3 => 0xEB22,
      0xFE7DC => 0xE4D8,
      0xFE1D4 => 0xEB23,
      0xFE1D5 => 0xEB24,
      0xFE1D6 => 0xEB25,
      0xFE1CC => 0xEB1F,
      0xFE1CD => 0xEB20,
      0xFE1CE => 0xE4D9,
      0xFE1CF => 0xE48F,
      0xFE1C5 => 0xE5C7,
      0xFE1C6 => 0xEAEC,
      0xFE1CB => 0xEB1E,
      0xFE1DA => 0xE4DD,
      0xFE1E1 => 0xEB57,
      0xFE1E2 => 0xEB58,
      0xFE1E3 => 0xE492,
      0xFE1C9 => 0xEB1D,
      0xFE1D9 => 0xE4D3,
      0xFE1DC => 0xE5D4,
      0xFE1BA => 0xE4E0,
      0xFE1BB => 0xEB76,
      0xFE1C8 => 0xE4E0,
      0xFE1DD => 0xE5DB,
      0xFE1BC => 0xE4DC,
      0xFE1D8 => 0xE4DF,
      0xFE1BD => 0xE49A,
      0xFE1C7 => 0xEB1B,
      0xFE1C2 => 0xE5C2,
      0xFE1C0 => 0xE5C0,
      0xFE1B8 => 0xE4DB,
      0xFE1C3 => 0xE470,
      0xFE1BE => 0xE4D8,
      0xFE1C4 => 0xE4D9,
      0xFE1B7 => 0xE4E1,
      0xFE1BF => 0xE4DE,
      0xFE1C1 => 0xE5C1,
      0xFE1CA => 0x3013,
      0xFE1D0 => 0xE4E1,
      0xFE1D1 => 0xEB21,
      0xFE1D2 => 0xE4D7,
      0xFE1D7 => 0xE4DA,
      0xFE1DB => 0xE4EE,
      0xFE1DE => 0xEB3F,
      0xFE1DF => 0xEB46,
      0xFE1E0 => 0xEB48,
      0xFE336 => 0xE4FB,
      0xFE320 => 0xE472,
      0xFE321 => 0xEB67,
      0xFE322 => 0xEACA,
      0xFE323 => 0xEAC0,
      0xFE324 => 0xE5AE,
      0xFE325 => 0xEACB,
      0xFE326 => 0xEAC9,
      0xFE327 => 0xE5C4,
      0xFE328 => 0xEAC1,
      0xFE329 => 0xE4E7,
      0xFE32A => 0xE4E7,
      0xFE32B => 0xEACD,
      0xFE32C => 0xEACF,
      0xFE32D => 0xEACE,
      0xFE32E => 0xEAC7,
      0xFE32F => 0xEAC8,
      0xFE330 => 0xE471,
      0xFE331 => "[Bug #7466]",
    }
    k = h.keys
    assert_equal([129, 0xFE331], [k.size, k.last], bug7466)

    code = [
      "h = {",
      (1..128).map {|i| "#{i} => 0,"},
      (129..140).map {|i| "#{i} => [],"},
      "}",
    ].join
    assert_separately([], <<-"end;")
      GC.stress = true
      #{code}
      GC.stress = false
      assert_equal(140, h.size)
    end;
  end

  def test_hash_duplicated_key
    h = EnvUtil.suppress_warning do
      eval "#{<<-"begin;"}\n#{<<-'end;'}"
      begin;
        # This is a syntax that renders warning at very early stage.
        # eval used to delay warning, to be suppressible by EnvUtil.
        {"a" => 100, "b" => 200, "a" => 300, "a" => 400}
      end;
    end
    assert_equal(2, h.size)
    assert_equal(400, h['a'])
    assert_equal(200, h['b'])
    assert_nil(h['c'])
    assert_equal(nil, h.key('300'))

    a = []
    h = EnvUtil.suppress_warning do
      eval <<~end
        # This is a syntax that renders warning at very early stage.
        # eval used to delay warning, to be suppressible by EnvUtil.
        {"a" => a.push(100).last, "b" => a.push(200).last, "a" => a.push(300).last, "a" => a.push(400).last}
      end
    end
    assert_equal({'a' => 400, 'b' => 200}, h)
    assert_equal([100, 200, 300, 400], a)

    assert_all_assertions_foreach(
      "duplicated literal key",
      ':foo',
      '"a"',
      '1000',
      '1.0',
      '1_000_000_000_000_000_000_000',
      '1.0r',
      '1.0i',
      '1.72723e-77',
      '//',
    ) do |key|
      assert_warning(/key #{Regexp.quote(eval(key).inspect)} is duplicated/) do
        eval("{#{key} => :bar, #{key} => :foo}")
      end
    end
  end

  def test_hash_frozen_key_id
    key = "a".freeze
    h = {key => 100}
    assert_equal(100, h['a'])
    assert_same(key, *h.keys)
  end

  def test_hash_key_tampering
    key = "a"
    h = {key => 100}
    key.upcase!
    assert_equal(100, h['a'])
  end

  FOO = "foo"

  def test_hash_value_omission
    x = 1
    y = 2
    assert_equal({x: 1, y: 2}, {x:, y:})
    assert_equal({x: 1, y: 2, z: 3}, {x:, y:, z: 3})
    assert_equal({one: 1, two: 2}, {one:, two:})
    b = binding
    b.local_variable_set(:if, "if")
    b.local_variable_set(:self, "self")
    assert_equal({FOO: "foo", if: "if", self: "self"},
                 eval('{FOO:, if:, self:}', b))
    assert_syntax_error('{"#{x}":}', /'\}'/)
  end

  private def one
    1
  end

  private def two
    2
  end

  def test_range
    assert_instance_of Range, (1..2)
    assert_equal(1..2, 1..2)
    r = 1..2
    assert_equal 1, r.begin
    assert_equal 2, r.end
    assert_equal false, r.exclude_end?
    assert_instance_of Range, (1...3)
    assert_equal(1...3, 1...3)
    r = 1...3
    assert_equal 1, r.begin
    assert_equal 3, r.end
    assert_equal true, r.exclude_end?
    r = 1+2 .. 3+4
    assert_instance_of Range, r
    assert_equal 3, r.begin
    assert_equal 7, r.end
    assert_equal false, r.exclude_end?
    r = 1+2 ... 3+4
    assert_instance_of Range, r
    assert_equal 3, r.begin
    assert_equal 7, r.end
    assert_equal true, r.exclude_end?
    assert_instance_of Range, 'a'..'c'
    r = 'a'..'c'
    assert_equal 'a', r.begin
    assert_equal 'c', r.end
  end

  def test__FILE__
    assert_instance_of String, __FILE__
    assert_equal __FILE__, __FILE__
    assert_equal 'test_literal.rb', File.basename(__FILE__)
  end

  def test__LINE__
    assert_instance_of Integer, __LINE__
    assert_equal __LINE__, __LINE__
  end

  def test_integer
    head = ['', '0x', '0o', '0b', '0d', '-', '+']
    chars = ['0', '1', '_', '9', 'f']
    head.each {|h|
      4.times {|len|
        a = [h]
        len.times { a = a.product(chars).map {|x| x.join('') } }
        a.each {|s|
          next if s.empty?
          begin
            r1 = Integer(s)
          rescue ArgumentError
            r1 = :err
          end
          begin
            r2 = eval(s)
          rescue NameError, SyntaxError
            r2 = :err
          end
          assert_equal(r1, r2, "Integer(#{s.inspect}) != eval(#{s.inspect})")
        }
      }
    }
    bug2407 = '[ruby-dev:39798]'
    head.grep_v(/^0/) do |s|
      head.grep(/^0/) do |h|
        h = "#{s}#{h}_"
        assert_syntax_error(h, /numeric literal without digits\Z/, "#{bug2407}: #{h.inspect}")
      end
    end
  end

  def test_float
    head = ['', '-', '+']
    chars = ['0', '1', '_', '9', 'f', '.']
    head.each {|h|
      6.times {|len|
        a = [h]
        len.times { a = a.product(chars).map {|x| x.join('') } }
        a.each {|s|
          next if s.empty?
          next if /\.\z/ =~ s
          next if /\A[-+]?\./ =~ s
          next if /\A[-+]?0/ =~ s
          begin
            r1 = Float(s)
          rescue ArgumentError
            r1 = :err
          end
          begin
            r2 = eval(s)
          rescue NameError, SyntaxError
            r2 = :err
          end
          r2 = :err if Range === r2
          assert_equal(r1, r2, "Float(#{s.inspect}) != eval(#{s.inspect})")
        }
      }
    }
    assert_equal(100.0, 0.0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100e100)
  end

  def test_symbol_list
    assert_equal([:foo, :bar], %i[foo bar])
    assert_equal([:"\"foo"], %i["foo])

    x = 10
    assert_equal([:foo, :b10], %I[foo b#{x}])
    assert_equal([:"\"foo10"], %I["foo#{x}])

    assert_ruby_status(["--disable-gems", "--dump=parsetree"], "%I[foo bar]")
  end
end
