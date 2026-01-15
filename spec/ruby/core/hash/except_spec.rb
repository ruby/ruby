require_relative '../../spec_helper'

describe "Hash#except" do
  before :each do
    @hash = { a: 1, b: 2, c: 3 }
  end

  it "returns a new duplicate hash without arguments" do
    ret = @hash.except
    ret.should_not equal(@hash)
    ret.should == @hash
  end

  it "returns a hash without the requested subset" do
    @hash.except(:c, :a).should == { b: 2 }
  end

  it "ignores keys not present in the original hash" do
    @hash.except(:a, :chunky_bacon).should == { b: 2, c: 3 }
  end

  it "does not retain the default value" do
    h = Hash.new(1)
    h.except(:a).default.should be_nil
    h[:a] = 1
    h.except(:a).default.should be_nil
  end

  it "does not retain the default_proc" do
    pr = proc { |h, k| h[k] = [] }
    h = Hash.new(&pr)
    h.except(:a).default_proc.should be_nil
    h[:a] = 1
    h.except(:a).default_proc.should be_nil
  end

  it "retains compare_by_identity flag" do
    h = { a: 9, c: 4 }.compare_by_identity
    h2 = h.except(:a)
    h2.compare_by_identity?.should == true
  end
end
