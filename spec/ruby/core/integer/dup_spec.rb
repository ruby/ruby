require File.expand_path('../../../spec_helper', __FILE__)

ruby_version_is '2.4' do
  describe "Integer#dup" do
    it "returns self" do
      int = 2
      int.dup.should equal(int)
    end
  end
end
