describe :time_gm, shared: true do
  it "creates a time based on given values, interpreted as UTC (GMT)" do
    Time.send(@method, 2000,"jan",1,20,15,1).inspect.should == "2000-01-01 20:15:01 UTC"
  end

  it "creates a time based on given C-style gmtime arguments, interpreted as UTC (GMT)" do
    time = Time.send(@method, 1, 15, 20, 1, 1, 2000, :ignored, :ignored, :ignored, :ignored)
    time.inspect.should == "2000-01-01 20:15:01 UTC"
  end

  it "interprets pre-Gregorian reform dates using Gregorian proleptic calendar" do
    Time.send(@method, 1582, 10, 4, 12).to_i.should == -12220200000 # 2299150j
  end

  it "interprets Julian-Gregorian gap dates using Gregorian proleptic calendar" do
    Time.send(@method, 1582, 10, 14, 12).to_i.should == -12219336000 # 2299160j
  end

  it "interprets post-Gregorian reform dates using Gregorian calendar" do
    Time.send(@method, 1582, 10, 15, 12).to_i.should == -12219249600 # 2299161j
  end

  it "handles fractional usec close to rounding limit" do
    time = Time.send(@method, 2000, 1, 1, 12, 30, 0, 9999r/10000)

    time.usec.should == 0
    time.nsec.should == 999
  end

  guard -> {
    with_timezone 'right/UTC' do
      (Time.gm(1972, 6, 30, 23, 59, 59) + 1).sec == 60
    end
  } do
    it "handles real leap seconds in zone 'right/UTC'" do
      with_timezone 'right/UTC' do
        time = Time.send(@method, 1972, 6, 30, 23, 59, 60)

        time.sec.should == 60
        time.min.should == 59
        time.hour.should == 23
        time.day.should == 30
        time.month.should == 6
      end
    end
  end

  it "handles bad leap seconds by carrying values forward" do
    with_timezone 'UTC' do
      time = Time.send(@method, 2017, 7, 5, 23, 59, 60)
      time.sec.should == 0
      time.min.should == 0
      time.hour.should == 0
      time.day.should == 6
      time.month.should == 7
    end
  end

  it "handles a value of 60 for seconds by carrying values forward in zone 'UTC'" do
    with_timezone 'UTC' do
      time = Time.send(@method, 1972, 6, 30, 23, 59, 60)

      time.sec.should == 0
      time.min.should == 0
      time.hour.should == 0
      time.day.should == 1
      time.month.should == 7
    end
  end
end
