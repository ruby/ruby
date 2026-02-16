# encoding: binary
require_relative '../../../spec_helper'
require_relative '../fixtures/classes'
require_relative 'shared/basic'
require_relative 'shared/numeric_basic'
require_relative 'shared/integer'

ruby_version_is "4.1" do
  describe "Array#pack with format 'R'" do
    it_behaves_like :array_pack_basic, 'R'
    it_behaves_like :array_pack_basic_non_float, 'R'
    it_behaves_like :array_pack_arguments, 'R'
    it_behaves_like :array_pack_numeric_basic, 'R'
    it_behaves_like :array_pack_integer, 'R'

    it "encodes a ULEB128 integer" do
      [ [[0],            "\x00"],
        [[1],            "\x01"],
        [[127],          "\x7f"],
        [[128],          "\x80\x01"],
        [[0x3fff],       "\xff\x7f"],
        [[0x4000],       "\x80\x80\x01"],
        [[0xffffffff],   "\xff\xff\xff\xff\x0f"],
        [[0x100000000],  "\x80\x80\x80\x80\x10"],
        [[0xffff_ffff_ffff_ffff], "\xff\xff\xff\xff\xff\xff\xff\xff\xff\x01"],
        [[0xffff_ffff_ffff_ffff_ffff_ffff], "\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\x1f"],
      ].should be_computed_by(:pack, "R")
    end

    it "encodes multiple values with '*' modifier" do
      [1, 2].pack("R*").should == "\x01\x02"
      [127, 128].pack("R*").should == "\x7f\x80\x01"
    end

    it "raises an ArgumentError when passed a negative value" do
      -> { [-1].pack("R") }.should raise_error(ArgumentError)
      -> { [-100].pack("R") }.should raise_error(ArgumentError)
    end

    it "round-trips values through pack and unpack" do
      values = [0, 1, 127, 128, 0x3fff, 0x4000, 0xffffffff, 0x100000000]
      values.pack("R*").unpack("R*").should == values
    end
  end

  describe "Array#pack with format 'r'" do
    it_behaves_like :array_pack_basic, 'r'
    it_behaves_like :array_pack_basic_non_float, 'r'
    it_behaves_like :array_pack_arguments, 'r'
    it_behaves_like :array_pack_numeric_basic, 'r'
    it_behaves_like :array_pack_integer, 'r'

    it "encodes a SLEB128 integer" do
      [ [[0],     "\x00"],
        [[1],     "\x01"],
        [[-1],    "\x7f"],
        [[-2],    "\x7e"],
        [[127],   "\xff\x00"],
        [[128],   "\x80\x01"],
        [[-127],  "\x81\x7f"],
        [[-128],  "\x80\x7f"],
      ].should be_computed_by(:pack, "r")
    end

    it "encodes larger positive numbers" do
      [0x3fff].pack("r").should == "\xff\xff\x00"
      [0x4000].pack("r").should == "\x80\x80\x01"
    end

    it "encodes larger negative numbers" do
      [-0x3fff].pack("r").should == "\x81\x80\x7f"
      [-0x4000].pack("r").should == "\x80\x80\x7f"
    end

    it "encodes very large numbers" do
      [0xffff_ffff_ffff_ffff_ffff_ffff].pack("r").should == "\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\x1F"
      [-0xffff_ffff_ffff_ffff_ffff_ffff].pack("r").should == "\x81\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x60"
    end

    it "encodes multiple values with '*' modifier" do
      [0, 1, -1].pack("r*").should == "\x00\x01\x7f"
    end

    it "round-trips values through pack and unpack" do
      values = [0, 1, -1, 127, -127, 128, -128, 0x3fff, -0x3fff, 0x4000, -0x4000]
      values.pack("r*").unpack("r*").should == values
    end
  end
end
