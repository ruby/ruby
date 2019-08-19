require File.expand_path('../../fixtures/classes', __FILE__)

describe :integer_arithmetic_coerce_rescue, shared: true do
  it "rescues exception (StandardError and subclasses) raised in other#coerce and raises TypeError" do
    b = mock("numeric with failed #coerce")
    b.should_receive(:coerce).and_raise(IntegerSpecs::CoerceError)

    # e.g. 1 + b
    -> { 1.send(@method, b) }.should raise_error(TypeError, /MockObject can't be coerced into Integer/)
  end

  it "does not rescue Exception and StandardError siblings raised in other#coerce" do
    [Exception, NoMemoryError].each do |exception|
      b = mock("numeric with failed #coerce")
      b.should_receive(:coerce).and_raise(exception)

      # e.g. 1 + b
      -> { 1.send(@method, b) }.should raise_error(exception)
    end
  end
end

describe :integer_arithmetic_coerce_not_rescue, shared: true do
  it "does not rescue exception raised in other#coerce" do
    b = mock("numeric with failed #coerce")
    b.should_receive(:coerce).and_raise(IntegerSpecs::CoerceError)

    # e.g. 1 + b
    -> { 1.send(@method, b) }.should raise_error(IntegerSpecs::CoerceError)
  end
end
