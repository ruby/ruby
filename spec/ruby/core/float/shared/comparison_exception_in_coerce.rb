require_relative '../fixtures/classes'

describe :float_comparison_exception_in_coerce, shared: true do
  it "does not rescue exception raised in other#coerce" do
    b = mock("numeric with failed #coerce")
    b.should_receive(:coerce).and_raise(FloatSpecs::CoerceError)

    # e.g. 1.0 > b
    -> { 1.0.send(@method, b) }.should raise_error(FloatSpecs::CoerceError)
  end
end
