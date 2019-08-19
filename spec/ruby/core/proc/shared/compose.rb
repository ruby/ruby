describe :proc_compose, shared: true do
  ruby_version_is "2.6"..."2.7" do
    it "raises NoMethodError when called if passed not callable object" do
      not_callable = Object.new
      composed = @object.call.send(@method, not_callable)

      -> {
        composed.call('a')
      }.should raise_error(NoMethodError, /undefined method `call' for/)

    end

    it "when called does not try to coerce argument with #to_proc" do
      succ = Object.new
      def succ.to_proc(s); s.succ; end

      composed = @object.call.send(@method, succ)

      -> {
        composed.call('a')
      }.should raise_error(NoMethodError, /undefined method `call' for/)
    end
  end

  ruby_version_is "2.7" do # https://bugs.ruby-lang.org/issues/15428
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
end
