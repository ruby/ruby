require_relative '../../spec_helper'
require_relative 'fixtures/location'

describe "Binding#source_location" do
  it "returns an [file, line] pair" do
    b = BindingSpecs::LocationMethod::TEST_BINDING
    b.source_location.should == [BindingSpecs::LocationMethod::FILE_PATH, 4]
  end

  it "works for eval with a given line" do
    b = eval('binding', nil, "foo", 100)
    b.source_location.should == ["foo", 100]
  end
end
