describe :date_valid_jd?, shared: true do
  it "returns true if passed a number value" do
    Date.send(@method, -100).should be_true
    Date.send(@method, 100.0).should be_true
    Date.send(@method, 2**100).should be_true
    Date.send(@method, Rational(1,2)).should be_true
  end

  it "returns false if passed nil" do
    Date.send(@method, nil).should be_false
  end

  ruby_version_is ''...'2.7' do
    it "returns true if passed symbol" do
      Date.send(@method, :number).should be_true
    end

    it "returns true if passed false" do
      Date.send(@method, false).should be_true
    end
  end

  ruby_version_is '2.7' do
    it "returns false if passed symbol" do
      Date.send(@method, :number).should be_false
    end

    it "returns false if passed false" do
      Date.send(@method, false).should be_false
    end
  end
end
