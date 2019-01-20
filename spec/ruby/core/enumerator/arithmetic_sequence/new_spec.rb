require_relative '../../../spec_helper'

ruby_version_is "2.6" do
  describe "Enumerator::ArithmeticSequence.new" do
    it "is not defined" do
      lambda {
        Enumerator::ArithmeticSequence.new
      }.should raise_error(NoMethodError)
    end
  end

  describe "Enumerator::ArithmeticSequence.allocate" do
    it "is not defined" do
      lambda {
        Enumerator::ArithmeticSequence.allocate
      }.should raise_error(TypeError, 'allocator undefined for Enumerator::ArithmeticSequence')
    end
  end
end
