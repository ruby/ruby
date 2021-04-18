require_relative '../../spec_helper'

describe "Hash#transform_keys" do
  before :each do
    @hash = { a: 1, b: 2, c: 3 }
  end

  it "returns new hash" do
    ret = @hash.transform_keys(&:succ)
    ret.should_not equal(@hash)
    ret.should be_an_instance_of(Hash)
  end

  it "sets the result as transformed keys with the given block" do
    @hash.transform_keys(&:succ).should ==  { b: 1, c: 2, d: 3 }
  end

  it "keeps last pair if new keys conflict" do
    @hash.transform_keys { |_| :a }.should == { a: 3 }
  end

  it "makes both hashes to share values" do
    value = [1, 2, 3]
    new_hash = { a: value }.transform_keys(&:upcase)
    new_hash[:A].should equal(value)
  end

  context "when no block is given" do
    it "returns a sized Enumerator" do
      enumerator = @hash.transform_keys
      enumerator.should be_an_instance_of(Enumerator)
      enumerator.size.should == @hash.size
      enumerator.each(&:succ).should == { b: 1, c: 2, d: 3 }
    end
  end

  it "returns a Hash instance, even on subclasses" do
    klass = Class.new(Hash)
    h = klass.new
    h[:foo] = 42
    r = h.transform_keys{|v| :"x#{v}"}
    r.keys.should == [:xfoo]
    r.class.should == Hash
  end
end

describe "Hash#transform_keys!" do
  before :each do
    @hash = { a: 1, b: 2, c: 3, d: 4 }
    @initial_pairs = @hash.dup
  end

  it "returns self" do
    @hash.transform_keys!(&:succ).should equal(@hash)
  end

  it "updates self as transformed values with the given block" do
    @hash.transform_keys!(&:to_s)
    @hash.should == { 'a' => 1, 'b' => 2, 'c' => 3, 'd' => 4 }
  end

  # https://bugs.ruby-lang.org/issues/14380
  ruby_version_is ""..."2.5.1" do
    it "does not prevent conflicts between new keys and old ones" do
      @hash.transform_keys!(&:succ)
      @hash.should == { e: 1 }
    end
  end

  ruby_version_is "2.5.1" do
    it "prevents conflicts between new keys and old ones" do
      @hash.transform_keys!(&:succ)
      @hash.should == { b: 1, c: 2, d: 3, e: 4 }
    end
  end

  ruby_version_is ""..."2.5.1" do
    it "partially modifies the contents if we broke from the block" do
      @hash.transform_keys! do |v|
        break if v == :c
        v.succ
      end
      @hash.should == { c: 1, d: 4 }
    end
  end

  ruby_version_is "2.5.1"..."3.0.2" do
    it "returns the processed keys if we broke from the block" do
      @hash.transform_keys! do |v|
        break if v == :c
        v.succ
      end
      @hash.should == { b: 1, c: 2 }
    end
  end

  ruby_version_is "3.0.2" do
    it "returns the processed keys and non evaluated keys if we broke from the block" do
      @hash.transform_keys! do |v|
        break if v == :c
        v.succ
      end
      @hash.should == { b: 1, c: 2, d: 4 }
    end
  end

  it "keeps later pair if new keys conflict" do
    @hash.transform_keys! { |_| :a }.should == { a: 4 }
  end

  context "when no block is given" do
    it "returns a sized Enumerator" do
      enumerator = @hash.transform_keys!
      enumerator.should be_an_instance_of(Enumerator)
      enumerator.size.should == @hash.size
      enumerator.each(&:upcase).should == { A: 1, B: 2, C: 3, D: 4 }
    end
  end

  describe "on frozen instance" do
    before :each do
      @hash.freeze
    end

    it "raises a FrozenError on an empty hash" do
      ->{ {}.freeze.transform_keys!(&:upcase) }.should raise_error(FrozenError)
    end

    it "keeps pairs and raises a FrozenError" do
      ->{ @hash.transform_keys!(&:upcase) }.should raise_error(FrozenError)
      @hash.should == @initial_pairs
    end

    context "when no block is given" do
      it "does not raise an exception" do
        @hash.transform_keys!.should be_an_instance_of(Enumerator)
      end
    end
  end
end
