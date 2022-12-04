require_relative '../../spec_helper'
require_relative 'fixtures/classes'

ruby_version_is ""..."3.0" do
  describe "Kernel#iterator?" do
    it "is a private method" do
      Kernel.should have_private_instance_method(:iterator?)
    end
  end

  describe "Kernel.iterator?" do
    it "needs to be reviewed for spec completeness"
  end
end
