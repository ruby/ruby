require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Struct#to_s" do
  it "returns a string representation showing members and values" do
    car = StructClasses::Car.new('Ford', 'Ranger')
    car.to_s.should == '#<struct StructClasses::Car make="Ford", model="Ranger", year=nil>'
  end

  it "returns a string representation without the class name for anonymous structs" do
    Struct.new(:a).new("").to_s.should == '#<struct a="">'
  end

  it "returns a string representation without the class name for structs nested in anonymous classes" do
    c = Class.new
    c.class_eval <<~DOC
      class Foo < Struct.new(:a); end
    DOC

    c::Foo.new("").to_s.should == '#<struct a="">'
  end

  it "returns a string representation without the class name for structs nested in anonymous modules" do
    m = Module.new
    m.module_eval <<~DOC
      class Foo < Struct.new(:a); end
    DOC

    m::Foo.new("").to_s.should == '#<struct a="">'
  end

  it "does not call #name method" do
    struct = StructClasses::StructWithOverriddenName.new("")
    struct.to_s.should == '#<struct StructClasses::StructWithOverriddenName a="">'
  end

  it "does not call #name method when struct is anonymous" do
    struct = Struct.new(:a)
    def struct.name; "A"; end

    struct.new("").to_s.should == '#<struct a="">'
  end
end
