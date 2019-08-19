require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Enumerable#one?" do
  describe "when passed a block" do
    it "returns true if block returns true once" do
      [:a, :b, :c].one? { |s| s == :a }.should be_true
    end

    it "returns false if the block returns true more than once" do
      [:a, :b, :c].one? { |s| s == :a || s == :b }.should be_false
    end

    it "returns false if the block only returns false" do
      [:a, :b, :c].one? { |s| s == :d }.should be_false
    end

    it "gathers initial args as elements when each yields multiple" do
      # This spec doesn't spec what it says it does
      multi = EnumerableSpecs::YieldsMulti.new
      multi.one? {|e| e == 1 }.should be_true
    end

    it "yields multiple arguments when each yields multiple" do
      multi = EnumerableSpecs::YieldsMulti.new
      yielded = []
      multi.one? {|e, i| yielded << [e, i] }
      yielded.should == [[1, 2], [3, 4]]
    end

    ruby_version_is "2.5" do
      describe "given a pattern argument" do
        # This spec should be replaced by more extensive ones
        it "returns true iff none match that pattern" do
          EnumerableSpecs::Numerous.new.one?(Integer).should == false
          [nil, false, true].one?(NilClass).should == true
        end
      end
    end
  end

  describe "when not passed a block" do
    it "returns true if only one element evaluates to true" do
      [false, nil, true].one?.should be_true
    end

    it "returns false if two elements evaluate to true" do
      [false, :value, nil, true].one?.should be_false
    end

    it "returns false if all elements evaluate to false" do
      [false, nil, false].one?.should be_false
    end

    it "gathers whole arrays as elements when each yields multiple" do
      multi = EnumerableSpecs::YieldsMultiWithSingleTrue.new
      multi.one?.should be_false
    end
  end
end
