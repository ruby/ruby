require_relative '../spec_helper'
require_relative 'fixtures/hash_strings_binary'
require_relative 'fixtures/hash_strings_utf8'
require_relative 'fixtures/hash_strings_usascii'

describe "Hash literal" do
  it "{} should return an empty Hash" do
    {}.size.should == 0
    {}.should == {}
  end

  it "{} should return a new Hash populated with the given elements" do
    h = {a: 'a', 'b' => 3, 44 => 2.3}
    h.size.should == 3
    h.should == {a: "a", "b" => 3, 44 => 2.3}
  end

  it "treats empty expressions as nils" do
    h = {() => ()}
    h.keys.should == [nil]
    h.values.should == [nil]
    h[nil].should == nil

    h = {() => :value}
    h.keys.should == [nil]
    h.values.should == [:value]
    h[nil].should == :value

    h = {key: ()}
    h.keys.should == [:key]
    h.values.should == [nil]
    h[:key].should == nil
  end

  it "freezes string keys on initialization" do
    key = +"foo"
    h = {key => "bar"}
    key.reverse!
    h["foo"].should == "bar"
    h.keys.first.should == "foo"
    h.keys.first.should.frozen?
    key.should == "oof"
  end

  it "checks duplicated keys on initialization" do
    -> {
      @h = eval "{foo: :bar, foo: :foo}"
    }.should complain(/key :foo is duplicated|duplicated key/)
    @h.keys.size.should == 1
    @h.should == {foo: :foo}
    -> {
      @h = eval "{%q{a} => :bar, %q{a} => :foo}"
    }.should complain(/key "a" is duplicated|duplicated key/)
    @h.keys.size.should == 1
    @h.should == {%q{a} => :foo}
    -> {
      @h = eval "{1000 => :bar, 1000 => :foo}"
    }.should complain(/key 1000 is duplicated|duplicated key/)
    @h.keys.size.should == 1
    @h.should == {1000 => :foo}
  end

  ruby_version_is "3.1" do
    it "checks duplicated float keys on initialization" do
      -> {
        @h = eval "{1.0 => :bar, 1.0 => :foo}"
      }.should complain(/key 1.0 is duplicated|duplicated key/)
      @h.keys.size.should == 1
      @h.should == {1.0 => :foo}
    end
  end

  it "accepts a hanging comma" do
    h = {a: 1, b: 2,}
    h.size.should == 2
    h.should == {a: 1, b: 2}
  end

  it "recognizes '=' at the end of the key" do
    eval("{:a==>1}").should == {:"a=" => 1}
    eval("{:a= =>1}").should == {:"a=" => 1}
    eval("{:a= => 1}").should == {:"a=" => 1}
  end

  it "with '==>' in the middle raises SyntaxError" do
    -> { eval("{:a ==> 1}") }.should raise_error(SyntaxError)
  end

  it "recognizes '!' at the end of the key" do
    eval("{:a! =>1}").should == {:"a!" => 1}
    eval("{:a! => 1}").should == {:"a!" => 1}

    eval("{a!:1}").should == {:"a!" => 1}
    eval("{a!: 1}").should == {:"a!" => 1}
  end

  it "raises a SyntaxError if there is no space between `!` and `=>`" do
    -> { eval("{:a!=> 1}") }.should raise_error(SyntaxError)
  end

  it "recognizes '?' at the end of the key" do
    eval("{:a? =>1}").should == {:"a?" => 1}
    eval("{:a? => 1}").should == {:"a?" => 1}

    eval("{a?:1}").should == {:"a?" => 1}
    eval("{a?: 1}").should == {:"a?" => 1}
  end

  it "raises a SyntaxError if there is no space between `?` and `=>`" do
    -> { eval("{:a?=> 1}") }.should raise_error(SyntaxError)
  end

  it "constructs a new Hash with the given elements" do
    {foo: 123}.should == {foo: 123}
    h = {rbx: :cool, specs: 'fail_sometimes'}
    {rbx: :cool, specs: 'fail_sometimes'}.should == h
  end

  it "ignores a hanging comma" do
    {foo: 123,}.should == {foo: 123}
    h = {rbx: :cool, specs: 'fail_sometimes'}
    {rbx: :cool, specs: 'fail_sometimes',}.should == h
  end

  it "accepts mixed 'key: value' and 'key => value' syntax" do
    h = {:a => 1, :b => 2, "c" => 3}
    {a: 1, b: 2, "c" => 3}.should == h
  end

  it "accepts mixed 'key: value', 'key => value' and '\"key\"': value' syntax" do
    h = {:a => 1, :b => 2, "c" => 3, :d => 4}
    eval('{a: 1, :b => 2, "c" => 3, "d": 4}').should == h
  end

  it "expands an '**{}' element into the containing Hash literal initialization" do
    {a: 1, **{b: 2}, c: 3}.should == {a: 1, b: 2, c: 3}
  end

  it "expands an '**obj' element into the containing Hash literal initialization" do
    h = {b: 2, c: 3}
    {**h, a: 1}.should == {b: 2, c: 3, a: 1}
    {a: 1, **h}.should == {a: 1, b: 2, c: 3}
    {a: 1, **h, c: 4}.should == {a: 1, b: 2, c: 4}
  end

  it "expands a BasicObject using ** into the containing Hash literal initialization" do
    h = BasicObject.new
    def h.to_hash; {:b => 2, :c => 3}; end
    {**h, a: 1}.should == {b: 2, c: 3, a: 1}
    {a: 1, **h}.should == {a: 1, b: 2, c: 3}
    {a: 1, **h, c: 4}.should == {a: 1, b: 2, c: 4}
  end

  it "expands an '**{}' or '**obj' element with the last key/value pair taking precedence" do
    -> {
      @h = eval "{a: 1, **{a: 2, b: 3, c: 1}, c: 3}"
    }.should complain(/key :a is duplicated|duplicated key/)
    @h.should == {a: 2, b: 3, c: 3}

    -> {
      h = {a: 2, b: 3, c: 1}
      @h = eval "{a: 1, **h, c: 3}"
    }.should_not complain
    @h.should == {a: 2, b: 3, c: 3}
  end

  it "expands an '**{}' and warns when finding an additional duplicate key afterwards" do
    -> {
      @h = eval "{d: 1, **{a: 2, b: 3, c: 1}, c: 3}"
    }.should complain(/key :c is duplicated|duplicated key/)
    @h.should == {a: 2, b: 3, c: 3, d: 1}
  end

  it "merges multiple nested '**obj' in Hash literals" do
    -> {
      @h = eval "{a: 1, **{a: 2, **{b: 3, **{c: 4}}, **{d: 5}, }, **{d: 6}}"
    }.should complain(/key :a is duplicated|duplicated key/)
    @h.should == {a: 2, b: 3, c: 4, d: 6}
  end

  it "calls #to_hash to expand an '**obj' element" do
    obj = mock("hash splat")
    obj.should_receive(:to_hash).and_return({b: 2, d: 4})

    {a: 1, **obj, c: 3}.should == {a:1, b: 2, c: 3, d: 4}
  end

  it "allows splatted elements keys that are not symbols" do
    h = {1 => 2, b: 3}
    {a: 1, **h}.should == {a: 1, 1 => 2, b: 3}
  end

  it "raises a TypeError if #to_hash does not return a Hash" do
    obj = mock("hash splat")
    obj.should_receive(:to_hash).and_return(obj)

    -> { {**obj} }.should raise_error(TypeError)
  end

  it "raises a TypeError if the object does not respond to #to_hash" do
    obj = 42
    -> { {**obj} }.should raise_error(TypeError)
    -> { {a: 1, **obj} }.should raise_error(TypeError)
  end

  it "does not change encoding of literal string keys during creation" do
    binary_hash = HashStringsBinary.literal_hash
    utf8_hash = HashStringsUTF8.literal_hash
    usascii_hash = HashStringsUSASCII.literal_hash

    binary_hash.keys.first.encoding.should == Encoding::BINARY
    binary_hash.keys.first.should == utf8_hash.keys.first
    utf8_hash.keys.first.encoding.should == Encoding::UTF_8
    utf8_hash.keys.first.should == usascii_hash.keys.first
    usascii_hash.keys.first.encoding.should == Encoding::US_ASCII
  end

  ruby_bug "#20280", ""..."3.4" do
    it "raises a SyntaxError at parse time when Symbol key with invalid bytes" do
      ScratchPad.record []
      -> {
        eval 'ScratchPad << 1; {:"\xC3" => 1}'
      }.should raise_error(SyntaxError, /invalid symbol/)
      ScratchPad.recorded.should == []
    end

    it "raises a SyntaxError at parse time when Symbol key with invalid bytes and 'key: value' syntax used" do
      ScratchPad.record []
      -> {
        eval 'ScratchPad << 1; {"\xC3": 1}'
      }.should raise_error(SyntaxError, /invalid symbol/)
      ScratchPad.recorded.should == []
    end
  end

  describe "with omitted values" do # a.k.a. "Hash punning" or "Shorthand Hash syntax"
    it "accepts short notation 'key' for 'key: value' syntax" do
      a, b, c = 1, 2, 3
      h = eval('{a:}')
      {a: 1}.should == h
      h = eval('{a:, b:, c:}')
      {a: 1, b: 2, c: 3}.should == h
    end

    it "ignores hanging comma on short notation" do
      a, b, c = 1, 2, 3
      h = eval('{a:, b:, c:,}')
      {a: 1, b: 2, c: 3}.should == h
    end

    it "accepts mixed syntax" do
      a, e = 1, 5
      h = eval('{a:, b: 2, "c" => 3, :d => 4, e:}')
      eval('{a: 1, :b => 2, "c" => 3, "d": 4, e: 5}').should == h
    end

    # Copied from Prism::Translation::Ripper
    keywords = [
      "alias",
      "and",
      "begin",
      "BEGIN",
      "break",
      "case",
      "class",
      "def",
      "defined?",
      "do",
      "else",
      "elsif",
      "end",
      "END",
      "ensure",
      "false",
      "for",
      "if",
      "in",
      "module",
      "next",
      "nil",
      "not",
      "or",
      "redo",
      "rescue",
      "retry",
      "return",
      "self",
      "super",
      "then",
      "true",
      "undef",
      "unless",
      "until",
      "when",
      "while",
      "yield",
      "__ENCODING__",
      "__FILE__",
      "__LINE__"
    ]

    invalid_kw_param_names = [
      "BEGIN",
      "END",
      "defined?",
    ]

    invalid_method_names = [
      "BEGIN",
      "END",
      "defined?",
    ]

    # Evaluates the given Ruby source in a temporary Module, to prevent
    # the surrounding context from being polluted with the new methods.
    def sandboxed_eval(ruby_src)
      Module
        # Allows instance methods defined by `ruby_src` to be called directly.
        .new { extend self }
        .class_eval(ruby_src)
    end

    it "can reference local variables" do
      a = 1
      b = 2

      eval('{ a:, b: }.should == { a: 1, b: 2 }')
    end

    it "cannot find dynamically defined local variables" do
      b = binding
      b.local_variable_set(:abc, "a dynamically defined local var")

      eval <<~RUBY
        # The local variable definitely exists:
        b.local_variable_get(:abc).should == "a dynamically defined local var"
        # but we can't get it via value omission:
        -> { { abc: } }.should raise_error(NameError)
      RUBY
    end

    it "can call methods" do
      result = sandboxed_eval <<~RUBY
        def m = "a statically defined method"

        { m: }
      RUBY

      result.should == { m: "a statically defined method" }
    end

    it "can find dynamically defined methods" do
      result = sandboxed_eval <<~RUBY
        define_method(:m) { "a dynamically defined method" }

        { m: }
      RUBY

      result.should == { m: "a dynamically defined method" }
    end

    it "prefers local variables over methods" do
      result = sandboxed_eval <<~RUBY
        x = "from a local var"
        def x; "from a method"; end
        { x: }
      RUBY

      result.should == { x: "from a local var" }
    end

    describe "handling keywords" do
      keywords.each do |kw|
        describe "keyword '#{kw}'" do
          # None of these keywords can be used as local variables,
          # so it's not possible to resolve them via shorthand Hash syntax.
          # See `reserved_keywords.rb`

          unless invalid_kw_param_names.include?(kw)
            it "can be used a keyword parameter name" do
              result = sandboxed_eval <<~RUBY
                def m(#{kw}:) = { #{kw}: }

                m(#{kw}: "an argument to '#{kw}'")
              RUBY

              result.should == { kw.to_sym => "an argument to '#{kw}'" }
            end
          end

          unless invalid_method_names.include?(kw)
            it "can refer to a method called '#{kw}'" do
              result = sandboxed_eval <<~RUBY
                def #{kw} = "a method named '#{kw}'"

                { #{kw}: }
              RUBY

              result.should == { kw.to_sym => "a method named '#{kw}'" }
            end
          end
        end
      end

      describe "keyword 'self:'" do
        it "does not refer to actual 'self'" do
          eval <<~RUBY
            -> { { self: } }.should raise_error(NameError)
          RUBY
        end
      end
    end

    it "raises a SyntaxError when the Hash key ends with `!`" do
      -> { eval("{a!:}") }.should raise_error(SyntaxError, /identifier a! is not valid to get/)
    end

    it "raises a SyntaxError when the Hash key ends with `?`" do
      -> { eval("{a?:}") }.should raise_error(SyntaxError, /identifier a\? is not valid to get/)
    end
  end
end

describe "The ** operator" do
  it "makes a copy when calling a method taking a keyword rest argument" do
    def m(**h)
      h.delete(:one); h
    end

    h = { one: 1, two: 2 }
    m(**h).should == { two: 2 }
    m(**h).should_not.equal?(h)
    h.should == { one: 1, two: 2 }
  end

  ruby_bug "#20012", ""..."3.3" do
    it "makes a copy when calling a method taking a positional Hash" do
      def m(h)
        h.delete(:one); h
      end

      h = { one: 1, two: 2 }
      m(**h).should == { two: 2 }
      m(**h).should_not.equal?(h)
      h.should == { one: 1, two: 2 }
    end
  end
end
