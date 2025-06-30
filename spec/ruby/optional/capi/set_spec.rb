require_relative 'spec_helper'

load_extension("set")

describe "C-API Set function" do
  before :each do
    @s = CApiSetSpecs.new
  end

  ruby_version_is "3.5" do
    describe "rb_set_foreach" do
      it "calls function with each element and arg" do
        a = []
        @s.rb_set_foreach(Set[1, 2], 3) {|*args| a.concat(args) }
        a.should == [1, 3, 2, 3]
      end

      it "respects function return value" do
        a = []
        @s.rb_set_foreach(Set[1, 2], 3) do |*args|
          a.concat(args)
          false
        end
        a.should == [1, 3]
      end
    end

    describe "rb_set_new" do
      it "returns a new set" do
        @s.rb_set_new.should == Set[]
      end
    end

    describe "rb_set_new_capa" do
      it "returns a new set" do
        @s.rb_set_new_capa(3).should == Set[]
      end
    end

    describe "rb_set_lookup" do
      it "returns whether the element is in the set" do
        set = Set[1]
        @s.rb_set_lookup(set, 1).should == true
        @s.rb_set_lookup(set, 2).should == false
      end
    end

    describe "rb_set_add" do
      it "adds element to set" do
        set = Set[]
        @s.rb_set_add(set, 1).should == true
        set.should == Set[1]
        @s.rb_set_add(set, 2).should == true
        set.should == Set[1, 2]
      end

      it "returns false if element is already in set" do
        set = Set[1]
        @s.rb_set_add(set, 1).should == false
        set.should == Set[1]
      end
    end

    describe "rb_set_clear" do
      it "empties and returns self" do
        set = Set[1]
        @s.rb_set_clear(set).should equal(set)
        set.should == Set[]
      end
    end

    describe "rb_set_delete" do
      it "removes element from set" do
        set = Set[1, 2]
        @s.rb_set_delete(set, 1).should == true
        set.should == Set[2]
        @s.rb_set_delete(set, 2).should == true
        set.should == Set[]
      end

      it "returns false if element is not already in set" do
        set = Set[2]
        @s.rb_set_delete(set, 1).should == false
        set.should == Set[2]
      end
    end

    describe "rb_set_size" do
      it "returns number of elements in set" do
        @s.rb_set_size(Set[]).should == 0
        @s.rb_set_size(Set[1]).should == 1
        @s.rb_set_size(Set[1,2]).should == 2
      end
    end
  end
end
