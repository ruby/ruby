# -*- encoding: binary -*-
require_relative '../../spec_helper'
require_relative 'shared/codepoints'
require_relative 'shared/each_codepoint_without_block'

with_feature :encoding do
  describe "String#codepoints" do
    it_behaves_like :string_codepoints, :codepoints

    it "returns an Array when no block is given" do
      "abc".send(@method).should == [?a.ord, ?b.ord, ?c.ord]
    end

    it "raises an ArgumentError when no block is given if self has an invalid encoding" do
      s = "\xDF".force_encoding(Encoding::UTF_8)
      s.valid_encoding?.should be_false
      lambda {s.send(@method)}.should raise_error(ArgumentError)
    end
  end
end
