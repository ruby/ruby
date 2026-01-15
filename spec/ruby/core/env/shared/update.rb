describe :env_update, shared: true do
  before :each do
    @saved_foo = ENV["foo"]
    @saved_bar = ENV["bar"]
  end

  after :each do
    ENV["foo"] = @saved_foo
    ENV["bar"] = @saved_bar
  end

  it "adds the parameter hash to ENV, returning ENV" do
    ENV.send(@method, "foo" => "0", "bar" => "1").should equal(ENV)
    ENV["foo"].should == "0"
    ENV["bar"].should == "1"
  end

  it "adds the multiple parameter hashes to ENV, returning ENV" do
    ENV.send(@method, {"foo" => "multi1"}, {"bar" => "multi2"}).should equal(ENV)
    ENV["foo"].should == "multi1"
    ENV["bar"].should == "multi2"
  end

  it "returns ENV when no block given" do
    ENV.send(@method, {"foo" => "0", "bar" => "1"}).should equal(ENV)
  end

  it "yields key, the old value and the new value when replacing an entry" do
    ENV.send @method, {"foo" => "0", "bar" => "3"}
    a = []
    ENV.send @method, {"foo" => "1", "bar" => "4"} do |key, old, new|
      a << [key, old, new]
      new
    end
    a[0].should == ["foo", "0", "1"]
    a[1].should == ["bar", "3", "4"]
  end

  it "yields key, the old value and the new value when replacing an entry" do
    ENV.send @method, {"foo" => "0", "bar" => "3"}
    ENV.send @method, {"foo" => "1", "bar" => "4"} do |key, old, new|
      (new.to_i + 1).to_s
    end
    ENV["foo"].should == "2"
    ENV["bar"].should == "5"
  end

  # BUG: https://bugs.ruby-lang.org/issues/16192
  it "does not evaluate the block when the name is new" do
    ENV.delete("bar")
    ENV.send @method, {"foo" => "0"}
    ENV.send(@method, "bar" => "1") { |key, old, new| fail "Should not get here" }
    ENV["bar"].should == "1"
  end

  # BUG: https://bugs.ruby-lang.org/issues/16192
  it "does not use the block's return value as the value when the name is new" do
    ENV.delete("bar")
    ENV.send @method, {"foo" => "0"}
    ENV.send(@method, "bar" => "1") { |key, old, new| "Should not use this value" }
    ENV["foo"].should == "0"
    ENV["bar"].should == "1"
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

  it "raises Errno::EINVAL when a name contains the '=' character" do
    -> { ENV.send(@method, "foo=" => "bar") }.should raise_error(Errno::EINVAL)
  end

  it "raises Errno::EINVAL when a name is an empty string" do
    -> { ENV.send(@method, "" => "bar") }.should raise_error(Errno::EINVAL)
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
