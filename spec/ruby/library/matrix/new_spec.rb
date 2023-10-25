require_relative '../../spec_helper'

ruby_version_is ""..."3.1" do
  require 'matrix'

  describe "Matrix.new" do
    it "is private" do
      Matrix.should have_private_method(:new)
    end
  end
end
