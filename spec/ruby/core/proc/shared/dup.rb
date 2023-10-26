describe :proc_dup, shared: true do
  it "returns a copy of self" do
    a = -> { "hello" }
    b = a.send(@method)

    a.should_not equal(b)

    a.call.should == b.call
  end

  ruby_version_is "3.2" do
    it "returns an instance of subclass" do
      cl = Class.new(Proc)

      cl.new{}.send(@method).class.should == cl
    end
  end
end
