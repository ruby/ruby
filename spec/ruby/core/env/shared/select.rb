describe :env_select, shared: true do
  before :each do
    @saved_foo = ENV["foo"]
  end

  after :each do
    ENV["foo"] = @saved_foo
  end

  it "returns a Hash of names and values for which block return true" do
    ENV["foo"] = "bar"
    (ENV.send(@method) { |k, v| k == "foo" }).should == { "foo" => "bar" }
  end

  it "returns an Enumerator when no block is given" do
    enum = ENV.send(@method)
    enum.should be_an_instance_of(Enumerator)
  end

  it "selects via the enumerator" do
    enum = ENV.send(@method)
    ENV["foo"] = "bar"
    enum.each { |k, v| k == "foo" }.should == { "foo" => "bar"}
  end
end

describe :env_select!, shared: true do
  before :each do
    @saved_foo = ENV["foo"]
  end

  after :each do
    ENV["foo"] = @saved_foo
  end

  it "removes environment variables for which the block returns true" do
    ENV["foo"] = "bar"
    ENV.send(@method) { |k, v| k != "foo" }
    ENV["foo"].should == nil
  end

  it "returns self if any changes were made" do
    ENV["foo"] = "bar"
    (ENV.send(@method) { |k, v| k != "foo" }).should == ENV
  end

  it "returns nil if no changes were made" do
    (ENV.send(@method) { true }).should == nil
  end

  it "returns an Enumerator if called without a block" do
    ENV.send(@method).should be_an_instance_of(Enumerator)
  end

  it "selects via the enumerator" do
    enum = ENV.send(@method)
    ENV["foo"] = "bar"
    enum.each { |k, v| k != "foo" }
    ENV["foo"].should == nil
  end
end
