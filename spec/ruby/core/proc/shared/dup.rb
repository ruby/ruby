describe :proc_dup, shared: true do
  it "returns a copy of self" do
    a = -> { "hello" }
    b = a.send(@method)

    a.should_not equal(b)

    a.call.should == b.call
  end

  it "returns an instance of subclass" do
    cl = Class.new(Proc)

    cl.new{}.send(@method).class.should == cl
  end

  ruby_version_is "3.4" do
    it "copies instance variables" do
      proc = -> { "hello" }
      proc.instance_variable_set(:@ivar, 1)
      cl = proc.send(@method)
      cl.instance_variables.should == [:@ivar]
    end

    it "copies the finalizer" do
      code = <<-'RUBY'
        obj = Proc.new { }

        ObjectSpace.define_finalizer(obj, Proc.new { STDOUT.write "finalized\n" })

        obj.clone

        exit 0
      RUBY

      ruby_exe(code).lines.sort.should == ["finalized\n", "finalized\n"]
    end
  end
end
