require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Hash#replace" do
  it "replaces the contents of self with other" do
    h = { a: 1, b: 2 }
    h.replace(c: -1, d: -2).should equal(h)
    h.should == { c: -1, d: -2 }
  end

  it "tries to convert the passed argument to a hash using #to_hash" do
    obj = mock('{1=>2,3=>4}')
    obj.should_receive(:to_hash).and_return({ 1 => 2, 3 => 4 })

    h = {}
    h.replace(obj)
    h.should == { 1 => 2, 3 => 4 }
  end

  it "calls to_hash on hash subclasses" do
    h = {}
    h.replace(HashSpecs::ToHashHash[1 => 2])
    h.should == { 1 => 2 }
  end

  it "does not retain the default value" do
    hash = Hash.new(1)
    hash.replace(b: 2).default.should be_nil
  end

  it "transfers the default value of an argument" do
    hash = Hash.new(1)
    { a: 1 }.replace(hash).default.should == 1
  end

  it "does not retain the default_proc" do
    pr = proc { |h, k| h[k] = [] }
    hash = Hash.new(&pr)
    hash.replace(b: 2).default_proc.should be_nil
  end

  it "transfers the default_proc of an argument" do
    pr = proc { |h, k| h[k] = [] }
    hash = Hash.new(&pr)
    { a: 1 }.replace(hash).default_proc.should == pr
  end

  it "does not call the default_proc of an argument" do
    hash_a = Hash.new { |h, k| k * 5 }
    hash_b = Hash.new(-> { raise "Should not invoke lambda" })
    hash_a.replace(hash_b)
    hash_a.default.should == hash_b.default
  end

  it "transfers compare_by_identity flag of an argument" do
    h = { a: 1, c: 3 }
    h2 = { b: 2, d: 4 }.compare_by_identity
    h.replace(h2)
    h.compare_by_identity?.should == true
  end

  it "does not retain compare_by_identity flag" do
    h = { a: 1, c: 3 }.compare_by_identity
    h.replace(b: 2, d: 4)
    h.compare_by_identity?.should == false
  end

  it "raises a FrozenError if called on a frozen instance that would not be modified" do
    -> do
      HashSpecs.frozen_hash.replace(HashSpecs.frozen_hash)
    end.should raise_error(FrozenError)
  end

  it "raises a FrozenError if called on a frozen instance that is modified" do
    -> do
      HashSpecs.frozen_hash.replace(HashSpecs.empty_frozen_hash)
    end.should raise_error(FrozenError)
  end
end
