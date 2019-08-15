require_relative '../../../spec_helper'

ruby_version_is ''...'2.5' do
  require 'mathn'

  describe "Float#**" do
    it "returns self raised to other (positive) power" do
      (2.0 ** 4).should == 16.0
      (2.0 ** 1.2).should be_close(2.2973967, TOLERANCE)
    end

    it "returns a complex number when negative and raised to a fractional power" do
      ((-8.0) ** (1/3)).should be_close(Complex(1, 1.73205), TOLERANCE)
      ((-8.0) ** (1.0/3)).should be_close(Complex(1, 1.73205), TOLERANCE)
    end
  end
end
