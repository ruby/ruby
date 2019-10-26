describe :env_update, shared: true do
  before :each do
    @saved_foo = ENV["foo"]
    @saved_bar = ENV["bar"]
  end

  after :each do
    ENV["foo"] = @saved_foo
    ENV["bar"] = @saved_bar
  end

  it "adds the parameter hash to ENV" do
    ENV.send @method, {"foo" => "0", "bar" => "1"}
    ENV["foo"].should == "0"
    ENV["bar"].should == "1"
  end

  it "returns ENV when no block given" do
    ENV.send(@method, {"foo" => "0", "bar" => "1"}).should equal(ENV)
  end

  it "yields key, the old value and the new value when replacing entries" do
    ENV.send @method, {"foo" => "0", "bar" => "3"}
    a = []
    ENV.send @method, {"foo" => "1", "bar" => "4"} do |key, old, new|
      a << [key, old, new]
      (new.to_i + 1).to_s
    end
    ENV["foo"].should == "2"
    ENV["bar"].should == "5"
    a[0].should == ["foo", "0", "1"]
    a[1].should == ["bar", "3", "4"]
  end

  it "returns ENV when block given" do
    ENV.send(@method, {"foo" => "0", "bar" => "1"}){}.should equal(ENV)
  end

  it "raises TypeError when a name is not coercible to String" do
    -> { ENV.send @method, Object.new => "0" }.should raise_error(TypeError, "no implicit conversion of Object into String")
  end

  it "raises TypeError when a value is not coercible to String" do
    -> { ENV.send @method, "foo" => Object.new }.should raise_error(TypeError, "no implicit conversion of Object into String")
  end

  it "updates good data preceding an error" do
    ENV["foo"] = "0"
    begin
      ENV.send @method, {"foo" => "2", Object.new => "1"}
    rescue TypeError
    ensure
      ENV["foo"].should == "2"
    end
  end

  it "does not update good data following an error" do
    ENV["foo"] = "0"
    begin
      ENV.send @method, {Object.new => "1", "foo" => "2"}
    rescue TypeError
    ensure
      ENV["foo"].should == "0"
    end
  end
end
