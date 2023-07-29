require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/uniq_map'

ruby_version_is "3.4" do
  describe "Array#uniq_map" do
    @method = :uniq_map
    @value_to_return = -> e { e }
    it_behaves_like :array_uniq_map, :uniq_map
    it_behaves_like :array_collect, :uniq_map

    it "returns an array with no duplicates" do
      ["a", "a", "b", "b", "c"].uniq_map { |i| i }.should == ["a", "b", "c"]
      ["a", "a", "b", "b", "c"].uniq_map { |i| i * 2 }.should == ["aa", "bb", "cc"]
    end
  end

  describe "Array#uniq_map!" do
    @method = :uniq_map!
    @value_to_return = -> e { e }
    it_behaves_like :array_uniq_map, :uniq_map!
    it_behaves_like :array_collect_b, :uniq_map!

    it "modifies the array in place with no duplicates" do
      a = [ "a", "a", "b", "b", "c" ]
      b = a.dup

      a.uniq_map! { |i| i }
      a.should == ["a", "b", "c"]

      b.uniq_map! { |i| i * 2 }
      b.should == ["aa", "bb", "cc"]
    end

    it "returns self" do
      a = [ "a", "a", "b", "b", "c" ]
      a.should equal(a.uniq_map! { |i| i })
    end
  end
end
