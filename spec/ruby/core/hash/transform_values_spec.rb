require_relative '../../spec_helper'

describe "Hash#transform_values" do
  before :each do
    @hash = { a: 1, b: 2, c: 3 }
  end

  it "returns new hash" do
    ret = @hash.transform_values(&:succ)
    ret.should_not equal(@hash)
    ret.should be_an_instance_of(Hash)
  end

  it "sets the result as transformed values with the given block" do
    @hash.transform_values(&:succ).should ==  { a: 2, b: 3, c: 4 }
  end

  it "makes both hashes to share keys" do
    key = [1, 2, 3]
    new_hash = { key => 1 }.transform_values(&:succ)
    new_hash[key].should == 2
    new_hash.keys[0].should equal(key)
  end

  context "when no block is given" do
    it "returns a sized Enumerator" do
      enumerator = @hash.transform_values
      enumerator.should be_an_instance_of(Enumerator)
      enumerator.size.should == @hash.size
      enumerator.each(&:succ).should == { a: 2, b: 3, c: 4 }
    end
  end

  it "returns a Hash instance, even on subclasses" do
    klass = Class.new(Hash)
    h = klass.new
    h[:foo] = 42
    r = h.transform_values{|v| 2 * v}
    r[:foo].should == 84
    r.class.should == Hash
  end
end

describe "Hash#transform_values!" do
  before :each do
    @hash = { a: 1, b: 2, c: 3 }
    @initial_pairs = @hash.dup
  end

  it "returns self" do
    @hash.transform_values!(&:succ).should equal(@hash)
  end

  it "updates self as transformed values with the given block" do
    @hash.transform_values!(&:succ)
    @hash.should == { a: 2, b: 3, c: 4 }
  end

  it "partially modifies the contents if we broke from the block" do
    @hash.transform_values! do |v|
      break if v == 3
      100 + v
    end
    @hash.should == { a: 101, b: 102, c: 3}
  end

  context "when no block is given" do
    it "returns a sized Enumerator" do
      enumerator = @hash.transform_values!
      enumerator.should be_an_instance_of(Enumerator)
      enumerator.size.should == @hash.size
      enumerator.each(&:succ)
      @hash.should == { a: 2, b: 3, c: 4 }
    end
  end

  describe "on frozen instance" do
    before :each do
      @hash.freeze
    end

    it "raises a #{frozen_error_class} on an empty hash" do
      ->{ {}.freeze.transform_values!(&:succ) }.should raise_error(frozen_error_class)
    end

    it "keeps pairs and raises a #{frozen_error_class}" do
      ->{ @hash.transform_values!(&:succ) }.should raise_error(frozen_error_class)
      @hash.should == @initial_pairs
    end

    context "when no block is given" do
      it "does not raise an exception" do
        @hash.transform_values!.should be_an_instance_of(Enumerator)
      end
    end
  end
end
