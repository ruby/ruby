describe :date_valid_jd?, shared: true do
  it "returns true if passed a number value" do
    Date.send(@method, -100).should == true
    Date.send(@method, 100.0).should == true
    Date.send(@method, 2**100).should == true
    Date.send(@method, Rational(1,2)).should == true
  end

  it "returns false if passed nil" do
    Date.send(@method, nil).should == false
  end

  it "returns false if passed symbol" do
    Date.send(@method, :number).should == false
  end

  it "returns false if passed false" do
    Date.send(@method, false).should == false
  end
end
