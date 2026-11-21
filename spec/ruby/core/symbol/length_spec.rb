require_relative '../../spec_helper'

describe "Symbol#length" do
  it "returns 0 for empty name" do
    :''.length.should == 0
  end

  it "returns 1 for name formed by a NUL character" do
    :"\x00".length.should == 1
  end

  it "returns 3 for name formed by 3 ASCII characters" do
    :one.length.should == 3
  end

  it "returns 4 for name formed by 4 ASCII characters" do
    :four.length.should == 4
  end

  it "returns 4 for name formed by 1 multibyte and 3 ASCII characters" do
    :"\xC3\x9Cber".length.should == 4
  end
end
