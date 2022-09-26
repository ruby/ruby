describe :string_slice, shared: true do
  it "returns the character code of the character at the given index" do
    "hello".send(@method, 0).should == ?h
    "hello".send(@method, -1).should == ?o
  end

  it "returns nil if index is outside of self" do
    "hello".send(@method, 20).should == nil
    "hello".send(@method, -20).should == nil

    "".send(@method, 0).should == nil
    "".send(@method, -1).should == nil
  end

  it "calls to_int on the given index" do
    "hello".send(@method, 0.5).should == ?h

    obj = mock('1')
    obj.should_receive(:to_int).and_return(1)
    "hello".send(@method, obj).should == ?e
  end

  it "raises a TypeError if the given index is nil" do
    -> { "hello".send(@method, nil) }.should raise_error(TypeError)
  end

  it "raises a TypeError if the given index can't be converted to an Integer" do
    -> { "hello".send(@method, mock('x')) }.should raise_error(TypeError)
    -> { "hello".send(@method, {})        }.should raise_error(TypeError)
    -> { "hello".send(@method, [])        }.should raise_error(TypeError)
  end

  it "raises a RangeError if the index is too big" do
    -> { "hello".send(@method, bignum_value) }.should raise_error(RangeError)
  end
end

describe :string_slice_index_length, shared: true do
  it "returns the substring starting at the given index with the given length" do
    "hello there".send(@method, 0,0).should == ""
    "hello there".send(@method, 0,1).should == "h"
    "hello there".send(@method, 0,3).should == "hel"
    "hello there".send(@method, 0,6).should == "hello "
    "hello there".send(@method, 0,9).should == "hello the"
    "hello there".send(@method, 0,12).should == "hello there"

    "hello there".send(@method, 1,0).should == ""
    "hello there".send(@method, 1,1).should == "e"
    "hello there".send(@method, 1,3).should == "ell"
    "hello there".send(@method, 1,6).should == "ello t"
    "hello there".send(@method, 1,9).should == "ello ther"
    "hello there".send(@method, 1,12).should == "ello there"

    "hello there".send(@method, 3,0).should == ""
    "hello there".send(@method, 3,1).should == "l"
    "hello there".send(@method, 3,3).should == "lo "
    "hello there".send(@method, 3,6).should == "lo the"
    "hello there".send(@method, 3,9).should == "lo there"

    "hello there".send(@method, 4,0).should == ""
    "hello there".send(@method, 4,3).should == "o t"
    "hello there".send(@method, 4,6).should == "o ther"
    "hello there".send(@method, 4,9).should == "o there"

    "foo".send(@method, 2,1).should == "o"
    "foo".send(@method, 3,0).should == ""
    "foo".send(@method, 3,1).should == ""

    "".send(@method, 0,0).should == ""
    "".send(@method, 0,1).should == ""

    "x".send(@method, 0,0).should == ""
    "x".send(@method, 0,1).should == "x"
    "x".send(@method, 1,0).should == ""
    "x".send(@method, 1,1).should == ""

    "x".send(@method, -1,0).should == ""
    "x".send(@method, -1,1).should == "x"

    "hello there".send(@method, -3,2).should == "er"
  end

  it "returns a string with the same encoding" do
    s = "hello there"
    s.send(@method, 1, 9).encoding.should == s.encoding

    a = "hello".force_encoding("binary")
    b = " there".force_encoding("ISO-8859-1")
    c = (a + b).force_encoding(Encoding::US_ASCII)

    c.send(@method, 0, 5).encoding.should == Encoding::US_ASCII
    c.send(@method, 5, 6).encoding.should == Encoding::US_ASCII
    c.send(@method, 1, 3).encoding.should == Encoding::US_ASCII
    c.send(@method, 8, 2).encoding.should == Encoding::US_ASCII
    c.send(@method, 1, 10).encoding.should == Encoding::US_ASCII
  end

  it "returns nil if the offset falls outside of self" do
    "hello there".send(@method, 20,3).should == nil
    "hello there".send(@method, -20,3).should == nil

    "".send(@method, 1,0).should == nil
    "".send(@method, 1,1).should == nil

    "".send(@method, -1,0).should == nil
    "".send(@method, -1,1).should == nil

    "x".send(@method, 2,0).should == nil
    "x".send(@method, 2,1).should == nil

    "x".send(@method, -2,0).should == nil
    "x".send(@method, -2,1).should == nil

    "x".send(@method, fixnum_max, 1).should == nil
  end

  it "returns nil if the length is negative" do
    "hello there".send(@method, 4,-3).should == nil
    "hello there".send(@method, -4,-3).should == nil
  end

  it "calls to_int on the given index and the given length" do
    "hello".send(@method, 0.5, 1).should == "h"
    "hello".send(@method, 0.5, 2.5).should == "he"
    "hello".send(@method, 1, 2.5).should == "el"

    obj = mock('2')
    obj.should_receive(:to_int).exactly(4).times.and_return(2)

    "hello".send(@method, obj, 1).should == "l"
    "hello".send(@method, obj, obj).should == "ll"
    "hello".send(@method, 0, obj).should == "he"
  end

  it "raises a TypeError when idx or length can't be converted to an integer" do
    -> { "hello".send(@method, mock('x'), 0) }.should raise_error(TypeError)
    -> { "hello".send(@method, 0, mock('x')) }.should raise_error(TypeError)

    # I'm deliberately including this here.
    # It means that str.send(@method, other, idx) isn't supported.
    -> { "hello".send(@method, "", 0) }.should raise_error(TypeError)
  end

  it "raises a TypeError when the given index or the given length is nil" do
    -> { "hello".send(@method, 1, nil)   }.should raise_error(TypeError)
    -> { "hello".send(@method, nil, 1)   }.should raise_error(TypeError)
    -> { "hello".send(@method, nil, nil) }.should raise_error(TypeError)
  end

  it "raises a RangeError if the index or length is too big" do
    -> { "hello".send(@method, bignum_value, 1) }.should raise_error(RangeError)
    -> { "hello".send(@method, 0, bignum_value) }.should raise_error(RangeError)
  end

  ruby_version_is ''...'3.0' do
    it "returns subclass instances" do
      s = StringSpecs::MyString.new("hello")
      s.send(@method, 0,0).should be_an_instance_of(StringSpecs::MyString)
      s.send(@method, 0,4).should be_an_instance_of(StringSpecs::MyString)
      s.send(@method, 1,4).should be_an_instance_of(StringSpecs::MyString)
    end
  end

  ruby_version_is '3.0' do
    it "returns String instances" do
      s = StringSpecs::MyString.new("hello")
      s.send(@method, 0,0).should be_an_instance_of(String)
      s.send(@method, 0,4).should be_an_instance_of(String)
      s.send(@method, 1,4).should be_an_instance_of(String)
    end
  end

  it "handles repeated application" do
    "hello world".send(@method, 6, 5).send(@method, 0, 1).should == 'w'
    "hello world".send(@method, 6, 5).send(@method, 0, 5).should == 'world'

    "hello world".send(@method, 6, 5).send(@method, 1, 1).should == 'o'
    "hello world".send(@method, 6, 5).send(@method, 1, 4).should == 'orld'

    "hello world".send(@method, 6, 5).send(@method, 4, 1).should == 'd'
    "hello world".send(@method, 6, 5).send(@method, 5, 0).should == ''

    "hello world".send(@method, 6, 0).send(@method, -1, 0).should == nil
    "hello world".send(@method, 6, 0).send(@method, 1, 1).should == nil
  end
end

describe :string_slice_range, shared: true do
  it "returns the substring given by the offsets of the range" do
    "hello there".send(@method, 1..1).should == "e"
    "hello there".send(@method, 1..3).should == "ell"
    "hello there".send(@method, 1...3).should == "el"
    "hello there".send(@method, -4..-2).should == "her"
    "hello there".send(@method, -4...-2).should == "he"
    "hello there".send(@method, 5..-1).should == " there"
    "hello there".send(@method, 5...-1).should == " ther"

    "".send(@method, 0..0).should == ""

    "x".send(@method, 0..0).should == "x"
    "x".send(@method, 0..1).should == "x"
    "x".send(@method, 0...1).should == "x"
    "x".send(@method, 0..-1).should == "x"

    "x".send(@method, 1..1).should == ""
    "x".send(@method, 1..-1).should == ""
  end

  it "returns nil if the beginning of the range falls outside of self" do
    "hello there".send(@method, 12..-1).should == nil
    "hello there".send(@method, 20..25).should == nil
    "hello there".send(@method, 20..1).should == nil
    "hello there".send(@method, -20..1).should == nil
    "hello there".send(@method, -20..-1).should == nil

    "".send(@method, -1..-1).should == nil
    "".send(@method, -1...-1).should == nil
    "".send(@method, -1..0).should == nil
    "".send(@method, -1...0).should == nil
  end

  it "returns an empty string if range.begin is inside self and > real end" do
    "hello there".send(@method, 1...1).should == ""
    "hello there".send(@method, 4..2).should == ""
    "hello".send(@method, 4..-4).should == ""
    "hello there".send(@method, -5..-6).should == ""
    "hello there".send(@method, -2..-4).should == ""
    "hello there".send(@method, -5..-6).should == ""
    "hello there".send(@method, -5..2).should == ""

    "".send(@method, 0...0).should == ""
    "".send(@method, 0..-1).should == ""
    "".send(@method, 0...-1).should == ""

    "x".send(@method, 0...0).should == ""
    "x".send(@method, 0...-1).should == ""
    "x".send(@method, 1...1).should == ""
    "x".send(@method, 1...-1).should == ""
  end

  ruby_version_is ''...'3.0' do
    it "returns subclass instances" do
      s = StringSpecs::MyString.new("hello")
      s.send(@method, 0...0).should be_an_instance_of(StringSpecs::MyString)
      s.send(@method, 0..4).should be_an_instance_of(StringSpecs::MyString)
      s.send(@method, 1..4).should be_an_instance_of(StringSpecs::MyString)
    end
  end

  ruby_version_is '3.0' do
    it "returns String instances" do
      s = StringSpecs::MyString.new("hello")
      s.send(@method, 0...0).should be_an_instance_of(String)
      s.send(@method, 0..4).should be_an_instance_of(String)
      s.send(@method, 1..4).should be_an_instance_of(String)
    end
  end

  it "calls to_int on range arguments" do
    from = mock('from')
    to = mock('to')

    # So we can construct a range out of them...
    from.should_receive(:<=>).twice.and_return(0)

    from.should_receive(:to_int).twice.and_return(1)
    to.should_receive(:to_int).twice.and_return(-2)

    "hello there".send(@method, from..to).should == "ello ther"
    "hello there".send(@method, from...to).should == "ello the"
  end

  it "works with Range subclasses" do
    a = "GOOD"
    range_incl = StringSpecs::MyRange.new(1, 2)
    range_excl = StringSpecs::MyRange.new(-3, -1, true)

    a.send(@method, range_incl).should == "OO"
    a.send(@method, range_excl).should == "OO"
  end

  it "handles repeated application" do
    "hello world".send(@method, 6..11).send(@method, 0..0).should == 'w'
    "hello world".send(@method, 6..11).send(@method, 0..4).should == 'world'

    "hello world".send(@method, 6..11).send(@method, 1..1).should == 'o'
    "hello world".send(@method, 6..11).send(@method, 1..4).should == 'orld'

    "hello world".send(@method, 6..11).send(@method, 4..4).should == 'd'
    "hello world".send(@method, 6..11).send(@method, 5..4).should == ''

    "hello world".send(@method, 6..5).send(@method, -1..-1).should == nil
    "hello world".send(@method, 6..5).send(@method, 1..1).should == nil
  end

  it "raises a type error if a range is passed with a length" do
    ->{ "hello".send(@method, 1..2, 1) }.should raise_error(TypeError)
  end

  it "raises a RangeError if one of the bound is too big" do
    -> { "hello".send(@method, bignum_value..(bignum_value + 1)) }.should raise_error(RangeError)
    -> { "hello".send(@method, 0..bignum_value) }.should raise_error(RangeError)
  end

  it "works with endless ranges" do
    "hello there".send(@method, eval("(2..)")).should == "llo there"
    "hello there".send(@method, eval("(2...)")).should == "llo there"
    "hello there".send(@method, eval("(-4..)")).should == "here"
    "hello there".send(@method, eval("(-4...)")).should == "here"
  end

  it "works with beginless ranges" do
    "hello there".send(@method, (..5)).should == "hello "
    "hello there".send(@method, (...5)).should == "hello"
    "hello there".send(@method, (..-4)).should == "hello th"
    "hello there".send(@method, (...-4)).should == "hello t"
    "hello there".send(@method, (...nil)).should == "hello there"
  end
end

describe :string_slice_regexp, shared: true do
  it "returns the matching portion of self" do
    "hello there".send(@method, /[aeiou](.)\1/).should == "ell"
    "".send(@method, //).should == ""
  end

  it "returns nil if there is no match" do
    "hello there".send(@method, /xyz/).should == nil
  end

  not_supported_on :opal do
  end

  ruby_version_is ''...'3.0' do
    it "returns subclass instances" do
      s = StringSpecs::MyString.new("hello")
      s.send(@method, //).should be_an_instance_of(StringSpecs::MyString)
      s.send(@method, /../).should be_an_instance_of(StringSpecs::MyString)
    end
  end

  ruby_version_is '3.0' do
    it "returns String instances" do
      s = StringSpecs::MyString.new("hello")
      s.send(@method, //).should be_an_instance_of(String)
      s.send(@method, /../).should be_an_instance_of(String)
    end
  end

  it "sets $~ to MatchData when there is a match and nil when there's none" do
    'hello'.send(@method, /./)
    $~[0].should == 'h'

    'hello'.send(@method, /not/)
    $~.should == nil
  end
end

describe :string_slice_regexp_index, shared: true do
  it "returns the capture for the given index" do
    "hello there".send(@method, /[aeiou](.)\1/, 0).should == "ell"
    "hello there".send(@method, /[aeiou](.)\1/, 1).should == "l"
    "hello there".send(@method, /[aeiou](.)\1/, -1).should == "l"

    "har".send(@method, /(.)(.)(.)/, 0).should == "har"
    "har".send(@method, /(.)(.)(.)/, 1).should == "h"
    "har".send(@method, /(.)(.)(.)/, 2).should == "a"
    "har".send(@method, /(.)(.)(.)/, 3).should == "r"
    "har".send(@method, /(.)(.)(.)/, -1).should == "r"
    "har".send(@method, /(.)(.)(.)/, -2).should == "a"
    "har".send(@method, /(.)(.)(.)/, -3).should == "h"
  end

  it "returns nil if there is no match" do
    "hello there".send(@method, /(what?)/, 1).should == nil
  end

  it "returns nil if the index is larger than the number of captures" do
    "hello there".send(@method, /hello (.)/, 2).should == nil
    # You can't refer to 0 using negative indices
    "hello there".send(@method, /hello (.)/, -2).should == nil
  end

  it "returns nil if there is no capture for the given index" do
    "hello there".send(@method, /[aeiou](.)\1/, 2).should == nil
  end

  it "returns nil if the given capture group was not matched but still sets $~" do
    "test".send(@method, /te(z)?/, 1).should == nil
    $~[0].should == "te"
    $~[1].should == nil
  end

  it "calls to_int on the given index" do
    obj = mock('2')
    obj.should_receive(:to_int).and_return(2)

    "har".send(@method, /(.)(.)(.)/, 1.5).should == "h"
    "har".send(@method, /(.)(.)(.)/, obj).should == "a"
  end

  it "raises a TypeError when the given index can't be converted to Integer" do
    -> { "hello".send(@method, /(.)(.)(.)/, mock('x')) }.should raise_error(TypeError)
    -> { "hello".send(@method, /(.)(.)(.)/, {})        }.should raise_error(TypeError)
    -> { "hello".send(@method, /(.)(.)(.)/, [])        }.should raise_error(TypeError)
  end

  it "raises a TypeError when the given index is nil" do
    -> { "hello".send(@method, /(.)(.)(.)/, nil) }.should raise_error(TypeError)
  end

  ruby_version_is ''...'3.0' do
    it "returns subclass instances" do
      s = StringSpecs::MyString.new("hello")
      s.send(@method, /(.)(.)/, 0).should be_an_instance_of(StringSpecs::MyString)
      s.send(@method, /(.)(.)/, 1).should be_an_instance_of(StringSpecs::MyString)
    end
  end

  ruby_version_is '3.0' do
    it "returns String instances" do
      s = StringSpecs::MyString.new("hello")
      s.send(@method, /(.)(.)/, 0).should be_an_instance_of(String)
      s.send(@method, /(.)(.)/, 1).should be_an_instance_of(String)
    end
  end

  it "sets $~ to MatchData when there is a match and nil when there's none" do
    'hello'.send(@method, /.(.)/, 0)
    $~[0].should == 'he'

    'hello'.send(@method, /.(.)/, 1)
    $~[1].should == 'e'

    'hello'.send(@method, /not/, 0)
    $~.should == nil
  end
end

describe :string_slice_string, shared: true do
  it "returns other_str if it occurs in self" do
    s = "lo"
    "hello there".send(@method, s).should == s
  end

  it "doesn't set $~" do
    $~ = nil

    'hello'.send(@method, 'll')
    $~.should == nil
  end

  it "returns nil if there is no match" do
    "hello there".send(@method, "bye").should == nil
  end

  it "doesn't call to_str on its argument" do
    o = mock('x')
    o.should_not_receive(:to_str)

    -> { "hello".send(@method, o) }.should raise_error(TypeError)
  end

  ruby_version_is ''...'3.0' do
    it "returns a subclass instance when given a subclass instance" do
      s = StringSpecs::MyString.new("el")
      r = "hello".send(@method, s)
      r.should == "el"
      r.should be_an_instance_of(StringSpecs::MyString)
    end
  end

  ruby_version_is '3.0' do
    it "returns a String instance when given a subclass instance" do
      s = StringSpecs::MyString.new("el")
      r = "hello".send(@method, s)
      r.should == "el"
      r.should be_an_instance_of(String)
    end
  end
end

describe :string_slice_regexp_group, shared: true do
  not_supported_on :opal do
    it "returns the capture for the given name" do
      "hello there".send(@method, /(?<g>[aeiou](.))/, 'g').should == "el"
      "hello there".send(@method, /[aeiou](?<g>.)/, 'g').should == "l"

      "har".send(@method, /(?<g>(.)(.)(.))/, 'g').should == "har"
      "har".send(@method, /(?<h>.)(.)(.)/, 'h').should == "h"
      "har".send(@method, /(.)(?<a>.)(.)/, 'a').should == "a"
      "har".send(@method, /(.)(.)(?<r>.)/, 'r').should == "r"
      "har".send(@method, /(?<h>.)(?<a>.)(?<r>.)/, 'r').should == "r"
    end

    it "returns the last capture for duplicate names" do
      "hello there".send(@method, /(?<g>h)(?<g>.)/, 'g').should == "e"
      "hello there".send(@method, /(?<g>h)(?<g>.)(?<f>.)/, 'g').should == "e"
    end

    it "returns the innermost capture for nested duplicate names" do
      "hello there".send(@method, /(?<g>h(?<g>.))/, 'g').should == "e"
    end

    it "returns nil if there is no match" do
      "hello there".send(@method, /(?<whut>what?)/, 'whut').should be_nil
    end

    it "raises an IndexError if there is no capture for the given name" do
      -> do
        "hello there".send(@method, /[aeiou](.)\1/, 'non')
      end.should raise_error(IndexError)
    end

    it "raises a TypeError when the given name is not a String" do
      -> { "hello".send(@method, /(?<q>.)/, mock('x')) }.should raise_error(TypeError)
      -> { "hello".send(@method, /(?<q>.)/, {})        }.should raise_error(TypeError)
      -> { "hello".send(@method, /(?<q>.)/, [])        }.should raise_error(TypeError)
    end

    it "raises an IndexError when given the empty String as a group name" do
      -> { "hello".send(@method, /(?<q>)/, '') }.should raise_error(IndexError)
    end

    ruby_version_is ''...'3.0' do
      it "returns subclass instances" do
        s = StringSpecs::MyString.new("hello")
        s.send(@method, /(?<q>.)/, 'q').should be_an_instance_of(StringSpecs::MyString)
      end
    end

    ruby_version_is '3.0' do
      it "returns String instances" do
        s = StringSpecs::MyString.new("hello")
        s.send(@method, /(?<q>.)/, 'q').should be_an_instance_of(String)
      end
    end

    it "sets $~ to MatchData when there is a match and nil when there's none" do
      'hello'.send(@method, /(?<hi>.(.))/, 'hi')
      $~[0].should == 'he'

      'hello'.send(@method, /(?<non>not)/, 'non')
      $~.should be_nil
    end
  end
end

describe :string_slice_symbol, shared: true do
  it "raises TypeError" do
    -> { 'hello'.send(@method, :hello) }.should raise_error(TypeError)
  end
end

describe :string_slice_bang, shared: true do
  it "deletes and return the char at the given position" do
    a = "hello"
    a.slice!(1).should == ?e
    a.should == "hllo"
    a.slice!(-1).should == ?o
    a.should == "hll"
  end

  it "returns nil if idx is outside of self" do
    a = "hello"
    a.slice!(20).should == nil
    a.should == "hello"
    a.slice!(-20).should == nil
    a.should == "hello"
  end

  it "raises a FrozenError if self is frozen" do
    -> { "hello".freeze.slice!(1)  }.should raise_error(FrozenError)
    -> { "hello".freeze.slice!(10) }.should raise_error(FrozenError)
    -> { "".freeze.slice!(0)       }.should raise_error(FrozenError)
  end

  it "calls to_int on index" do
    "hello".slice!(0.5).should == ?h

    obj = mock('1')
    obj.should_receive(:to_int).at_least(1).and_return(1)
    "hello".slice!(obj).should == ?e

    obj = mock('1')
    obj.should_receive(:respond_to?).at_least(1).with(:to_int, true).and_return(true)
    obj.should_receive(:method_missing).at_least(1).with(:to_int).and_return(1)
    "hello".slice!(obj).should == ?e
  end


  it "returns the character given by the character index" do
    "hellö there".slice!(1).should == "e"
    "hellö there".slice!(4).should == "ö"
    "hellö there".slice!(6).should == "t"
  end

end

describe :string_slice_bang_index_length, shared: true do
  it "deletes and returns the substring at idx and the given length" do
    a = "hello"
    a.slice!(1, 2).should == "el"
    a.should == "hlo"

    a.slice!(1, 0).should == ""
    a.should == "hlo"

    a.slice!(-2, 4).should == "lo"
    a.should == "h"
  end

  it "returns nil if the given position is out of self" do
    a = "hello"
    a.slice(10, 3).should == nil
    a.should == "hello"

    a.slice(-10, 20).should == nil
    a.should == "hello"
  end

  it "returns nil if the length is negative" do
    a = "hello"
    a.slice(4, -3).should == nil
    a.should == "hello"
  end

  it "raises a FrozenError if self is frozen" do
    -> { "hello".freeze.slice!(1, 2)  }.should raise_error(FrozenError)
    -> { "hello".freeze.slice!(10, 3) }.should raise_error(FrozenError)
    -> { "hello".freeze.slice!(-10, 3)}.should raise_error(FrozenError)
    -> { "hello".freeze.slice!(4, -3) }.should raise_error(FrozenError)
    -> { "hello".freeze.slice!(10, 3) }.should raise_error(FrozenError)
    -> { "hello".freeze.slice!(-10, 3)}.should raise_error(FrozenError)
    -> { "hello".freeze.slice!(4, -3) }.should raise_error(FrozenError)
  end

  it "calls to_int on idx and length" do
    "hello".slice!(0.5, 2.5).should == "he"

    obj = mock('2')
    def obj.to_int() 2 end
    "hello".slice!(obj, obj).should == "ll"

    obj = mock('2')
    def obj.respond_to?(name, *) name == :to_int; end
    def obj.method_missing(name, *) name == :to_int ? 2 : super; end
    "hello".slice!(obj, obj).should == "ll"
  end

  ruby_version_is ''...'3.0' do
    it "returns subclass instances" do
      s = StringSpecs::MyString.new("hello")
      s.slice!(0, 0).should be_an_instance_of(StringSpecs::MyString)
      s.slice!(0, 4).should be_an_instance_of(StringSpecs::MyString)
    end
  end

  ruby_version_is '3.0' do
    it "returns String instances" do
      s = StringSpecs::MyString.new("hello")
      s.slice!(0, 0).should be_an_instance_of(String)
      s.slice!(0, 4).should be_an_instance_of(String)
    end
  end

  it "returns the substring given by the character offsets" do
    "hellö there".slice!(1,0).should == ""
    "hellö there".slice!(1,3).should == "ell"
    "hellö there".slice!(1,6).should == "ellö t"
    "hellö there".slice!(1,9).should == "ellö ther"
  end

  it "treats invalid bytes as single bytes" do
    xE6xCB = [0xE6,0xCB].pack('CC').force_encoding('utf-8')
    "a#{xE6xCB}b".slice!(1, 2).should == xE6xCB
  end
end

describe :string_slice_bang_range, shared: true do
  it "deletes and return the substring given by the offsets of the range" do
    a = "hello"
    a.slice!(1..3).should == "ell"
    a.should == "ho"
    a.slice!(0..0).should == "h"
    a.should == "o"
    a.slice!(0...0).should == ""
    a.should == "o"

    # Edge Case?
    "hello".slice!(-3..-9).should == ""
  end

  it "returns nil if the given range is out of self" do
    a = "hello"
    a.slice!(-6..-9).should == nil
    a.should == "hello"

    b = "hello"
    b.slice!(10..20).should == nil
    b.should == "hello"
  end

  ruby_version_is ''...'3.0' do
    it "returns subclass instances" do
      s = StringSpecs::MyString.new("hello")
      s.slice!(0...0).should be_an_instance_of(StringSpecs::MyString)
      s.slice!(0..4).should be_an_instance_of(StringSpecs::MyString)
    end
  end

  ruby_version_is '3.0' do
    it "returns String instances" do
      s = StringSpecs::MyString.new("hello")
      s.slice!(0...0).should be_an_instance_of(String)
      s.slice!(0..4).should be_an_instance_of(String)
    end
  end

  it "calls to_int on range arguments" do
    from = mock('from')
    to = mock('to')

    # So we can construct a range out of them...
    def from.<=>(o) 0 end
    def to.<=>(o) 0 end

    def from.to_int() 1 end
    def to.to_int() -2 end

    "hello there".slice!(from..to).should == "ello ther"

    from = mock('from')
    to = mock('to')

    def from.<=>(o) 0 end
    def to.<=>(o) 0 end

    def from.respond_to?(name, *) name == :to_int; end
    def from.method_missing(name) name == :to_int ? 1 : super; end
    def to.respond_to?(name, *) name == :to_int; end
    def to.method_missing(name) name == :to_int ? -2 : super; end

    "hello there".slice!(from..to).should == "ello ther"
  end

  it "works with Range subclasses" do
    a = "GOOD"
    range_incl = StringSpecs::MyRange.new(1, 2)

    a.slice!(range_incl).should == "OO"
  end


  it "returns the substring given by the character offsets of the range" do
    "hellö there".slice!(1..1).should == "e"
    "hellö there".slice!(1..3).should == "ell"
    "hellö there".slice!(1...3).should == "el"
    "hellö there".slice!(-4..-2).should == "her"
    "hellö there".slice!(-4...-2).should == "he"
    "hellö there".slice!(5..-1).should == " there"
    "hellö there".slice!(5...-1).should == " ther"
  end


  it "raises a FrozenError on a frozen instance that is modified" do
    -> { "hello".freeze.slice!(1..3)  }.should raise_error(FrozenError)
  end

  # see redmine #1551
  it "raises a FrozenError on a frozen instance that would not be modified" do
    -> { "hello".freeze.slice!(10..20)}.should raise_error(FrozenError)
  end
end

describe :string_slice_bang_regexp, shared: true do
  it "deletes and returns the first match from self" do
    s = "this is a string"
    s.slice!(/s.*t/).should == 's is a st'
    s.should == 'thiring'

    c = "hello hello"
    c.slice!(/llo/).should == "llo"
    c.should == "he hello"
  end

  it "returns nil if there was no match" do
    s = "this is a string"
    s.slice!(/zzz/).should == nil
    s.should == "this is a string"
  end

  ruby_version_is ''...'3.0' do
    it "returns subclass instances" do
      s = StringSpecs::MyString.new("hello")
      s.slice!(//).should be_an_instance_of(StringSpecs::MyString)
      s.slice!(/../).should be_an_instance_of(StringSpecs::MyString)
    end
  end

  ruby_version_is '3.0' do
    it "returns String instances" do
      s = StringSpecs::MyString.new("hello")
      s.slice!(//).should be_an_instance_of(String)
      s.slice!(/../).should be_an_instance_of(String)
    end
  end

  it "returns the matching portion of self with a multi byte character" do
    "hëllo there".slice!(/[ë](.)\1/).should == "ëll"
    "".slice!(//).should == ""
  end

  it "sets $~ to MatchData when there is a match and nil when there's none" do
    'hello'.slice!(/./)
    $~[0].should == 'h'

    'hello'.slice!(/not/)
    $~.should == nil
  end

  it "raises a FrozenError on a frozen instance that is modified" do
    -> { "this is a string".freeze.slice!(/s.*t/) }.should raise_error(FrozenError)
  end

  it "raises a FrozenError on a frozen instance that would not be modified" do
    -> { "this is a string".freeze.slice!(/zzz/)  }.should raise_error(FrozenError)
  end
end

describe :string_slice_bang_regexp_index, shared: true do
  it "deletes and returns the capture for idx from self" do
    str = "hello there"
    str.slice!(/[aeiou](.)\1/, 0).should == "ell"
    str.should == "ho there"
    str.slice!(/(t)h/, 1).should == "t"
    str.should == "ho here"
  end

  it "returns nil if there was no match" do
    s = "this is a string"
    s.slice!(/x(zzz)/, 1).should == nil
    s.should == "this is a string"
  end

  it "returns nil if there is no capture for idx" do
    "hello there".slice!(/[aeiou](.)\1/, 2).should == nil
    # You can't refer to 0 using negative indices
    "hello there".slice!(/[aeiou](.)\1/, -2).should == nil
  end

  it "accepts a Float for capture index" do
    "har".slice!(/(.)(.)(.)/, 1.5).should == "h"
  end

  it "calls #to_int to convert an Object to capture index" do
    obj = mock('2')
    obj.should_receive(:to_int).at_least(1).times.and_return(2)

    "har".slice!(/(.)(.)(.)/, obj).should == "a"
  end

  ruby_version_is ''...'3.0' do
    it "returns subclass instances" do
      s = StringSpecs::MyString.new("hello")
      s.slice!(/(.)(.)/, 0).should be_an_instance_of(StringSpecs::MyString)
      s.slice!(/(.)(.)/, 1).should be_an_instance_of(StringSpecs::MyString)
    end
  end

  ruby_version_is '3.0' do
    it "returns String instances" do
      s = StringSpecs::MyString.new("hello")
      s.slice!(/(.)(.)/, 0).should be_an_instance_of(String)
      s.slice!(/(.)(.)/, 1).should be_an_instance_of(String)
    end
  end

  it "returns the encoding aware capture for the given index" do
    "hår".slice!(/(.)(.)(.)/, 0).should == "hår"
    "hår".slice!(/(.)(.)(.)/, 1).should == "h"
    "hår".slice!(/(.)(.)(.)/, 2).should == "å"
    "hår".slice!(/(.)(.)(.)/, 3).should == "r"
    "hår".slice!(/(.)(.)(.)/, -1).should == "r"
    "hår".slice!(/(.)(.)(.)/, -2).should == "å"
    "hår".slice!(/(.)(.)(.)/, -3).should == "h"
  end

  it "sets $~ to MatchData when there is a match and nil when there's none" do
    'hello'[/.(.)/, 0]
    $~[0].should == 'he'

    'hello'[/.(.)/, 1]
    $~[1].should == 'e'

    'hello'[/not/, 0]
    $~.should == nil
  end

  it "raises a FrozenError if self is frozen" do
    -> { "this is a string".freeze.slice!(/s.*t/)  }.should raise_error(FrozenError)
    -> { "this is a string".freeze.slice!(/zzz/, 0)}.should raise_error(FrozenError)
    -> { "this is a string".freeze.slice!(/(.)/, 2)}.should raise_error(FrozenError)
  end
end

describe :string_slice_bang_string, shared: true do
  it "removes and returns the first occurrence of other_str from self" do
    c = "hello hello"
    c.slice!('llo').should == "llo"
    c.should == "he hello"
  end

  it "doesn't set $~" do
    $~ = nil

    'hello'.slice!('ll')
    $~.should == nil
  end

  it "returns nil if self does not contain other" do
    a = "hello"
    a.slice!('zzz').should == nil
    a.should == "hello"
  end

  it "doesn't call to_str on its argument" do
    o = mock('x')
    o.should_not_receive(:to_str)

    -> { "hello".slice!(o) }.should raise_error(TypeError)
  end

  ruby_version_is ''...'3.0' do
    it "returns a subclass instance when given a subclass instance" do
      s = StringSpecs::MyString.new("el")
      r = "hello".slice!(s)
      r.should == "el"
      r.should be_an_instance_of(StringSpecs::MyString)
    end
  end

  ruby_version_is '3.0' do
    it "returns a subclass instance when given a subclass instance" do
      s = StringSpecs::MyString.new("el")
      r = "hello".slice!(s)
      r.should == "el"
      r.should be_an_instance_of(String)
    end
  end

  it "raises a FrozenError if self is frozen" do
    -> { "hello hello".freeze.slice!('llo')     }.should raise_error(FrozenError)
    -> { "this is a string".freeze.slice!('zzz')}.should raise_error(FrozenError)
    -> { "this is a string".freeze.slice!('zzz')}.should raise_error(FrozenError)
  end
end
