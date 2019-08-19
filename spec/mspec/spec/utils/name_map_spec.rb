require 'spec_helper'
require 'mspec/utils/name_map'

module NameMapSpecs
  class A
    A = self

    def self.a; end
    def a; end
    def c; end

    class B
      def b; end
    end
  end

  class Error
  end

  class Fixnum
    def f; end
  end

  def self.n; end
  def n; end
end

describe NameMap, "#exception?" do
  before :each do
    @map = NameMap.new
  end

  it "returns true if the constant is Errno" do
    @map.exception?("Errno").should == true
  end

  it "returns true if the constant is a kind of Exception" do
    @map.exception?("Errno::EBADF").should == true
    @map.exception?("LoadError").should == true
    @map.exception?("SystemExit").should == true
  end

  it "returns false if the constant is not a kind of Exception" do
    @map.exception?("NameMapSpecs::Error").should == false
    @map.exception?("NameMapSpecs").should == false
  end

  it "returns false if the constant does not exist" do
    @map.exception?("Nonexistent").should == false
  end
end

describe NameMap, "#class_or_module" do
  before :each do
    @map = NameMap.new true
  end

  it "returns the constant specified by the string" do
    @map.class_or_module("NameMapSpecs").should == NameMapSpecs
  end

  it "returns the constant specified by the 'A::B' string" do
    @map.class_or_module("NameMapSpecs::A").should == NameMapSpecs::A
  end

  it "returns nil if the constant is not a class or module" do
    @map.class_or_module("Float::MAX").should == nil
  end

  it "returns nil if the constant is in the set of excluded constants" do
    excluded = %w[
      MSpecScript
      MkSpec
      NameMap
    ]

    excluded.each do |const|
      @map.class_or_module(const).should == nil
    end
  end

  it "returns nil if the constant does not exist" do
    @map.class_or_module("Heaven").should == nil
    @map.class_or_module("Hell").should == nil
    @map.class_or_module("Bush::Brain").should == nil
  end
end

describe NameMap, "#dir_name" do
  before :each do
    @map = NameMap.new
  end

  it "returns a directory name from the base name and constant" do
    @map.dir_name("NameMapSpecs", 'spec/core').should == 'spec/core/namemapspecs'
  end

  it "returns a directory name from the components in the constants name" do
    @map.dir_name("NameMapSpecs::A", 'spec').should == 'spec/namemapspecs/a'
    @map.dir_name("NameMapSpecs::A::B", 'spec').should == 'spec/namemapspecs/a/b'
  end

  it "returns a directory name without 'class' for constants like TrueClass" do
    @map.dir_name("TrueClass", 'spec').should == 'spec/true'
    @map.dir_name("FalseClass", 'spec').should == 'spec/false'
  end

  it "returns 'exception' for the directory name of any Exception subclass" do
    @map.dir_name("SystemExit", 'spec').should == 'spec/exception'
    @map.dir_name("Errno::EBADF", 'spec').should == 'spec/exception'
  end

  it "returns 'class' for Class" do
    @map.dir_name("Class", 'spec').should == 'spec/class'
  end
end

# These specs do not cover all the mappings, but only describe how the
# name is derived when the hash item maps to a single value, a hash with
# a specific item, or a hash with a :default item.
describe NameMap, "#file_name" do
  before :each do
    @map = NameMap.new
  end

  it "returns the name of the spec file based on the constant and method" do
    @map.file_name("[]=", "Array").should == "element_set_spec.rb"
  end

  it "returns the name of the spec file based on the special entry for the method" do
    @map.file_name("~", "Regexp").should == "match_spec.rb"
    @map.file_name("~", "Integer").should == "complement_spec.rb"
  end

  it "returns the name of the spec file based on the default entry for the method" do
    @map.file_name("<<", "NameMapSpecs").should == "append_spec.rb"
  end

  it "uses the last component of the constant to look up the method name" do
    @map.file_name("^", "NameMapSpecs::Integer").should == "bit_xor_spec.rb"
  end
end

describe NameMap, "#namespace" do
  before :each do
    @map = NameMap.new
  end

  it "prepends the module to the constant name" do
    @map.namespace("SubModule", Integer).should == "SubModule::Integer"
  end

  it "does not prepend Object, Class, or Module to the constant name" do
    @map.namespace("Object", String).should == "String"
    @map.namespace("Module", Integer).should == "Integer"
    @map.namespace("Class", Float).should == "Float"
  end
end

describe NameMap, "#map" do
  before :each do
    @map = NameMap.new
  end

  it "flattens an object hierarchy into a single Hash" do
    @map.map({}, [NameMapSpecs]).should == {
      "NameMapSpecs."         => ["n"],
      "NameMapSpecs#"         => ["n"],
      "NameMapSpecs::A."      => ["a"],
      "NameMapSpecs::A#"      => ["a", "c"],
      "NameMapSpecs::A::B#"   => ["b"],
      "NameMapSpecs::Fixnum#" => ["f"]
    }
  end
end
