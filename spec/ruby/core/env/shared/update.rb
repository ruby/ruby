describe :env_update, shared: true do
  it "adds the parameter hash to ENV" do
    ENV["foo"].should == nil
    ENV.send @method, "foo" => "bar"
    ENV["foo"].should == "bar"
    ENV.delete "foo"
  end

  it "yields key, the old value and the new value when replacing entries" do
    ENV.send @method, "foo" => "bar"
    ENV["foo"].should == "bar"
    ENV.send(@method, "foo" => "boo") do |key, old, new|
      key.should == "foo"
      old.should == "bar"
      new.should == "boo"
      "rab"
    end
    ENV["foo"].should == "rab"
    ENV.delete "foo"
  end

  ruby_version_is "2.7" do
    it "does not touch when given no arguments" do
      before = ENV.to_h
      ENV.send(@method)
      ENV.to_h.should == before
    end

    it "takes multiple arguments" do
      ENV.send(@method, { "foo" => "foo1", "bar" => "bar1" }, { "foo" => "foo2", "baz" => "baz2" })
      ENV.slice("foo", "bar", "baz").should == { "foo" => "foo2", "bar" => "bar1", "baz" => "baz2" }
    end
  end
end
