require File.expand_path('../../../spec_helper', __FILE__)

ruby_version_is '2.4' do
  describe "NilClass#dup" do
    it "returns self" do
      nil.dup.should equal(nil)
    end
  end
end
