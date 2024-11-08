describe :date_month, shared: true do
  it "returns the month" do
    m = Date.new(2000, 7, 1).send(@method)
    m.should == 7
  end
end
