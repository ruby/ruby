describe :env_to_hash, shared: true do
  before :each do
    @saved_foo = ENV["foo"]
  end

  after :each do
    ENV["foo"]= @saved_foo
  end

  it "returns the ENV as a hash" do
    ENV["foo"] = "bar"
    h = ENV.send(@method)
    h.should be_an_instance_of(Hash)
    h["foo"].should == "bar"
  end

  it "uses the locale encoding for keys" do
    ENV.send(@method).keys.all? {|k| k.encoding == Encoding.find('locale') }.should be_true
  end

  it "uses the locale encoding for values" do
    ENV.send(@method).values.all? {|v| v.encoding == Encoding.find('locale') }.should be_true
  end

  it "duplicates the ENV when converting to a Hash" do
    h = ENV.send(@method)
    h.should_not equal ENV
    h.size.should == ENV.size
    h.each_pair do |k, v|
      ENV[k].should == v
    end
  end
end
