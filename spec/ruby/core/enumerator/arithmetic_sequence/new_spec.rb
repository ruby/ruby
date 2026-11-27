require_relative '../../../spec_helper'

describe "Enumerator::ArithmeticSequence.new" do
  it "is not defined" do
    -> {
      Enumerator::ArithmeticSequence.new
    }.should.raise(NoMethodError)
  end
end

describe "Enumerator::ArithmeticSequence.allocate" do
  it "is not defined" do
    -> {
      Enumerator::ArithmeticSequence.allocate
    }.should.raise(TypeError, 'allocator undefined for Enumerator::ArithmeticSequence')
  end
end
