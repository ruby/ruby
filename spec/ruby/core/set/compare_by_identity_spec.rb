require_relative '../../spec_helper'

describe "Set#compare_by_identity" do
  it "compares its members by identity" do
    a = "a"
    b1 = "b"
    b2 = b1.dup

    set = Set.new
    set.compare_by_identity
    set.merge([a, a, b1, b2])
    set.to_a.sort.should == [a, b1, b2].sort
  end

  it "causes future comparisons on the receiver to be made by identity" do
    elt = [1]
    set = Set.new
    set << elt
    set.member?(elt.dup).should be_true
    set.compare_by_identity
    set.member?(elt.dup).should be_false
  end

  it "rehashes internally so that old members can be looked up" do
    set = Set.new
    (1..10).each { |k| set << k }
    o = Object.new
    def o.hash; 123; end
    set << o
    set.compare_by_identity
    set.member?(o).should be_true
  end

  it "returns self" do
    set = Set.new
    result = set.compare_by_identity
    result.should equal(set)
  end

  it "is idempotent and has no effect on an already compare_by_identity set" do
    set = Set.new.compare_by_identity
    set << :foo
    set.compare_by_identity.should equal(set)
    set.should.compare_by_identity?
    set.to_a.should == [:foo]
  end

  it "uses the semantics of BasicObject#equal? to determine members identity" do
    :a.equal?(:a).should == true
    Set.new.compare_by_identity.merge([:a, :a]).to_a.should == [:a]

    ary1 = [1]
    ary2 = [1]
    ary1.equal?(ary2).should == false
    Set.new.compare_by_identity.merge([ary1, ary2]).to_a.sort.should == [ary1, ary2].sort
  end

  it "uses #equal? semantics, but doesn't actually call #equal? to determine identity" do
    set = Set.new.compare_by_identity
    obj = mock("equal")
    obj.should_not_receive(:equal?)
    set << :foo
    set << obj
    set.to_a.should == [:foo, obj]
  end

  it "does not call #hash on members" do
    elt = mock("element")
    elt.should_not_receive(:hash)
    set = Set.new.compare_by_identity
    set << elt
    set.member?(elt).should be_true
  end

  it "regards #dup'd objects as having different identities" do
    a1 = "a"
    a2 = a1.dup

    set = Set.new.compare_by_identity
    set.merge([a1, a2])
    set.to_a.sort.should == [a1, a2].sort
  end

  it "regards #clone'd objects as having different identities" do
    a1 = "a"
    a2 = a1.clone

    set = Set.new.compare_by_identity
    set.merge([a1, a2])
    set.to_a.sort.should == [a1, a2].sort
  end

  ruby_version_is "3.5" do
    it "raises a FrozenError on frozen sets" do
      set = Set.new.freeze
      -> {
        set.compare_by_identity
      }.should raise_error(FrozenError, "can't modify frozen Set: #<Set: {}>")
    end
  end

  ruby_version_is ""..."3.5" do
    it "raises a FrozenError on frozen sets" do
      set = Set.new.freeze
      -> {
        set.compare_by_identity
      }.should raise_error(FrozenError, /frozen Hash/)
    end
  end

  it "persists over #dups" do
    set = Set.new.compare_by_identity
    set << :a
    set_dup = set.dup
    set_dup.should == set
    set_dup << :a
    set_dup.to_a.should == [:a]
  end

  it "persists over #clones" do
    set = Set.new.compare_by_identity
    set << :a
    set_clone = set.clone
    set_clone.should == set
    set_clone << :a
    set_clone.to_a.should == [:a]
  end

  it "is not equal to set what does not compare by identity" do
    Set.new([1, 2]).should == Set.new([1, 2])
    Set.new([1, 2]).should_not == Set.new([1, 2]).compare_by_identity
  end
end

describe "Set#compare_by_identity?" do
  it "returns false by default" do
    Set.new.should_not.compare_by_identity?
  end

  it "returns true once #compare_by_identity has been invoked on self" do
    set = Set.new
    set.compare_by_identity
    set.should.compare_by_identity?
  end

  it "returns true when called multiple times on the same set" do
    set = Set.new
    set.compare_by_identity
    set.should.compare_by_identity?
    set.should.compare_by_identity?
    set.should.compare_by_identity?
  end
end
