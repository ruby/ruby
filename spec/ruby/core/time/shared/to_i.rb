describe :time_to_i, shared: true do
  it "returns the value of time as an integer number of seconds since epoch" do
    Time.at(0).send(@method).should == 0
  end

  it "doesn't return an actual number of seconds in time" do
    Time.at(65.5).send(@method).should == 65
  end

  it "rounds fractional seconds toward zero" do
    t = Time.utc(1960, 1, 1, 0, 0, 0, 999_999)

    t.to_f.to_i.should == -315619199
    t.to_i.should == -315619200
  end
end
