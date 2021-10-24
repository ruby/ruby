describe :env_key, shared: true do
  before :each do
    @saved_foo = ENV["foo"]
  end

  after :each do
    ENV["foo"] = @saved_foo
  end

  it "returns the index associated with the passed value" do
    ENV["foo"] = "bar"
    suppress_warning {
      ENV.send(@method, "bar").should == "foo"
    }
  end

  it "returns nil if the passed value is not found" do
    ENV.delete("foo")
    suppress_warning {
      ENV.send(@method, "foo").should be_nil
    }
  end

  it "raises TypeError if the argument is not a String and does not respond to #to_str" do
    -> {
      suppress_warning {
        ENV.send(@method, Object.new)
      }
    }.should raise_error(TypeError, "no implicit conversion of Object into String")
  end
end
