require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Hash#to_h" do
  it "returns self for Hash instances" do
    h = {}
    h.to_h.should equal(h)
  end

  ruby_version_is "2.6" do
    it "converts [key, value] pairs returned by the block to a hash" do
      {a: 1, b: 2}.to_h {|k, v| [k.to_s, v*v]}.should == { "a" => 1, "b" => 4 }
    end
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
end
