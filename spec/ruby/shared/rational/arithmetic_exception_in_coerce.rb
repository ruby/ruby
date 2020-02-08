require_relative '../../fixtures/rational'

describe :rational_arithmetic_exception_in_coerce, shared: true do
  it "does not rescue exception raised in other#coerce" do
    b = mock("numeric with failed #coerce")
    b.should_receive(:coerce).and_raise(RationalSpecs::CoerceError)

    # e.g. Rational(3, 4) + b
    -> { Rational(3, 4).send(@method, b) }.should raise_error(RationalSpecs::CoerceError)
  end
end
