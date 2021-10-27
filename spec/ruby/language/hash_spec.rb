require_relative '../spec_helper'
require_relative 'fixtures/hash_strings_binary'
require_relative 'fixtures/hash_strings_utf8'
require_relative 'fixtures/hash_strings_usascii'

describe "Hash literal" do
  it "{} should return an empty hash" do
    {}.size.should == 0
    {}.should == {}
  end

  it "{} should return a new hash populated with the given elements" do
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
    key = "foo"
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

  it "constructs a new hash with the given elements" do
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

  it "expands an '**{}' element with the last key/value pair taking precedence" do
    -> {
      @h = eval "{a: 1, **{a: 2, b: 3, c: 1}, c: 3}"
    }.should complain(/key :a is duplicated|duplicated key/)
    @h.should == {a: 2, b: 3, c: 3}
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

  ruby_version_is ""..."2.7" do
    it "raises a TypeError if any splatted elements keys are not symbols" do
      h = {1 => 2, b: 3}
      -> { {a: 1, **h} }.should raise_error(TypeError)
    end
  end

  ruby_version_is "2.7" do
    it "allows splatted elements keys that are not symbols" do
      h = {1 => 2, b: 3}
      {a: 1, **h}.should == {a: 1, 1 => 2, b: 3}
    end
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

  ruby_version_is ""..."3.0" do
    it "makes a caller-side copy when calling a method taking a positional Hash" do
      def m(h)
        h.delete(:one); h
      end

      h = { one: 1, two: 2 }
      m(**h).should == { two: 2 }
      m(**h).should_not.equal?(h)
      h.should == { one: 1, two: 2 }
    end
  end

  ruby_version_is "3.0" do
    it "does not copy when calling a method taking a positional Hash" do
      def m(h)
        h.delete(:one); h
      end

      h = { one: 1, two: 2 }
      m(**h).should == { two: 2 }
      m(**h).should.equal?(h)
      h.should == { two: 2 }
    end
  end

  ruby_version_is "3.1" do
    describe "hash with omitted value" do
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

      it "works with methods and local vars" do
        a = Class.new
        a.class_eval(<<-RUBY)
          def bar
            "baz"
          end

          def foo(val)
            {bar:, val:}
          end
        RUBY

        a.new.foo(1).should == {bar: "baz", val: 1}
      end
    end
  end
end
