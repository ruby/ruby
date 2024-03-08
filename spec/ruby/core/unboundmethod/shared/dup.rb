describe :unboundmethod_dup, shared: true do
  it "returns a copy of self" do
    a = Class.instance_method(:instance_method)
    b = a.send(@method)

    a.should == b
    a.should_not equal(b)
  end

  ruby_version_is "3.4" do
    it "copies instance variables" do
      method = Class.instance_method(:instance_method)
      method.instance_variable_set(:@ivar, 1)
      cl = method.send(@method)
      cl.instance_variables.should == [:@ivar]
    end

    it "copies the finalizer" do
      code = <<-RUBY
        obj = Class.instance_method(:instance_method)

        ObjectSpace.define_finalizer(obj, Proc.new { STDOUT.write "finalized\n" })

        obj.clone

        exit 0
      RUBY

      ruby_exe(code).lines.sort.should == ["finalized\n", "finalized\n"]
    end
  end
end
