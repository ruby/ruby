require_relative '../../spec_helper'

ruby_version_is "3.4" do
  describe "Warning.categories" do
    # There might be more, but these are standard across Ruby implementations
    it "returns the list of possible warning categories" do
      Warning.categories.should.include? :deprecated
      Warning.categories.should.include? :experimental
      Warning.categories.should.include? :performance
    end
  end
end
