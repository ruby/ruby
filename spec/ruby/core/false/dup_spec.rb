require_relative '../../spec_helper'

ruby_version_is '2.4' do
  describe "FalseClass#dup" do
    it "returns self" do
      false.dup.should equal(false)
    end
  end
end
