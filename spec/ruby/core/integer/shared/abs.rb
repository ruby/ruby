describe :integer_abs, shared: true do
  context "fixnum" do
    it "returns self's absolute fixnum value" do
      { 0 => [0, -0, +0], 2 => [2, -2, +2], 100 => [100, -100, +100] }.each do |key, values|
        values.each do |value|
          value.send(@method).should == key
        end
      end
    end
  end

  context "bignum" do
    it "returns the absolute bignum value" do
      bignum_value(39).send(@method).should == 9223372036854775847
      (-bignum_value(18)).send(@method).should == 9223372036854775826
    end
  end
end
