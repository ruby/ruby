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

    it "copies the default" do
      @h.default = 42
      @h.to_h.default.should == 42
      @h[:hello].should == 42
    end

    it "copies the default_proc" do
      @h.default_proc = prc = Proc.new{ |h, k| h[k] = 2 * k }
      @h.to_h.default_proc.should == prc
      @h[42].should == 84
    end
  end

  ruby_version_is "2.6" do
    context "with block" do
      it "converts [key, value] pairs returned by the block to a hash" do
        { a: 1, b: 2 }.to_h { |k, v| [k.to_s, v*v]}.should == { "a" => 1, "b" => 4 }
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
    end
  end
end
