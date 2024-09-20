describe :time_yday, shared: true do
  it 'returns the correct value for each day of each month' do
    mdays = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

    yday = 1
    mdays.each_with_index do |days, month|
      days.times do |day|
        @method.call(2014, month+1, day+1).should == yday
        yday += 1
      end
    end
  end

  it 'supports leap years' do
    @method.call(2016, 2, 29).should == 31 + 29
    @method.call(2016, 3, 1).should == 31 + 29 + 1
  end
end
