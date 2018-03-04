require_relative '../../spec_helper'

ruby_version_is '2.4' do
  describe "TrueClass#dup" do
    it "returns self" do
      true.dup.should equal(true)
    end
  end
end
