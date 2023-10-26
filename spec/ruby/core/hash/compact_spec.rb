require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Hash#compact" do
  before :each do
    @hash = { truthy: true, false: false, nil: nil, nil => true }
    @initial_pairs = @hash.dup
    @compact = { truthy: true, false: false, nil => true }
  end

  it "returns new object that rejects pair has nil value" do
    ret = @hash.compact
    ret.should_not equal(@hash)
    ret.should == @compact
  end

  it "keeps own pairs" do
    @hash.compact
    @hash.should == @initial_pairs
  end

  ruby_version_is '3.3' do
    it "retains the default value" do
      hash = Hash.new(1)
      hash.compact.default.should == 1
      hash[:a] = 1
      hash.compact.default.should == 1
    end

    it "retains the default_proc" do
      pr = proc { |h, k| h[k] = [] }
      hash = Hash.new(&pr)
      hash.compact.default_proc.should == pr
      hash[:a] = 1
      hash.compact.default_proc.should == pr
    end

    it "retains compare_by_identity_flag" do
      hash = {}.compare_by_identity
      hash.compact.compare_by_identity?.should == true
      hash[:a] = 1
      hash.compact.compare_by_identity?.should == true
    end
  end
end

describe "Hash#compact!" do
  before :each do
    @hash = { truthy: true, false: false, nil: nil, nil => true }
    @initial_pairs = @hash.dup
    @compact = { truthy: true, false: false, nil => true }
  end

  it "returns self" do
    @hash.compact!.should equal(@hash)
  end

  it "rejects own pair has nil value" do
    @hash.compact!
    @hash.should == @compact
  end

  context "when each pair does not have nil value" do
    before :each do
      @hash.compact!
    end

    it "returns nil" do
      @hash.compact!.should be_nil
    end
  end

  describe "on frozen instance" do
    before :each do
      @hash.freeze
    end

    it "keeps pairs and raises a FrozenError" do
      ->{ @hash.compact! }.should raise_error(FrozenError)
      @hash.should == @initial_pairs
    end
  end
end
