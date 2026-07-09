# encoding: binary
require_relative '../../spec_helper'
require_relative 'shared/codepoints'

describe "String#each_codepoint" do
  it_behaves_like :string_codepoints, :each_codepoint

  describe "when no block is given" do
    it "returns an Enumerator" do
      "".each_codepoint.should.instance_of?(Enumerator)
    end

    it "returns an Enumerator even when self has an invalid encoding" do
      s = "\xDF".dup.force_encoding(Encoding::UTF_8)
      s.valid_encoding?.should == false
      s.each_codepoint.should.instance_of?(Enumerator)
    end

    describe "returned Enumerator" do
      describe "size" do
        it "should return the size of the string" do
          str = "hello"
          str.each_codepoint.size.should == str.size
          str = "ola"
          str.each_codepoint.size.should == str.size
          str = "\303\207\342\210\202\303\251\306\222g"
          str.each_codepoint.size.should == str.size
        end

        it "should return the size of the string even when the string has an invalid encoding" do
          s = "\xDF".dup.force_encoding(Encoding::UTF_8)
          s.valid_encoding?.should == false
          s.each_codepoint.size.should == 1
        end
      end
    end
  end
end
