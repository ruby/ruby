require_relative '../../spec_helper'

ruby_version_is '2.4' do
  describe "Float#dup" do
    it "returns self" do
      float = 2.4
      float.dup.should equal(float)
    end
  end
end
