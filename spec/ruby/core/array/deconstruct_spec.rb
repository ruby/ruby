require_relative '../../spec_helper'

ruby_version_is "2.7" do
  describe "Array#deconstruct" do
    it "returns self" do
      array = [1]

      array.deconstruct.should equal array
    end
  end
end
