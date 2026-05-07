require_relative '../../spec_helper'

describe "Encoding#dummy?" do
  it "returns false for proper encodings" do
    Encoding::UTF_8.dummy?.should == false
    Encoding::ASCII.dummy?.should == false
  end

  it "returns true for dummy encodings" do
    Encoding::ISO_2022_JP.dummy?.should == true
    Encoding::CP50221.dummy?.should == true
    Encoding::UTF_7.dummy?.should == true
  end

  it "returns true for UTF_16 and UTF_32" do
    Encoding::UTF_16.should.dummy?
    Encoding::UTF_32.should.dummy?
  end

  it "implies not #ascii_compatible?" do
    Encoding.list.select(&:dummy?).each do |encoding|
      encoding.should_not.ascii_compatible?
    end
  end
end
