describe :proc_compose, shared: true do
  it "raises TypeError if passed not callable object" do
    lhs = @object.call
    not_callable = Object.new

    -> {
      lhs.send(@method, not_callable)
    }.should raise_error(TypeError, "callable object is expected")

  end

  it "does not try to coerce argument with #to_proc" do
    lhs = @object.call

    succ = Object.new
    def succ.to_proc(s); s.succ; end

    -> {
      lhs.send(@method, succ)
    }.should raise_error(TypeError, "callable object is expected")
  end
end
