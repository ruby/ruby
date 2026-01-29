require_relative '../spec_helper'

ruby_version_is "3.4" do
  eval <<-RUBY # use eval to avoid warnings on Ruby 3.3
  describe "The `it` parameter" do
    it "provides it in a block" do
      -> { it }.call("a").should == "a"
      proc { it }.call("a").should == "a"
      lambda { it }.call("a").should == "a"
      ["a"].map { it }.should == ["a"]
    end

    it "assigns nil to not passed parameters" do
      proc { it }.call().should == nil
    end

    it "can be used in both outer and nested blocks at the same time" do
      -> { it + -> { it * it }.call(2) }.call(3).should == 7
    end

    it "can be reassigned to act as a local variable" do
      proc { tmp = it; it = tmp * 2; it }.call(21).should == 42
    end

    it "is a regular local variable if there is already a 'it' local variable" do
      it = 0
      proc { it }.call("a").should == 0
    end

    it "is a regular local variable if there is a method `it` defined" do
      o = Object.new
      def o.it
        21
      end

      o.instance_eval("proc { it * 2 }").call(1).should == 2
    end

    it "is not shadowed by an reassignment in a block" do
      a = nil
      proc { a = it; it = 42 }.call(0)
      a.should == 0 # if `it` were shadowed its value would be nil
    end

    it "raises SyntaxError when block parameters are specified explicitly" do
      -> { eval("-> () { it }")         }.should raise_error(SyntaxError, /ordinary parameter is defined/)
      -> { eval("-> (x) { it }")        }.should raise_error(SyntaxError, /ordinary parameter is defined/)

      -> { eval("proc { || it }")       }.should raise_error(SyntaxError, /ordinary parameter is defined/)
      -> { eval("proc { |x| it }")      }.should raise_error(SyntaxError, /ordinary parameter is defined/)

      -> { eval("lambda { || it }")     }.should raise_error(SyntaxError, /ordinary parameter is defined/)
      -> { eval("lambda { |x| it }")    }.should raise_error(SyntaxError, /ordinary parameter is defined/)

      -> { eval("['a'].map { || it }")  }.should raise_error(SyntaxError, /ordinary parameter is defined/)
      -> { eval("['a'].map { |x| it }") }.should raise_error(SyntaxError, /ordinary parameter is defined/)
    end

    it "cannot be mixed with numbered parameters" do
      -> {
        eval("proc { it + _1 }")
      }.should raise_error(SyntaxError, /numbered parameters are not allowed when 'it' is already used|'it' is already used in/)

      -> {
        eval("proc { _1 + it }")
      }.should raise_error(SyntaxError, /numbered parameter is already used in|'it' is not allowed when a numbered parameter is already used/)
    end

    it "affects block arity" do
      -> {}.arity.should == 0
      -> { it }.arity.should == 1
    end

    it "affects block parameters" do
      -> { it }.parameters.should == [[:req]]

      ruby_version_is ""..."4.0" do
        proc { it }.parameters.should == [[:opt, nil]]
      end
      ruby_version_is "4.0" do
        proc { it }.parameters.should == [[:opt]]
      end
    end

    it "does not affect binding local variables" do
      -> { it; binding.local_variables }.call("a").should == []
    end

    it "does not work in methods" do
      obj = Object.new
      def obj.foo; it; end

      -> { obj.foo("a") }.should raise_error(ArgumentError, /wrong number of arguments/)
    end

    context "given multiple arguments" do
      it "provides it in a block and assigns the first argument for a block" do
        proc { it }.call("a", "b").should == "a"
      end

      it "raises ArgumentError for a proc" do
        -> { -> { it }.call("a", "b") }.should raise_error(ArgumentError, "wrong number of arguments (given 2, expected 1)")
        -> { lambda { it }.call("a", "b") }.should raise_error(ArgumentError, "wrong number of arguments (given 2, expected 1)")
      end
    end
  end
  RUBY
end
