require_relative '../spec_helper'

describe "Numbered parameters" do
  it "provides default parameters _1, _2, ... in a block" do
    -> { _1 }.call("a").should == "a"
    proc { _1 }.call("a").should == "a"
    lambda { _1 }.call("a").should == "a"
    ["a"].map { _1 }.should == ["a"]
  end

  it "assigns nil to not passed parameters" do
    proc { [_1, _2] }.call("a").should == ["a", nil]
    proc { [_1, _2] }.call("a", "b").should == ["a", "b"]
  end

  it "supports variables _1-_9 only for the first 9 passed parameters" do
    block = proc { [_1, _2, _3, _4, _5, _6, _7, _8, _9] }
    result = block.call(1, 2, 3, 4, 5, 6, 7, 8, 9)
    result.should == [1, 2, 3, 4, 5, 6, 7, 8, 9]
  end

  it "does not support more than 9 parameters" do
    -> {
      proc { [_10] }.call(1, 2, 3, 4, 5, 6, 7, 8, 9, 10)
    }.should raise_error(NameError, /undefined local variable or method `_10'/)
  end

  it "can not be used in both outer and nested blocks at the same time" do
    -> {
      eval("-> { _1; -> { _2 } }")
    }.should raise_error(SyntaxError, /numbered parameter is already used in/m)
  end

  it "cannot be overwritten with local variable" do
    -> {
      eval <<~CODE
        _1 = 0
        proc { _1 }.call("a").should == 0
      CODE
    }.should raise_error(SyntaxError, /_1 is reserved for numbered parameter/)
  end

  it "errors when numbered parameter is overwritten with local variable" do
    -> {
      eval("_1 = 0")
    }.should raise_error(SyntaxError, /_1 is reserved for numbered parameter/)
  end

  it "raises SyntaxError when block parameters are specified explicitly" do
    -> { eval("-> () { _1 }")         }.should raise_error(SyntaxError, /ordinary parameter is defined/)
    -> { eval("-> (x) { _1 }")        }.should raise_error(SyntaxError, /ordinary parameter is defined/)

    -> { eval("proc { || _1 }")       }.should raise_error(SyntaxError, /ordinary parameter is defined/)
    -> { eval("proc { |x| _1 }")      }.should raise_error(SyntaxError, /ordinary parameter is defined/)

    -> { eval("lambda { || _1 }")     }.should raise_error(SyntaxError, /ordinary parameter is defined/)
    -> { eval("lambda { |x| _1 }")    }.should raise_error(SyntaxError, /ordinary parameter is defined/)

    -> { eval("['a'].map { || _1 }")  }.should raise_error(SyntaxError, /ordinary parameter is defined/)
    -> { eval("['a'].map { |x| _1 }") }.should raise_error(SyntaxError, /ordinary parameter is defined/)
  end

  describe "assigning to a numbered parameter" do
    it "raises SyntaxError" do
      -> { eval("proc { _1 = 0 }") }.should raise_error(SyntaxError, /_1 is reserved for numbered parameter/)
    end
  end

  it "affects block arity" do
    -> { _1 }.arity.should == 1
    -> { _2 }.arity.should == 2
    -> { _3 }.arity.should == 3
    -> { _4 }.arity.should == 4
    -> { _5 }.arity.should == 5
    -> { _6 }.arity.should == 6
    -> { _7 }.arity.should == 7
    -> { _8 }.arity.should == 8
    -> { _9 }.arity.should == 9

    ->     { _9 }.arity.should == 9
    proc   { _9 }.arity.should == 9
    lambda { _9 }.arity.should == 9
  end

  it "affects block parameters" do
    -> { _1 }.parameters.should == [[:req, :_1]]
    -> { _2 }.parameters.should == [[:req, :_1], [:req, :_2]]

    proc { _1 }.parameters.should == [[:opt, :_1]]
    proc { _2 }.parameters.should == [[:opt, :_1], [:opt, :_2]]
  end

  it "affects binding local variables" do
    -> { _1; binding.local_variables }.call("a").should == [:_1]
    -> { _2; binding.local_variables }.call("a", "b").should == [:_1, :_2]
  end

  it "does not work in methods" do
    obj = Object.new
    def obj.foo; _1 end

    -> { obj.foo("a") }.should raise_error(ArgumentError, /wrong number of arguments/)
  end
end
