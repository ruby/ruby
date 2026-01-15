describe :env_include, shared: true do
  before :each do
    @saved_foo = ENV["foo"]
  end

  after :each do
    ENV["foo"] = @saved_foo
  end

  it "returns true if ENV has the key" do
    ENV["foo"] = "bar"
    ENV.send(@method, "foo").should == true
  end

  it "returns false if ENV doesn't include the key" do
    ENV.delete("foo")
    ENV.send(@method, "foo").should == false
  end

  it "coerces the key with #to_str" do
    ENV["foo"] = "bar"
    k = mock('key')
    k.should_receive(:to_str).and_return("foo")
    ENV.send(@method, k).should == true
  end

  it "raises TypeError if the argument is not a String and does not respond to #to_str" do
    -> { ENV.send(@method, Object.new) }.should raise_error(TypeError, "no implicit conversion of Object into String")
  end
end
