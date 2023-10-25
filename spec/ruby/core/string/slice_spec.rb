# -*- encoding: utf-8 -*-

require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/slice'

describe "String#slice" do
  it_behaves_like :string_slice, :slice
end

describe "String#slice with index, length" do
  it_behaves_like :string_slice_index_length, :slice
end

describe "String#slice with Range" do
  it_behaves_like :string_slice_range, :slice
end

describe "String#slice with Regexp" do
  it_behaves_like :string_slice_regexp, :slice
end

describe "String#slice with Regexp, index" do
  it_behaves_like :string_slice_regexp_index, :slice
end

describe "String#slice with Regexp, group" do
  it_behaves_like :string_slice_regexp_group, :slice
end

describe "String#slice with String" do
  it_behaves_like :string_slice_string, :slice
end

describe "String#slice with Symbol" do
  it_behaves_like :string_slice_symbol, :slice
end

describe "String#slice! with index" do
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

describe "String#slice! with index, length" do
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

  it "returns String instances" do
    s = StringSpecs::MyString.new("hello")
    s.slice!(0, 0).should be_an_instance_of(String)
    s.slice!(0, 4).should be_an_instance_of(String)
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

describe "String#slice! Range" do
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

  it "returns String instances" do
    s = StringSpecs::MyString.new("hello")
    s.slice!(0...0).should be_an_instance_of(String)
    s.slice!(0..4).should be_an_instance_of(String)
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

describe "String#slice! with Regexp" do
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

  it "returns String instances" do
    s = StringSpecs::MyString.new("hello")
    s.slice!(//).should be_an_instance_of(String)
    s.slice!(/../).should be_an_instance_of(String)
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

describe "String#slice! with Regexp, index" do
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

  it "returns String instances" do
    s = StringSpecs::MyString.new("hello")
    s.slice!(/(.)(.)/, 0).should be_an_instance_of(String)
    s.slice!(/(.)(.)/, 1).should be_an_instance_of(String)
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

describe "String#slice! with String" do
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

  it "returns a subclass instance when given a subclass instance" do
    s = StringSpecs::MyString.new("el")
    r = "hello".slice!(s)
    r.should == "el"
    r.should be_an_instance_of(String)
  end

  it "raises a FrozenError if self is frozen" do
    -> { "hello hello".freeze.slice!('llo')     }.should raise_error(FrozenError)
    -> { "this is a string".freeze.slice!('zzz')}.should raise_error(FrozenError)
    -> { "this is a string".freeze.slice!('zzz')}.should raise_error(FrozenError)
  end
end
