describe :time_xmlschema, shared: true do
  ruby_version_is "3.4" do
    it "generates ISO-8601 strings in Z for UTC times" do
      t = Time.utc(1985, 4, 12, 23, 20, 50, 521245)
      t.send(@method).should == "1985-04-12T23:20:50Z"
      t.send(@method, 2).should == "1985-04-12T23:20:50.52Z"
      t.send(@method, 9).should == "1985-04-12T23:20:50.521245000Z"
    end

    it "generates ISO-8601 string with timeone offset for non-UTC times" do
      t = Time.new(1985, 4, 12, 23, 20, 50, "+02:00")
      t.send(@method).should == "1985-04-12T23:20:50+02:00"
      t.send(@method, 2).should == "1985-04-12T23:20:50.00+02:00"
    end

    it "year is always at least 4 digits" do
      t = Time.utc(12, 4, 12)
      t.send(@method).should ==  "0012-04-12T00:00:00Z"
    end

    it "year can be more than 4 digits" do
      t = Time.utc(40_000, 4, 12)
      t.send(@method).should ==  "40000-04-12T00:00:00Z"
    end

    it "year can be negative" do
      t = Time.utc(-2000, 4, 12)
      t.send(@method).should ==  "-2000-04-12T00:00:00Z"
    end
  end
end
