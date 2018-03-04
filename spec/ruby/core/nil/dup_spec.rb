require_relative '../../spec_helper'

ruby_version_is '2.4' do
  describe "NilClass#dup" do
    it "returns self" do
      nil.dup.should equal(nil)
    end
  end
end
