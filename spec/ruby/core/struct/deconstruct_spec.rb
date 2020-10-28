require_relative '../../spec_helper'

ruby_version_is "2.7" do
  describe "Struct#deconstruct" do
    it "returns an array of attribute values" do
      struct = Struct.new(:x, :y)
      s = struct.new(1, 2)

      s.deconstruct.should == [1, 2]
    end
  end
end
