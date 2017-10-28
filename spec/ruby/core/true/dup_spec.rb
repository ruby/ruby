require File.expand_path('../../../spec_helper', __FILE__)

ruby_version_is '2.4' do
  describe "TrueClass#dup" do
    it "returns self" do
      true.dup.should equal(true)
    end
  end
end
