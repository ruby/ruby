# -*- encoding: utf-8 -*-
require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/byte_index_common.rb'

describe "String#byterindex with object" do
  ruby_version_is "3.2" do
    it "tries to convert obj to a string via to_str" do
      obj = mock('lo')
      def obj.to_str() "lo" end
      "hello".byterindex(obj).should == "hello".byterindex("lo")

      obj = mock('o')
      def obj.respond_to?(arg, *) true end
      def obj.method_missing(*args) "o" end
      "hello".byterindex(obj).should == "hello".byterindex("o")
    end

    it "calls #to_int to convert the second argument" do
      offset = mock("string index offset")
      offset.should_receive(:to_int).and_return(3)
      "abc".byterindex("c", offset).should == 2
    end

    it "does not raise IndexError when byte offset is correct or on string boundary" do
      "わ".byterindex("", 0).should == 0
      "わ".byterindex("", 3).should == 3
      "わ".byterindex("").should == 3
    end

    it_behaves_like :byte_index_common, :byterindex
  end
end

describe "String#byterindex with String" do
  ruby_version_is "3.2" do
    it "behaves the same as String#byterindex(char) for one-character strings" do
      "blablabla hello cruel world...!".split("").uniq.each do |str|
        chr = str[0]
        str.byterindex(str).should == str.byterindex(chr)

        0.upto(str.size + 1) do |start|
          str.byterindex(str, start).should == str.byterindex(chr, start)
        end

        (-str.size - 1).upto(-1) do |start|
          str.byterindex(str, start).should == str.byterindex(chr, start)
        end
      end
    end

    it "behaves the same as String#byterindex(?char) for one-character strings" do
      "blablabla hello cruel world...!".split("").uniq.each do |str|
        chr = str[0] =~ / / ? str[0] : eval("?#{str[0]}")
        str.byterindex(str).should == str.byterindex(chr)

        0.upto(str.size + 1) do |start|
          str.byterindex(str, start).should == str.byterindex(chr, start)
        end

        (-str.size - 1).upto(-1) do |start|
          str.byterindex(str, start).should == str.byterindex(chr, start)
        end
      end
    end

    it "returns the index of the last occurrence of the given substring" do
      "blablabla".byterindex("").should == 9
      "blablabla".byterindex("a").should == 8
      "blablabla".byterindex("la").should == 7
      "blablabla".byterindex("bla").should == 6
      "blablabla".byterindex("abla").should == 5
      "blablabla".byterindex("labla").should == 4
      "blablabla".byterindex("blabla").should == 3
      "blablabla".byterindex("ablabla").should == 2
      "blablabla".byterindex("lablabla").should == 1
      "blablabla".byterindex("blablabla").should == 0

      "blablabla".byterindex("l").should == 7
      "blablabla".byterindex("bl").should == 6
      "blablabla".byterindex("abl").should == 5
      "blablabla".byterindex("labl").should == 4
      "blablabla".byterindex("blabl").should == 3
      "blablabla".byterindex("ablabl").should == 2
      "blablabla".byterindex("lablabl").should == 1
      "blablabla".byterindex("blablabl").should == 0

      "blablabla".byterindex("b").should == 6
      "blablabla".byterindex("ab").should == 5
      "blablabla".byterindex("lab").should == 4
      "blablabla".byterindex("blab").should == 3
      "blablabla".byterindex("ablab").should == 2
      "blablabla".byterindex("lablab").should == 1
      "blablabla".byterindex("blablab").should == 0
    end

    it "ignores string subclasses" do
      "blablabla".byterindex(StringSpecs::MyString.new("bla")).should == 6
      StringSpecs::MyString.new("blablabla").byterindex("bla").should == 6
      StringSpecs::MyString.new("blablabla").byterindex(StringSpecs::MyString.new("bla")).should == 6
    end

    it "starts the search at the given offset" do
      "blablabla".byterindex("bl", 0).should == 0
      "blablabla".byterindex("bl", 1).should == 0
      "blablabla".byterindex("bl", 2).should == 0
      "blablabla".byterindex("bl", 3).should == 3

      "blablabla".byterindex("bla", 0).should == 0
      "blablabla".byterindex("bla", 1).should == 0
      "blablabla".byterindex("bla", 2).should == 0
      "blablabla".byterindex("bla", 3).should == 3

      "blablabla".byterindex("blab", 0).should == 0
      "blablabla".byterindex("blab", 1).should == 0
      "blablabla".byterindex("blab", 2).should == 0
      "blablabla".byterindex("blab", 3).should == 3
      "blablabla".byterindex("blab", 6).should == 3
      "blablablax".byterindex("blab", 6).should == 3

      "blablabla".byterindex("la", 1).should == 1
      "blablabla".byterindex("la", 2).should == 1
      "blablabla".byterindex("la", 3).should == 1
      "blablabla".byterindex("la", 4).should == 4

      "blablabla".byterindex("lab", 1).should == 1
      "blablabla".byterindex("lab", 2).should == 1
      "blablabla".byterindex("lab", 3).should == 1
      "blablabla".byterindex("lab", 4).should == 4

      "blablabla".byterindex("ab", 2).should == 2
      "blablabla".byterindex("ab", 3).should == 2
      "blablabla".byterindex("ab", 4).should == 2
      "blablabla".byterindex("ab", 5).should == 5

      "blablabla".byterindex("", 0).should == 0
      "blablabla".byterindex("", 1).should == 1
      "blablabla".byterindex("", 2).should == 2
      "blablabla".byterindex("", 7).should == 7
      "blablabla".byterindex("", 8).should == 8
      "blablabla".byterindex("", 9).should == 9
      "blablabla".byterindex("", 10).should == 9
    end

    it "starts the search at offset + self.length if offset is negative" do
      str = "blablabla"

      ["bl", "bla", "blab", "la", "lab", "ab", ""].each do |needle|
        (-str.length .. -1).each do |offset|
          str.byterindex(needle, offset).should ==
          str.byterindex(needle, offset + str.length)
        end
      end
    end

    it "returns nil if the substring isn't found" do
      "blablabla".byterindex("B").should == nil
      "blablabla".byterindex("z").should == nil
      "blablabla".byterindex("BLA").should == nil
      "blablabla".byterindex("blablablabla").should == nil

      "hello".byterindex("lo", 0).should == nil
      "hello".byterindex("lo", 1).should == nil
      "hello".byterindex("lo", 2).should == nil

      "hello".byterindex("llo", 0).should == nil
      "hello".byterindex("llo", 1).should == nil

      "hello".byterindex("el", 0).should == nil
      "hello".byterindex("ello", 0).should == nil

      "hello".byterindex("", -6).should == nil
      "hello".byterindex("", -7).should == nil

      "hello".byterindex("h", -6).should == nil
    end

    it "tries to convert start_offset to an integer via to_int" do
      obj = mock('5')
      def obj.to_int() 5 end
      "str".byterindex("st", obj).should == 0

      obj = mock('5')
      def obj.respond_to?(arg, *) true end
      def obj.method_missing(*args) 5 end
      "str".byterindex("st", obj).should == 0
    end

    it "raises a TypeError when given offset is nil" do
      -> { "str".byterindex("st", nil) }.should raise_error(TypeError)
    end

    it "handles a substring in a superset encoding" do
      'abc'.force_encoding(Encoding::US_ASCII).byterindex('é').should == nil
    end

    it "handles a substring in a subset encoding" do
      'été'.byterindex('t'.force_encoding(Encoding::US_ASCII)).should == 2
    end
  end
end

describe "String#byterindex with Regexp" do
  ruby_version_is "3.2" do
    it "behaves the same as String#byterindex(string) for escaped string regexps" do
      ["blablabla", "hello cruel world...!"].each do |str|
        ["", "b", "bla", "lab", "o c", "d."].each do |needle|
          regexp = Regexp.new(Regexp.escape(needle))
          str.byterindex(regexp).should == str.byterindex(needle)

          0.upto(str.size + 1) do |start|
            str.byterindex(regexp, start).should == str.byterindex(needle, start)
          end

          (-str.size - 1).upto(-1) do |start|
            str.byterindex(regexp, start).should == str.byterindex(needle, start)
          end
        end
      end
    end

    it "returns the index of the first match from the end of string of regexp" do
      "blablabla".byterindex(/bla/).should == 6
      "blablabla".byterindex(/BLA/i).should == 6

      "blablabla".byterindex(/.{0}/).should == 9
      "blablabla".byterindex(/.{1}/).should == 8
      "blablabla".byterindex(/.{2}/).should == 7
      "blablabla".byterindex(/.{6}/).should == 3
      "blablabla".byterindex(/.{9}/).should == 0

      "blablabla".byterindex(/.*/).should == 9
      "blablabla".byterindex(/.+/).should == 8

      "blablabla".byterindex(/bla|a/).should == 8

      not_supported_on :opal do
        "blablabla".byterindex(/\A/).should == 0
        "blablabla".byterindex(/\Z/).should == 9
        "blablabla".byterindex(/\z/).should == 9
        "blablabla\n".byterindex(/\Z/).should == 10
        "blablabla\n".byterindex(/\z/).should == 10
      end

      "blablabla".byterindex(/^/).should == 0
      not_supported_on :opal do
        "\nblablabla".byterindex(/^/).should == 1
        "b\nlablabla".byterindex(/^/).should == 2
      end
      "blablabla".byterindex(/$/).should == 9

      "blablabla".byterindex(/.l./).should == 6
    end

    it "starts the search at the given offset" do
      "blablabla".byterindex(/.{0}/, 5).should == 5
      "blablabla".byterindex(/.{1}/, 5).should == 5
      "blablabla".byterindex(/.{2}/, 5).should == 5
      "blablabla".byterindex(/.{3}/, 5).should == 5
      "blablabla".byterindex(/.{4}/, 5).should == 5

      "blablabla".byterindex(/.{0}/, 3).should == 3
      "blablabla".byterindex(/.{1}/, 3).should == 3
      "blablabla".byterindex(/.{2}/, 3).should == 3
      "blablabla".byterindex(/.{5}/, 3).should == 3
      "blablabla".byterindex(/.{6}/, 3).should == 3

      "blablabla".byterindex(/.l./, 0).should == 0
      "blablabla".byterindex(/.l./, 1).should == 0
      "blablabla".byterindex(/.l./, 2).should == 0
      "blablabla".byterindex(/.l./, 3).should == 3

      "blablablax".byterindex(/.x/, 10).should == 8
      "blablablax".byterindex(/.x/, 9).should == 8
      "blablablax".byterindex(/.x/, 8).should == 8

      "blablablax".byterindex(/..x/, 10).should == 7
      "blablablax".byterindex(/..x/, 9).should == 7
      "blablablax".byterindex(/..x/, 8).should == 7
      "blablablax".byterindex(/..x/, 7).should == 7

      not_supported_on :opal do
        "blablabla\n".byterindex(/\Z/, 9).should == 9
      end
    end

    it "starts the search at offset + self.length if offset is negative" do
      str = "blablabla"

      ["bl", "bla", "blab", "la", "lab", "ab", ""].each do |needle|
        (-str.length .. -1).each do |offset|
          str.byterindex(needle, offset).should ==
          str.byterindex(needle, offset + str.length)
        end
      end
    end

    it "returns nil if the substring isn't found" do
      "blablabla".byterindex(/BLA/).should == nil
      "blablabla".byterindex(/.{10}/).should == nil
      "blablablax".byterindex(/.x/, 7).should == nil
      "blablablax".byterindex(/..x/, 6).should == nil

      not_supported_on :opal do
        "blablabla".byterindex(/\Z/, 5).should == nil
        "blablabla".byterindex(/\z/, 5).should == nil
        "blablabla\n".byterindex(/\z/, 9).should == nil
      end
    end

    not_supported_on :opal do
      it "supports \\G which matches at the given start offset" do
        "helloYOU.".byterindex(/YOU\G/, 8).should == 5
        "helloYOU.".byterindex(/YOU\G/).should == nil

        idx = "helloYOUall!".index("YOU")
        re = /YOU.+\G.+/
        # The # marks where \G will match.
        [
          ["helloYOU#all.", nil],
          ["helloYOUa#ll.", idx],
          ["helloYOUal#l.", idx],
          ["helloYOUall#.", idx],
          ["helloYOUall.#", nil]
        ].each do |i|
          start = i[0].index("#")
          str = i[0].delete("#")

          str.byterindex(re, start).should == i[1]
        end
      end
    end

    it "tries to convert start_offset to an integer" do
      obj = mock('5')
      def obj.to_int() 5 end
      "str".byterindex(/../, obj).should == 1

      obj = mock('5')
      def obj.respond_to?(arg, *) true end
      def obj.method_missing(*args); 5; end
      "str".byterindex(/../, obj).should == 1
    end

    it "raises a TypeError when given offset is nil" do
      -> { "str".byterindex(/../, nil) }.should raise_error(TypeError)
    end

    it "returns the reverse byte index of a multibyte character" do
      "ありがりがとう".byterindex("が").should == 12
      "ありがりがとう".byterindex(/が/).should == 12
    end

    it "returns the character index before the finish" do
       "ありがりがとう".byterindex("が", 9).should == 6
       "ありがりがとう".byterindex(/が/, 9).should == 6
    end
  end
end
