# -*- encoding: binary -*-
require_relative '../../../spec_helper'
require_relative '../fixtures/classes'
require_relative 'shared/basic'

describe "String#unpack with directive 'w'" do
  it_behaves_like :string_unpack_basic, 'w'
  it_behaves_like :string_unpack_no_platform, 'w'

  it "decodes a BER-compressed integer" do
    [ ["\x00", [0]],
      ["\x01", [1]],
      ["\xce\x0f", [9999]],
      ["\x84\x80\x80\x80\x80\x80\x80\x80\x80\x00", [2**65]]
    ].should be_computed_by(:unpack, "w")
  end

  it "ignores NULL bytes between directives" do
    "\x01\x02\x03".unpack("w\x00w").should == [1, 2]
  end

  it "ignores spaces between directives" do
    "\x01\x02\x03".unpack("w w").should == [1, 2]
  end
end

describe "String#unpack with directive 'w*'" do

  it "decodes BER-compressed integers" do
    "\x01\x02\x03\x04".unpack("w*").should == [1, 2, 3, 4]
    "\x00\xCE\x0F\x84\x80\x80\x80\x80\x80\x80\x80\x80\x00\x01\x00".unpack("w*").should == [0, 9999, 2**65, 1, 0]
    "\x81\x80\x80\x80\x80\x80\x80\x80\x80\x00\x90\x80\x80\x80\x80\x80\x80\x80\x03\x01\x02".unpack("w*").should == [2**63, (2**60 + 3), 1, 2]
  end

end
