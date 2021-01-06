require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/accessor'

describe "Struct#hash" do

  it "returns the same integer for structs with the same content" do
    [StructClasses::Ruby.new("1.8.6", "PPC"),
     StructClasses::Car.new("Hugo", "Foo", "1972")].each do |stc|
      stc.hash.should == stc.dup.hash
      stc.hash.should be_kind_of(Integer)
    end
  end

  it "returns the same value if structs are #eql?" do
    car = StructClasses::Car.new("Honda", "Accord", "1998")
    similar_car = StructClasses::Car.new("Honda", "Accord", "1998")
    car.should eql(similar_car)
    car.hash.should == similar_car.hash
  end

  it "returns different hashes for structs with different values" do
    s1 = StructClasses::Ruby.new('2.7.0', 'linux')
    s2 = StructClasses::Ruby.new('2.7.0', 'macos')
    s1.hash.should_not == s2.hash
  end

  it "returns different hashes for structs with different values when using keyword_init: true" do
    key = :"1 non symbol member"
    struct_class = Struct.new(key, keyword_init: true)
    t1 = struct_class.new(key => 1)
    t2 = struct_class.new(key => 2)
    t1.hash.should_not == t2.hash
  end

  it "allows for overriding methods in an included module" do
    mod = Module.new do
      def hash
        "different"
      end
    end
    s = Struct.new(:arg) do
      include mod
    end
    s.new.hash.should == "different"
  end

  it "returns the same hash for recursive structs" do
    car = StructClasses::Car.new("Honda", "Accord", "1998")
    similar_car = StructClasses::Car.new("Honda", "Accord", "1998")
    car[:make] = car
    similar_car[:make] = car
    car.hash.should == similar_car.hash
    # This is because car.eql?(similar_car).
    # Objects that are eql? must return the same hash.
    # See the Struct#eql? specs
  end

  it_behaves_like :struct_accessor, :hash
end
