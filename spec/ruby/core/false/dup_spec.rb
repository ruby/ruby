require File.expand_path('../../../spec_helper', __FILE__)

ruby_version_is '2.4' do
  describe "FalseClass#dup" do
    it "returns self" do
      false.dup.should equal(false)
    end
  end
end
