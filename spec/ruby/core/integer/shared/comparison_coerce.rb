require_relative '../fixtures/classes'

describe :integer_comparison_coerce_not_rescue, shared: true do
  it "does not rescue exception raised in other#coerce" do
    b = mock("numeric with failed #coerce")
    b.should_receive(:coerce).and_raise(IntegerSpecs::CoerceError)

    # e.g. 1 > b
    -> { 1.send(@method, b) }.should raise_error(IntegerSpecs::CoerceError)
  end
end
