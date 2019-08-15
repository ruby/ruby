require_relative '../../spec_helper'
require_relative 'fixtures/location'

ruby_version_is "2.6" do
  describe "Binding#source_location" do
    it "returns an [file, line] pair" do
      b = BindingSpecs::LocationMethod::TEST_BINDING
      b.source_location.should == [BindingSpecs::LocationMethod::FILE_PATH, 4]
    end
  end
end
