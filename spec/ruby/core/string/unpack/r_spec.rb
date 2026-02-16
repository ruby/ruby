# encoding: binary
require_relative '../../../spec_helper'
require_relative '../fixtures/classes'
require_relative 'shared/basic'

ruby_version_is "4.1" do
  describe "String#unpack with format 'R'" do
    it_behaves_like :string_unpack_basic, 'R'
    it_behaves_like :string_unpack_no_platform, 'R'

    it "decodes a ULEB128 integer" do
      [ ["\x00",                                     [0]],
        ["\x01",                                     [1]],
        ["\x7f",                                     [127]],
        ["\x80\x01",                                 [128]],
        ["\xff\x7f",                                 [0x3fff]],
        ["\x80\x80\x01",                             [0x4000]],
        ["\xff\xff\xff\xff\x0f",                     [0xffffffff]],
        ["\x80\x80\x80\x80\x10",                     [0x100000000]],
        ["\xff\xff\xff\xff\xff\xff\xff\xff\xff\x01", [0xffff_ffff_ffff_ffff]],
      ].should be_computed_by(:unpack, "R")
    end

    it "decodes multiple values with '*' modifier" do
      "\x01\x02".unpack("R*").should == [1, 2]
      "\x7f\x80\x01".unpack("R*").should == [127, 128]
    end

    it "returns nil for incomplete data" do
      "\xFF".unpack("R").should == [nil]
      "\xFF".unpack1("R").should == nil
    end

    it "returns nil for remaining incomplete values after a valid one" do
      bytes = [256].pack("R")
      (bytes + "\xFF").unpack("RRRR").should == [256, nil, nil, nil]
    end

    it "skips incomplete values with '*' modifier" do
      "\xFF".unpack("R*").should == []
    end
  end

  describe "String#unpack with format 'r'" do
    it_behaves_like :string_unpack_basic, 'r'
    it_behaves_like :string_unpack_no_platform, 'r'

    it "decodes a SLEB128 integer" do
      [ ["\x00",      [0]],
        ["\x01",      [1]],
        ["\x7f",      [-1]],
        ["\x7e",      [-2]],
        ["\xff\x00",  [127]],
        ["\x80\x01",  [128]],
        ["\x81\x7f",  [-127]],
        ["\x80\x7f",  [-128]],
      ].should be_computed_by(:unpack, "r")
    end

    it "decodes larger numbers" do
      "\xff\xff\x00".unpack("r").should == [0x3fff]
      "\x80\x80\x01".unpack("r").should == [0x4000]
      "\x81\x80\x7f".unpack("r").should == [-0x3fff]
      "\x80\x80\x7f".unpack("r").should == [-0x4000]
    end

    it "decodes multiple values with '*' modifier" do
      "\x00\x01\x7f".unpack("r*").should == [0, 1, -1]
    end

    it "returns nil for incomplete data" do
      "\xFF".unpack("r").should == [nil]
      "\xFF".unpack1("r").should == nil
    end

    it "returns nil for remaining incomplete values after a valid one" do
      bytes = [256].pack("r")
      (bytes + "\xFF").unpack("rrrr").should == [256, nil, nil, nil]
    end

    it "skips incomplete values with '*' modifier" do
      "\xFF".unpack("r*").should == []
    end
  end
end
