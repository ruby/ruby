require_relative '../spec_helper'

ruby_version_is "3.4" do
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

    it "is a regular local variable if there is already a 'it' local variable" do
        it = 0
        proc { it }.call("a").should == 0
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
  end
end
