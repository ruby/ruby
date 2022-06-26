# -*- encoding: utf-8 -*-
require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "String#split with String" do
  it "throws an ArgumentError if the string  is not a valid" do
    s = "\xDF".force_encoding(Encoding::UTF_8)

    -> { s.split }.should raise_error(ArgumentError)
    -> { s.split(':') }.should raise_error(ArgumentError)
  end

  it "throws an ArgumentError if the pattern is not a valid string" do
    str = 'проверка'
    broken_str = "\xDF".force_encoding(Encoding::UTF_8)

    -> { str.split(broken_str) }.should raise_error(ArgumentError)
  end

  it "splits on multibyte characters" do
    "ありがりがとう".split("が").should == ["あり", "り", "とう"]
  end

  it "returns an array of substrings based on splitting on the given string" do
    "mellow yellow".split("ello").should == ["m", "w y", "w"]
  end

  it "suppresses trailing empty fields when limit isn't given or 0" do
    "1,2,,3,4,,".split(',').should == ["1", "2", "", "3", "4"]
    "1,2,,3,4,,".split(',', 0).should == ["1", "2", "", "3", "4"]
    "  a  b  c\nd  ".split("  ").should == ["", "a", "b", "c\nd"]
    "hai".split("hai").should == []
    ",".split(",").should == []
    ",".split(",", 0).should == []
  end

  it "returns an array with one entry if limit is 1: the original string" do
    "hai".split("hai", 1).should == ["hai"]
    "x.y.z".split(".", 1).should == ["x.y.z"]
    "hello world ".split(" ", 1).should == ["hello world "]
    "hi!".split("", 1).should == ["hi!"]
  end

  it "returns at most limit fields when limit > 1" do
    "hai".split("hai", 2).should == ["", ""]

    "1,2".split(",", 3).should == ["1", "2"]

    "1,2,,3,4,,".split(',', 2).should == ["1", "2,,3,4,,"]
    "1,2,,3,4,,".split(',', 3).should == ["1", "2", ",3,4,,"]
    "1,2,,3,4,,".split(',', 4).should == ["1", "2", "", "3,4,,"]
    "1,2,,3,4,,".split(',', 5).should == ["1", "2", "", "3", "4,,"]
    "1,2,,3,4,,".split(',', 6).should == ["1", "2", "", "3", "4", ","]

    "x".split('x', 2).should == ["", ""]
    "xx".split('x', 2).should == ["", "x"]
    "xx".split('x', 3).should == ["", "", ""]
    "xxx".split('x', 2).should == ["", "xx"]
    "xxx".split('x', 3).should == ["", "", "x"]
    "xxx".split('x', 4).should == ["", "", "", ""]
  end

  it "doesn't suppress or limit fields when limit is negative" do
    "1,2,,3,4,,".split(',', -1).should == ["1", "2", "", "3", "4", "", ""]
    "1,2,,3,4,,".split(',', -5).should == ["1", "2", "", "3", "4", "", ""]
    "  a  b  c\nd  ".split("  ", -1).should == ["", "a", "b", "c\nd", ""]
    ",".split(",", -1).should == ["", ""]
  end

  it "raises a RangeError when the limit is larger than int" do
    -> { "a,b".split(" ", 2147483649) }.should raise_error(RangeError)
  end

  it "defaults to $; when string isn't given or nil" do
    suppress_warning do
      old_fs = $;
      begin
        [",", ":", "", "XY", nil].each do |fs|
          $; = fs

          ["x,y,z,,,", "1:2:", "aXYbXYcXY", ""].each do |str|
            expected = str.split(fs || " ")

            str.split(nil).should == expected
            str.split.should == expected

            str.split(nil, -1).should == str.split(fs || " ", -1)
            str.split(nil, 0).should == str.split(fs || " ", 0)
            str.split(nil, 2).should == str.split(fs || " ", 2)
          end
        end
      ensure
        $; = old_fs
      end
    end

    context "when $; is not nil" do
      before do
        suppress_warning do
          @old_value, $; = $;, 'foobar'
        end
      end

      after do
        $; = @old_value
      end

      it "warns" do
        -> { "".split }.should complain(/warning: \$; is set to non-nil value/)
      end
    end
  end

  it "ignores leading and continuous whitespace when string is a single space" do
    " now's  the time  ".split(' ').should == ["now's", "the", "time"]
    " now's  the time  ".split(' ', -1).should == ["now's", "the", "time", ""]
    " now's  the time  ".split(' ', 3).should == ["now's", "the", "time  "]

    "\t\n a\t\tb \n\r\r\nc\v\vd\v ".split(' ').should == ["a", "b", "c", "d"]
    "a\x00a b".split(' ').should == ["a\x00a", "b"]
  end

  describe "when limit is zero" do
    it "ignores leading and continuous whitespace when string is a single space" do
      " now's  the time  ".split(' ', 0).should == ["now's", "the", "time"]
    end
  end

  it "splits between characters when its argument is an empty string" do
    "hi!".split("").should == ["h", "i", "!"]
    "hi!".split("", -1).should == ["h", "i", "!", ""]
    "hi!".split("", 0).should == ["h", "i", "!"]
    "hi!".split("", 1).should == ["hi!"]
    "hi!".split("", 2).should == ["h", "i!"]
    "hi!".split("", 3).should == ["h", "i", "!"]
    "hi!".split("", 4).should == ["h", "i", "!", ""]
    "hi!".split("", 5).should == ["h", "i", "!", ""]
  end

  it "tries converting its pattern argument to a string via to_str" do
    obj = mock('::')
    obj.should_receive(:to_str).and_return("::")

    "hello::world".split(obj).should == ["hello", "world"]
  end

  it "tries converting limit to an integer via to_int" do
    obj = mock('2')
    obj.should_receive(:to_int).and_return(2)

    "1.2.3.4".split(".", obj).should == ["1", "2.3.4"]
  end

  it "doesn't set $~" do
    $~ = nil
    "x.y.z".split(".")
    $~.should == nil
  end

  it "returns the original string if no matches are found" do
    "foo".split("bar").should == ["foo"]
    "foo".split("bar", -1).should == ["foo"]
    "foo".split("bar", 0).should == ["foo"]
    "foo".split("bar", 1).should == ["foo"]
    "foo".split("bar", 2).should == ["foo"]
    "foo".split("bar", 3).should == ["foo"]
  end

  ruby_version_is ''...'3.0' do
    it "returns subclass instances based on self" do
      ["", "x.y.z.", "  x  y  "].each do |str|
        ["", ".", " "].each do |pat|
          [-1, 0, 1, 2].each do |limit|
            StringSpecs::MyString.new(str).split(pat, limit).each do |x|
              x.should be_an_instance_of(StringSpecs::MyString)
            end

            str.split(StringSpecs::MyString.new(pat), limit).each do |x|
              x.should be_an_instance_of(String)
            end
          end
        end
      end
    end

    it "does not call constructor on created subclass instances" do
      # can't call should_not_receive on an object that doesn't yet exist
      # so failure here is signalled by exception, not expectation failure

      s = StringSpecs::StringWithRaisingConstructor.new('silly:string')
      s.split(':').first.should == 'silly'
    end
  end

  ruby_version_is '3.0' do
    it "returns String instances based on self" do
      ["", "x.y.z.", "  x  y  "].each do |str|
        ["", ".", " "].each do |pat|
          [-1, 0, 1, 2].each do |limit|
            StringSpecs::MyString.new(str).split(pat, limit).each do |x|
              x.should be_an_instance_of(String)
            end

            str.split(StringSpecs::MyString.new(pat), limit).each do |x|
              x.should be_an_instance_of(String)
            end
          end
        end
      end
    end
  end

  it "returns an empty array when whitespace is split on whitespace" do
    " ".split(" ").should == []
    " \n ".split(" ").should == []
    "  ".split(" ").should == []
    " \t ".split(" ").should == []
  end

  it "doesn't split on non-ascii whitespace" do
    "a\u{2008}b".split(" ").should == ["a\u{2008}b"]
  end
end

describe "String#split with Regexp" do
  it "throws an ArgumentError if the string  is not a valid" do
    s = "\xDF".force_encoding(Encoding::UTF_8)

    -> { s.split(/./) }.should raise_error(ArgumentError)
  end

  it "divides self on regexp matches" do
    " now's  the time".split(/ /).should == ["", "now's", "", "the", "time"]
    " x\ny ".split(/ /).should == ["", "x\ny"]
    "1, 2.34,56, 7".split(/,\s*/).should == ["1", "2.34", "56", "7"]
    "1x2X3".split(/x/i).should == ["1", "2", "3"]
  end

  it "treats negative limits as no limit" do
    "".split(%r!/+!, -1).should == []
  end

  it "suppresses trailing empty fields when limit isn't given or 0" do
    "1,2,,3,4,,".split(/,/).should == ["1", "2", "", "3", "4"]
    "1,2,,3,4,,".split(/,/, 0).should == ["1", "2", "", "3", "4"]
    "  a  b  c\nd  ".split(/\s+/).should == ["", "a", "b", "c", "d"]
    "hai".split(/hai/).should == []
    ",".split(/,/).should == []
    ",".split(/,/, 0).should == []
  end

  it "returns an array with one entry if limit is 1: the original string" do
    "hai".split(/hai/, 1).should == ["hai"]
    "xAyBzC".split(/[A-Z]/, 1).should == ["xAyBzC"]
    "hello world ".split(/\s+/, 1).should == ["hello world "]
    "hi!".split(//, 1).should == ["hi!"]
  end

  it "returns at most limit fields when limit > 1" do
    "hai".split(/hai/, 2).should == ["", ""]

    "1,2".split(/,/, 3).should == ["1", "2"]

    "1,2,,3,4,,".split(/,/, 2).should == ["1", "2,,3,4,,"]
    "1,2,,3,4,,".split(/,/, 3).should == ["1", "2", ",3,4,,"]
    "1,2,,3,4,,".split(/,/, 4).should == ["1", "2", "", "3,4,,"]
    "1,2,,3,4,,".split(/,/, 5).should == ["1", "2", "", "3", "4,,"]
    "1,2,,3,4,,".split(/,/, 6).should == ["1", "2", "", "3", "4", ","]

    "x".split(/x/, 2).should == ["", ""]
    "xx".split(/x/, 2).should == ["", "x"]
    "xx".split(/x/, 3).should == ["", "", ""]
    "xxx".split(/x/, 2).should == ["", "xx"]
    "xxx".split(/x/, 3).should == ["", "", "x"]
    "xxx".split(/x/, 4).should == ["", "", "", ""]
  end

  it "doesn't suppress or limit fields when limit is negative" do
    "1,2,,3,4,,".split(/,/, -1).should == ["1", "2", "", "3", "4", "", ""]
    "1,2,,3,4,,".split(/,/, -5).should == ["1", "2", "", "3", "4", "", ""]
    "  a  b  c\nd  ".split(/\s+/, -1).should == ["", "a", "b", "c", "d", ""]
    ",".split(/,/, -1).should == ["", ""]
  end

  it "defaults to $; when regexp isn't given or nil" do
    suppress_warning do
      old_fs = $;
      begin
        [/,/, /:/, //, /XY/, /./].each do |fs|
          $; = fs

          ["x,y,z,,,", "1:2:", "aXYbXYcXY", ""].each do |str|
            expected = str.split(fs)

            str.split(nil).should == expected
            str.split.should == expected

            str.split(nil, -1).should == str.split(fs, -1)
            str.split(nil, 0).should == str.split(fs, 0)
            str.split(nil, 2).should == str.split(fs, 2)
          end
        end
      ensure
        $; = old_fs
      end
    end
  end

  it "splits between characters when regexp matches a zero-length string" do
    "hello".split(//).should == ["h", "e", "l", "l", "o"]
    "hello".split(//, -1).should == ["h", "e", "l", "l", "o", ""]
    "hello".split(//, 0).should == ["h", "e", "l", "l", "o"]
    "hello".split(//, 1).should == ["hello"]
    "hello".split(//, 2).should == ["h", "ello"]
    "hello".split(//, 5).should == ["h", "e", "l", "l", "o"]
    "hello".split(//, 6).should == ["h", "e", "l", "l", "o", ""]
    "hello".split(//, 7).should == ["h", "e", "l", "l", "o", ""]

    "hi mom".split(/\s*/).should == ["h", "i", "m", "o", "m"]

    "AABCCBAA".split(/(?=B)/).should == ["AA", "BCC", "BAA"]
    "AABCCBAA".split(/(?=B)/, -1).should == ["AA", "BCC", "BAA"]
    "AABCCBAA".split(/(?=B)/, 2).should == ["AA", "BCCBAA"]
  end

  it "respects unicode when splitting between characters" do
    str = "こにちわ"
    reg = %r!!
    ary = str.split(reg)
    ary.size.should == 4
    ary.should == ["こ", "に", "ち", "わ"]
  end

  it "respects the encoding of the regexp when splitting between characters" do
    str = "\303\202"
    ary = str.split(//u)
    ary.size.should == 1
    ary.should == ["\303\202"]
  end

  it "includes all captures in the result array" do
    "hello".split(/(el)/).should == ["h", "el", "lo"]
    "hi!".split(/()/).should == ["h", "", "i", "", "!"]
    "hi!".split(/()/, -1).should == ["h", "", "i", "", "!", "", ""]
    "hello".split(/((el))()/).should == ["h", "el", "el", "", "lo"]
    "AabB".split(/([a-z])+/).should == ["A", "b", "B"]
  end

  it "applies the limit to the number of split substrings, without counting captures" do
    "aBaBa".split(/(B)()()/, 2).should == ["a", "B", "", "", "aBa"]
  end

  it "does not include non-matching captures in the result array" do
    "hello".split(/(el)|(xx)/).should == ["h", "el", "lo"]
  end

  it "tries converting limit to an integer via to_int" do
    obj = mock('2')
    obj.should_receive(:to_int).and_return(2)

    "1.2.3.4".split(".", obj).should == ["1", "2.3.4"]
  end

  it "returns a type error if limit can't be converted to an integer" do
    -> {"1.2.3.4".split(".", "three")}.should raise_error(TypeError)
    -> {"1.2.3.4".split(".", nil)    }.should raise_error(TypeError)
  end

  it "doesn't set $~" do
    $~ = nil
    "x:y:z".split(/:/)
    $~.should == nil
  end

  it "returns the original string if no matches are found" do
    "foo".split(/bar/).should == ["foo"]
    "foo".split(/bar/, -1).should == ["foo"]
    "foo".split(/bar/, 0).should == ["foo"]
    "foo".split(/bar/, 1).should == ["foo"]
    "foo".split(/bar/, 2).should == ["foo"]
    "foo".split(/bar/, 3).should == ["foo"]
  end

  ruby_version_is ''...'3.0' do
    it "returns subclass instances based on self" do
      ["", "x:y:z:", "  x  y  "].each do |str|
        [//, /:/, /\s+/].each do |pat|
          [-1, 0, 1, 2].each do |limit|
            StringSpecs::MyString.new(str).split(pat, limit).each do |x|
              x.should be_an_instance_of(StringSpecs::MyString)
            end
          end
        end
      end
    end

    it "does not call constructor on created subclass instances" do
      # can't call should_not_receive on an object that doesn't yet exist
      # so failure here is signalled by exception, not expectation failure

      s = StringSpecs::StringWithRaisingConstructor.new('silly:string')
      s.split(/:/).first.should == 'silly'
    end
  end

  ruby_version_is '3.0' do
    it "returns String instances based on self" do
      ["", "x:y:z:", "  x  y  "].each do |str|
        [//, /:/, /\s+/].each do |pat|
          [-1, 0, 1, 2].each do |limit|
            StringSpecs::MyString.new(str).split(pat, limit).each do |x|
              x.should be_an_instance_of(String)
            end
          end
        end
      end
    end
  end

  it "retains the encoding of the source string" do
    ary = "а б в".split
    encodings = ary.map { |s| s.encoding }
    encodings.should == [Encoding::UTF_8, Encoding::UTF_8, Encoding::UTF_8]
  end


  it "splits a string on each character for a multibyte encoding and empty split" do
    "That's why eﬃciency could not be helped".split("").size.should == 39
  end

  it "returns an ArgumentError if an invalid UTF-8 string is supplied" do
    broken_str = 'проверка' # in russian, means "test"
    broken_str.force_encoding('binary')
    broken_str.chop!
    broken_str.force_encoding('utf-8')
    ->{ broken_str.split(/\r\n|\r|\n/) }.should raise_error(ArgumentError)
  end

  # See https://bugs.ruby-lang.org/issues/12689 and https://github.com/jruby/jruby/issues/4868
  it "allows concurrent Regexp calls in a shared context" do
    str = 'a,b,c,d,e'

    p = proc { str.split(/,/) }
    results = 10.times.map { Thread.new { x = nil; 100.times { x = p.call }; x } }.map(&:value)

    results.should == [%w[a b c d e]] * 10
  end

  context "when a block is given" do
    it "yields each split substring with default pattern" do
      a = []
      returned_object = "chunky bacon".split { |str| a << str.capitalize }

      returned_object.should == "chunky bacon"
      a.should == ["Chunky", "Bacon"]
    end

    it "yields each split substring with default pattern for a non-ASCII string" do
      a = []
      returned_object = "l'été arrive bientôt".split { |str| a << str }

      returned_object.should == "l'été arrive bientôt"
      a.should == ["l'été", "arrive", "bientôt"]
    end

    it "yields the string when limit is 1" do
      a = []
      returned_object = "chunky bacon".split("", 1) { |str| a << str.capitalize }

      returned_object.should == "chunky bacon"
      a.should == ["Chunky bacon"]
    end

    it "yields each split letter" do
      a = []
      returned_object = "chunky".split("", 0) { |str| a << str.capitalize }

      returned_object.should == "chunky"
      a.should == %w(C H U N K Y)
    end

    it "yields each split substring with a pattern" do
      a = []
      returned_object = "chunky-bacon".split("-", 0) { |str| a << str.capitalize }

      returned_object.should == "chunky-bacon"
      a.should == ["Chunky", "Bacon"]
    end

    it "yields each split substring with empty regexp pattern" do
      a = []
      returned_object = "chunky".split(//) { |str| a << str.capitalize }

      returned_object.should == "chunky"
      a.should == %w(C H U N K Y)
    end

    it "yields each split substring with empty regexp pattern and limit" do
      a = []
      returned_object = "chunky".split(//, 3) { |str| a << str.capitalize }

      returned_object.should == "chunky"
      a.should == %w(C H Unky)
    end

    it "yields each split substring with a regexp pattern" do
      a = []
      returned_object = "chunky:bacon".split(/:/) { |str| a << str.capitalize }

      returned_object.should == "chunky:bacon"
      a.should == ["Chunky", "Bacon"]
    end

    it "returns a string as is (and doesn't call block) if it is empty" do
      a = []
      returned_object = "".split { |str| a << str.capitalize }

      returned_object.should == ""
      a.should == []
    end
  end

  describe "for a String subclass" do
    ruby_version_is ''...'3.0' do
      it "yields instances of the same subclass" do
        a = []
        StringSpecs::MyString.new("a|b").split("|") { |str| a << str }
        first, last = a

        first.should be_an_instance_of(StringSpecs::MyString)
        first.should == "a"

        last.should be_an_instance_of(StringSpecs::MyString)
        last.should == "b"
      end
    end

    ruby_version_is '3.0' do
      it "yields instances of String" do
        a = []
        StringSpecs::MyString.new("a|b").split("|") { |str| a << str }
        first, last = a

        first.should be_an_instance_of(String)
        first.should == "a"

        last.should be_an_instance_of(String)
        last.should == "b"
      end
    end
  end

  it "raises a TypeError when not called with nil, String, or Regexp" do
    -> { "hello".split(42) }.should raise_error(TypeError)
    -> { "hello".split(:ll) }.should raise_error(TypeError)
    -> { "hello".split(false) }.should raise_error(TypeError)
    -> { "hello".split(Object.new) }.should raise_error(TypeError)
  end
end
