require_relative '../../spec_helper'

describe "Proc#parameters" do
  it "returns an empty Array for a proc expecting no parameters" do
    proc {}.parameters.should == []
  end

  it "returns an Array of Arrays for a proc expecting parameters" do
    p = proc {|x| }
    p.parameters.should be_an_instance_of(Array)
    p.parameters.first.should be_an_instance_of(Array)
  end

  it "sets the first element of each sub-Array to :opt for optional arguments" do
    proc {|x| }.parameters.first.first.should == :opt
    proc {|y,*x| }.parameters.first.first.should == :opt
  end

  it "regards named parameters in procs as optional" do
    proc {|x| }.parameters.first.first.should == :opt
  end

  ruby_version_is "3.2" do
    it "sets the first element of each sub-Array to :req for required argument if lambda keyword used" do
      proc {|x| }.parameters(lambda: true).first.first.should == :req
      proc {|y,*x| }.parameters(lambda: true).first.first.should == :req
    end

    it "regards named parameters in procs as required if lambda keyword used" do
      proc {|x| }.parameters(lambda: true).first.first.should == :req
    end

    it "regards named parameters in lambda as optional if lambda: false keyword used" do
      -> x { }.parameters(lambda: false).first.first.should == :opt
    end

    it "regards named parameters in procs and lambdas as required if lambda keyword is truthy" do
      proc {|x| }.parameters(lambda: 123).first.first.should == :req
      -> x { }.parameters(lambda: 123).first.first.should == :req
    end

    it "ignores the lambda keyword if it is nil" do
      proc {|x|}.parameters(lambda: nil).first.first.should == :opt
      -> x { }.parameters(lambda: nil).first.first.should == :req
    end
  end

  it "regards optional keyword parameters in procs as optional" do
    proc {|x: :y| }.parameters.first.first.should == :key
  end

  it "regards parameters with default values as optional" do
    -> x=1 { }.parameters.first.first.should == :opt
    proc {|x=1| }.parameters.first.first.should == :opt
  end

  it "sets the first element of each sub-Array to :req for required arguments" do
    -> x, y=[] { }.parameters.first.first.should == :req
    -> y, *x { }.parameters.first.first.should == :req
  end

  it "regards named parameters in lambdas as required" do
    -> x { }.parameters.first.first.should == :req
  end

  it "regards keyword parameters in lambdas as required" do
    eval("lambda {|x:| }").parameters.first.first.should == :keyreq
  end

  it "sets the first element of each sub-Array to :rest for parameters prefixed with asterisks" do
    -> *x { }.parameters.first.first.should == :rest
    -> x, *y { }.parameters.last.first.should == :rest
    proc {|*x| }.parameters.first.first.should == :rest
    proc {|x,*y| }.parameters.last.first.should == :rest
  end

  it "sets the first element of each sub-Array to :keyrest for parameters prefixed with double asterisks" do
    -> **x { }.parameters.first.first.should == :keyrest
    -> x, **y { }.parameters.last.first.should == :keyrest
    proc {|**x| }.parameters.first.first.should == :keyrest
    proc {|x,**y| }.parameters.last.first.should == :keyrest
  end

  it "sets the first element of each sub-Array to :block for parameters prefixed with ampersands" do
    -> &x { }.parameters.first.first.should == :block
    -> x, &y { }.parameters.last.first.should == :block
    proc {|&x| }.parameters.first.first.should == :block
    proc {|x,&y| }.parameters.last.first.should == :block
  end

  it "sets the second element of each sub-Array to the name of the argument" do
    -> x { }.parameters.first.last.should == :x
    -> x=Math::PI { }.parameters.first.last.should == :x
    -> an_argument, glark, &foo { }.parameters[1].last.should == :glark
    -> *rest { }.parameters.first.last.should == :rest
    -> &block { }.parameters.first.last.should == :block
    proc {|x| }.parameters.first.last.should == :x
    proc {|x=Math::PI| }.parameters.first.last.should == :x
    proc {|an_argument, glark, &foo| }.parameters[1].last.should == :glark
    proc {|*rest| }.parameters.first.last.should == :rest
    proc {|&block| }.parameters.first.last.should == :block
  end

  it "ignores unnamed rest arguments" do
    -> x {}.parameters.should == [[:req, :x]]
  end

  it "ignores implicit rest arguments" do
    proc { |x, | }.parameters.should == [[:opt, :x]]
    -> x { }.parameters.should == [[:req, :x]]
  end

  ruby_version_is '3.2' do
    it "adds rest arg with name * for \"star\" argument" do
      -> * {}.parameters.should == [[:rest, :*]]
    end

    it "adds keyrest arg with ** as a name for \"double star\" argument" do
      -> ** {}.parameters.should == [[:keyrest, :**]]
    end
  end

  ruby_version_is ''...'3.2' do
    it "adds nameless rest arg for \"star\" argument" do
      -> * {}.parameters.should == [[:rest]]
    end

    it "adds nameless keyrest arg for \"double star\" argument" do
      -> ** {}.parameters.should == [[:keyrest]]
    end
  end

  ruby_version_is '3.1' do
    it "adds block arg with name & for anonymous block argument" do
      eval('-> & {}.parameters').should == [[:block, :&]]
    end
  end

  it "does not add locals as block options with a block and splat" do
    -> *args, &blk do
      local_is_not_parameter = {}
    end.parameters.should == [[:rest, :args], [:block, :blk]]
    proc do |*args, &blk|
      local_is_not_parameter = {}
    end.parameters.should == [[:rest, :args], [:block, :blk]]
  end

  it "returns all parameters defined with the name _ as _" do
    proc = proc {|_, _, _ = 1, *_, _:, _: 2, **_, &_| }
    proc.parameters.should == [
      [:opt, :_],
      [:opt, :_],
      [:opt, :_],
      [:rest, :_],
      [:keyreq, :_],
      [:key, :_],
      [:keyrest, :_],
      [:block, :_]
    ]

    lambda = -> _, _, _ = 1, *_, _:, _: 2, **_, &_ {}
    lambda.parameters.should == [
      [:req, :_],
      [:req, :_],
      [:opt, :_],
      [:rest, :_],
      [:keyreq, :_],
      [:key, :_],
      [:keyrest, :_],
      [:block, :_]
    ]
  end

  it "returns :nokey for **nil parameter" do
    proc { |**nil| }.parameters.should == [[:nokey]]
  end
end
