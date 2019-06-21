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
end
