# -*- encoding: utf-8 -*-
require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/byte_index_common.rb'

describe "String#byteindex" do
  ruby_version_is "3.2" do
    it "calls #to_str to convert the first argument" do
      char = mock("string index char")
      char.should_receive(:to_str).and_return("b")
      "abc".byteindex(char).should == 1
    end

    it "calls #to_int to convert the second argument" do
      offset = mock("string index offset")
      offset.should_receive(:to_int).and_return(1)
      "abc".byteindex("c", offset).should == 2
    end

    it "does not raise IndexError when byte offset is correct or on string boundary" do
      "わ".byteindex("").should == 0
      "わ".byteindex("", 0).should == 0
      "わ".byteindex("", 3).should == 3
    end

    it_behaves_like :byte_index_common, :byteindex
  end
end

describe "String#byteindex with String" do
  ruby_version_is "3.2" do
    it "behaves the same as String#byteindex(char) for one-character strings" do
      "blablabla hello cruel world...!".split("").uniq.each do |str|
        chr = str[0]
        str.byteindex(str).should == str.byteindex(chr)

        0.upto(str.size + 1) do |start|
          str.byteindex(str, start).should == str.byteindex(chr, start)
        end

        (-str.size - 1).upto(-1) do |start|
          str.byteindex(str, start).should == str.byteindex(chr, start)
        end
      end
    end

    it "returns the byteindex of the first occurrence of the given substring" do
      "blablabla".byteindex("").should == 0
      "blablabla".byteindex("b").should == 0
      "blablabla".byteindex("bla").should == 0
      "blablabla".byteindex("blabla").should == 0
      "blablabla".byteindex("blablabla").should == 0

      "blablabla".byteindex("l").should == 1
      "blablabla".byteindex("la").should == 1
      "blablabla".byteindex("labla").should == 1
      "blablabla".byteindex("lablabla").should == 1

      "blablabla".byteindex("a").should == 2
      "blablabla".byteindex("abla").should == 2
      "blablabla".byteindex("ablabla").should == 2
    end

    it "treats the offset as a byteindex" do
      "aaaaa".byteindex("a", 0).should == 0
      "aaaaa".byteindex("a", 2).should == 2
      "aaaaa".byteindex("a", 4).should == 4
    end

    it "ignores string subclasses" do
      "blablabla".byteindex(StringSpecs::MyString.new("bla")).should == 0
      StringSpecs::MyString.new("blablabla").byteindex("bla").should == 0
      StringSpecs::MyString.new("blablabla").byteindex(StringSpecs::MyString.new("bla")).should == 0
    end

    it "starts the search at the given offset" do
      "blablabla".byteindex("bl", 0).should == 0
      "blablabla".byteindex("bl", 1).should == 3
      "blablabla".byteindex("bl", 2).should == 3
      "blablabla".byteindex("bl", 3).should == 3

      "blablabla".byteindex("bla", 0).should == 0
      "blablabla".byteindex("bla", 1).should == 3
      "blablabla".byteindex("bla", 2).should == 3
      "blablabla".byteindex("bla", 3).should == 3

      "blablabla".byteindex("blab", 0).should == 0
      "blablabla".byteindex("blab", 1).should == 3
      "blablabla".byteindex("blab", 2).should == 3
      "blablabla".byteindex("blab", 3).should == 3

      "blablabla".byteindex("la", 1).should == 1
      "blablabla".byteindex("la", 2).should == 4
      "blablabla".byteindex("la", 3).should == 4
      "blablabla".byteindex("la", 4).should == 4

      "blablabla".byteindex("lab", 1).should == 1
      "blablabla".byteindex("lab", 2).should == 4
      "blablabla".byteindex("lab", 3).should == 4
      "blablabla".byteindex("lab", 4).should == 4

      "blablabla".byteindex("ab", 2).should == 2
      "blablabla".byteindex("ab", 3).should == 5
      "blablabla".byteindex("ab", 4).should == 5
      "blablabla".byteindex("ab", 5).should == 5

      "blablabla".byteindex("", 0).should == 0
      "blablabla".byteindex("", 1).should == 1
      "blablabla".byteindex("", 2).should == 2
      "blablabla".byteindex("", 7).should == 7
      "blablabla".byteindex("", 8).should == 8
      "blablabla".byteindex("", 9).should == 9
    end

    it "starts the search at offset + self.length if offset is negative" do
      str = "blablabla"

      ["bl", "bla", "blab", "la", "lab", "ab", ""].each do |needle|
        (-str.length .. -1).each do |offset|
          str.byteindex(needle, offset).should ==
          str.byteindex(needle, offset + str.length)
        end
      end
    end

    it "returns nil if the substring isn't found" do
      "blablabla".byteindex("B").should == nil
      "blablabla".byteindex("z").should == nil
      "blablabla".byteindex("BLA").should == nil
      "blablabla".byteindex("blablablabla").should == nil
      "blablabla".byteindex("", 10).should == nil

      "hello".byteindex("he", 1).should == nil
      "hello".byteindex("he", 2).should == nil
      "I’ve got a multibyte character.\n".byteindex("\n\n").should == nil
    end

    it "returns the character byteindex of a multibyte character" do
      "ありがとう".byteindex("が").should == 6
    end

    it "returns the character byteindex after offset" do
      "われわれ".byteindex("わ", 3).should == 6
      "ありがとうありがとう".byteindex("が", 9).should == 21
    end

    it "returns the character byteindex after a partial first match" do
      "</</h".byteindex("</h").should == 2
    end

    it "raises an Encoding::CompatibilityError if the encodings are incompatible" do
      char = "れ".encode Encoding::EUC_JP
      -> do
        "あれ".byteindex(char)
      end.should raise_error(Encoding::CompatibilityError)
    end

    it "handles a substring in a superset encoding" do
      'abc'.force_encoding(Encoding::US_ASCII).byteindex('é').should == nil
    end

    it "handles a substring in a subset encoding" do
      'été'.byteindex('t'.force_encoding(Encoding::US_ASCII)).should == 2
    end
  end
end

describe "String#byteindex with Regexp" do
  ruby_version_is "3.2" do
    it "behaves the same as String#byteindex(string) for escaped string regexps" do
      ["blablabla", "hello cruel world...!"].each do |str|
        ["", "b", "bla", "lab", "o c", "d."].each do |needle|
          regexp = Regexp.new(Regexp.escape(needle))
          str.byteindex(regexp).should == str.byteindex(needle)

          0.upto(str.size + 1) do |start|
            str.byteindex(regexp, start).should == str.byteindex(needle, start)
          end

          (-str.size - 1).upto(-1) do |start|
            str.byteindex(regexp, start).should == str.byteindex(needle, start)
          end
        end
      end
    end

    it "returns the byteindex of the first match of regexp" do
      "blablabla".byteindex(/bla/).should == 0
      "blablabla".byteindex(/BLA/i).should == 0

      "blablabla".byteindex(/.{0}/).should == 0
      "blablabla".byteindex(/.{6}/).should == 0
      "blablabla".byteindex(/.{9}/).should == 0

      "blablabla".byteindex(/.*/).should == 0
      "blablabla".byteindex(/.+/).should == 0

      "blablabla".byteindex(/lab|b/).should == 0

      not_supported_on :opal do
        "blablabla".byteindex(/\A/).should == 0
        "blablabla".byteindex(/\Z/).should == 9
        "blablabla".byteindex(/\z/).should == 9
        "blablabla\n".byteindex(/\Z/).should == 9
        "blablabla\n".byteindex(/\z/).should == 10
      end

      "blablabla".byteindex(/^/).should == 0
      "\nblablabla".byteindex(/^/).should == 0
      "b\nablabla".byteindex(/$/).should == 1
      "bl\nablabla".byteindex(/$/).should == 2

      "blablabla".byteindex(/.l./).should == 0
    end

    it "starts the search at the given offset" do
      "blablabla".byteindex(/.{0}/, 5).should == 5
      "blablabla".byteindex(/.{1}/, 5).should == 5
      "blablabla".byteindex(/.{2}/, 5).should == 5
      "blablabla".byteindex(/.{3}/, 5).should == 5
      "blablabla".byteindex(/.{4}/, 5).should == 5

      "blablabla".byteindex(/.{0}/, 3).should == 3
      "blablabla".byteindex(/.{1}/, 3).should == 3
      "blablabla".byteindex(/.{2}/, 3).should == 3
      "blablabla".byteindex(/.{5}/, 3).should == 3
      "blablabla".byteindex(/.{6}/, 3).should == 3

      "blablabla".byteindex(/.l./, 0).should == 0
      "blablabla".byteindex(/.l./, 1).should == 3
      "blablabla".byteindex(/.l./, 2).should == 3
      "blablabla".byteindex(/.l./, 3).should == 3

      "xblaxbla".byteindex(/x./, 0).should == 0
      "xblaxbla".byteindex(/x./, 1).should == 4
      "xblaxbla".byteindex(/x./, 2).should == 4

      not_supported_on :opal do
        "blablabla\n".byteindex(/\Z/, 9).should == 9
      end
    end

    it "starts the search at offset + self.length if offset is negative" do
      str = "blablabla"

      ["bl", "bla", "blab", "la", "lab", "ab", ""].each do |needle|
        (-str.length .. -1).each do |offset|
          str.byteindex(needle, offset).should ==
          str.byteindex(needle, offset + str.length)
        end
      end
    end

    it "returns nil if the substring isn't found" do
      "blablabla".byteindex(/BLA/).should == nil

      "blablabla".byteindex(/.{10}/).should == nil
      "blaxbla".byteindex(/.x/, 3).should == nil
      "blaxbla".byteindex(/..x/, 2).should == nil
    end

    it "returns nil if the Regexp matches the empty string and the offset is out of range" do
      "ruby".byteindex(//, 12).should be_nil
    end

    it "supports \\G which matches at the given start offset" do
      "helloYOU.".byteindex(/\GYOU/, 5).should == 5
      "helloYOU.".byteindex(/\GYOU/).should == nil

      re = /\G.+YOU/
      # The # marks where \G will match.
      [
        ["#hi!YOUall.", 0],
        ["h#i!YOUall.", 1],
        ["hi#!YOUall.", 2],
        ["hi!#YOUall.", nil]
      ].each do |spec|

        start = spec[0].byteindex("#")
        str = spec[0].delete("#")

        str.byteindex(re, start).should == spec[1]
      end
    end

    it "converts start_offset to an integer via to_int" do
      obj = mock('1')
      obj.should_receive(:to_int).and_return(1)
      "RWOARW".byteindex(/R./, obj).should == 4
    end

    it "returns the character byteindex of a multibyte character" do
      "ありがとう".byteindex(/が/).should == 6
    end

    it "returns the character byteindex after offset" do
      "われわれ".byteindex(/わ/, 3).should == 6
    end

    it "treats the offset as a byteindex" do
      "われわわれ".byteindex(/わ/, 6).should == 6
    end
  end
end
