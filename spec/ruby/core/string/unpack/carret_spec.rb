# encoding: binary
ruby_version_is "4.1" do
  require_relative '../../../spec_helper'
  require_relative '../fixtures/classes'
  require_relative 'shared/basic'

  describe "String#unpack with format '^'" do
    it_behaves_like :string_unpack_basic, '^'
    it_behaves_like :string_unpack_no_platform, '^'

    it "returns the current offset that start from 0" do
      "".unpack("^").should == [0]
    end

    it "returns the current offset after the last decode ended" do
      "a".unpack("CC^").should == [97, nil, 1]
    end

    it "returns the current offset that start from the given offset" do
      "abc".unpack("^", offset: 1).should == [1]
    end

    it "returns the offset moved by 'X'" do
      "\x01\x02\x03\x04".unpack("C3X2^").should == [1, 2, 3, 1]
    end

    it "returns the offset moved by 'x'" do
      "\x01\x02\x03\x04".unpack("Cx2^").should == [1, 3]
    end

    it "returns the offset to the position the previous decode ended" do
      "foo".unpack("A4^").should == ["foo", 3]
      "foo".unpack("a4^").should == ["foo", 3]
      "foo".unpack("Z5^").should == ["foo", 3]
    end

    it "returns the offset including truncated part" do
      "foo   ".unpack("A*^").should == ["foo", 6]
      "foo\0".unpack("Z*^").should == ["foo", 4]
      "foo\0\0\0".unpack("Z5^").should == ["foo", 5]
    end
  end
end
