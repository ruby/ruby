require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Hash#to_h" do
  it "returns self for Hash instances" do
    h = {}
    h.to_h.should equal(h)
  end

  describe "when called on a subclass of Hash" do
    before :each do
      @h = HashSpecs::MyHash.new
      @h[:foo] = :bar
    end

    it "returns a new Hash instance" do
      @h.to_h.should be_an_instance_of(Hash)
      @h.to_h.should == @h
      @h[:foo].should == :bar
    end

    it "retains the default" do
      @h.default = 42
      @h.to_h.default.should == 42
      @h[:hello].should == 42
    end

    it "retains the default_proc" do
      @h.default_proc = prc = Proc.new{ |h, k| h[k] = 2 * k }
      @h.to_h.default_proc.should == prc
      @h[42].should == 84
    end

    it "retains compare_by_identity flag" do
      @h.compare_by_identity
      @h.to_h.compare_by_identity?.should == true
    end
  end

  context "with block" do
    it "converts [key, value] pairs returned by the block to a hash" do
      { a: 1, b: 2 }.to_h { |k, v| [k.to_s, v*v]}.should == { "a" => 1, "b" => 4 }
    end

    it "passes to a block each pair's key and value as separate arguments" do
      ScratchPad.record []
      { a: 1, b: 2 }.to_h { |k, v| ScratchPad << [k, v]; [k, v] }
      ScratchPad.recorded.sort.should == [[:a, 1], [:b, 2]]

      ScratchPad.record []
      { a: 1, b: 2 }.to_h { |*args| ScratchPad << args; [args[0], args[1]] }
      ScratchPad.recorded.sort.should == [[:a, 1], [:b, 2]]
    end

    it "raises ArgumentError if block returns longer or shorter array" do
      -> do
        { a: 1, b: 2 }.to_h { |k, v| [k.to_s, v*v, 1] }
      end.should raise_error(ArgumentError, /element has wrong array length/)

      -> do
        { a: 1, b: 2 }.to_h { |k, v| [k] }
      end.should raise_error(ArgumentError, /element has wrong array length/)
    end

    it "raises TypeError if block returns something other than Array" do
      -> do
        { a: 1, b: 2 }.to_h { |k, v| "not-array" }
      end.should raise_error(TypeError, /wrong element type String/)
    end

    it "coerces returned pair to Array with #to_ary" do
      x = mock('x')
      x.stub!(:to_ary).and_return([:b, 'b'])

      { a: 1 }.to_h { |k| x }.should == { :b => 'b' }
    end

    it "does not coerce returned pair to Array with #to_a" do
      x = mock('x')
      x.stub!(:to_a).and_return([:b, 'b'])

      -> do
        { a: 1 }.to_h { |k| x }
      end.should raise_error(TypeError, /wrong element type MockObject/)
    end

    it "does not retain the default value" do
      h = Hash.new(1)
      h2 = h.to_h { |k, v| [k.to_s, v*v]}
      h2.default.should be_nil
    end

    it "does not retain the default_proc" do
      pr = proc { |h, k| h[k] = [] }
      h = Hash.new(&pr)
      h2 = h.to_h { |k, v| [k.to_s, v*v]}
      h2.default_proc.should be_nil
    end

    it "does not retain compare_by_identity flag" do
      h = { a: 9, c: 4 }.compare_by_identity
      h2 = h.to_h { |k, v| [k.to_s, v*v]}
      h2.compare_by_identity?.should == false
    end
  end
end
