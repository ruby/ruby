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

RSpec.describe NameMap, "#exception?" do
  before :each do
    @map = NameMap.new
  end

  it "returns true if the constant is Errno" do
    expect(@map.exception?("Errno")).to eq(true)
  end

  it "returns true if the constant is a kind of Exception" do
    expect(@map.exception?("Errno::EBADF")).to eq(true)
    expect(@map.exception?("LoadError")).to eq(true)
    expect(@map.exception?("SystemExit")).to eq(true)
  end

  it "returns false if the constant is not a kind of Exception" do
    expect(@map.exception?("NameMapSpecs::Error")).to eq(false)
    expect(@map.exception?("NameMapSpecs")).to eq(false)
  end

  it "returns false if the constant does not exist" do
    expect(@map.exception?("Nonexistent")).to eq(false)
  end
end

RSpec.describe NameMap, "#class_or_module" do
  before :each do
    @map = NameMap.new true
  end

  it "returns the constant specified by the string" do
    expect(@map.class_or_module("NameMapSpecs")).to eq(NameMapSpecs)
  end

  it "returns the constant specified by the 'A::B' string" do
    expect(@map.class_or_module("NameMapSpecs::A")).to eq(NameMapSpecs::A)
  end

  it "returns nil if the constant is not a class or module" do
    expect(@map.class_or_module("Float::MAX")).to eq(nil)
  end

  it "returns nil if the constant is in the set of excluded constants" do
    excluded = %w[
      MSpecScript
      MkSpec
      NameMap
    ]

    excluded.each do |const|
      expect(@map.class_or_module(const)).to eq(nil)
    end
  end

  it "returns nil if the constant does not exist" do
    expect(@map.class_or_module("Heaven")).to eq(nil)
    expect(@map.class_or_module("Hell")).to eq(nil)
    expect(@map.class_or_module("Bush::Brain")).to eq(nil)
  end
end

RSpec.describe NameMap, "#dir_name" do
  before :each do
    @map = NameMap.new
  end

  it "returns a directory name from the base name and constant" do
    expect(@map.dir_name("NameMapSpecs", 'spec/core')).to eq('spec/core/namemapspecs')
  end

  it "returns a directory name from the components in the constants name" do
    expect(@map.dir_name("NameMapSpecs::A", 'spec')).to eq('spec/namemapspecs/a')
    expect(@map.dir_name("NameMapSpecs::A::B", 'spec')).to eq('spec/namemapspecs/a/b')
  end

  it "returns a directory name without 'class' for constants like TrueClass" do
    expect(@map.dir_name("TrueClass", 'spec')).to eq('spec/true')
    expect(@map.dir_name("FalseClass", 'spec')).to eq('spec/false')
  end

  it "returns 'exception' for the directory name of any Exception subclass" do
    expect(@map.dir_name("SystemExit", 'spec')).to eq('spec/exception')
    expect(@map.dir_name("Errno::EBADF", 'spec')).to eq('spec/exception')
  end

  it "returns 'class' for Class" do
    expect(@map.dir_name("Class", 'spec')).to eq('spec/class')
  end
end

# These specs do not cover all the mappings, but only describe how the
# name is derived when the hash item maps to a single value, a hash with
# a specific item, or a hash with a :default item.
RSpec.describe NameMap, "#file_name" do
  before :each do
    @map = NameMap.new
  end

  it "returns the name of the spec file based on the constant and method" do
    expect(@map.file_name("[]=", "Array")).to eq("element_set_spec.rb")
  end

  it "returns the name of the spec file based on the special entry for the method" do
    expect(@map.file_name("~", "Regexp")).to eq("match_spec.rb")
    expect(@map.file_name("~", "Integer")).to eq("complement_spec.rb")
  end

  it "returns the name of the spec file based on the default entry for the method" do
    expect(@map.file_name("<<", "NameMapSpecs")).to eq("append_spec.rb")
  end

  it "uses the last component of the constant to look up the method name" do
    expect(@map.file_name("^", "NameMapSpecs::Integer")).to eq("bit_xor_spec.rb")
  end
end

RSpec.describe NameMap, "#namespace" do
  before :each do
    @map = NameMap.new
  end

  it "prepends the module to the constant name" do
    expect(@map.namespace("SubModule", Integer)).to eq("SubModule::Integer")
  end

  it "does not prepend Object, Class, or Module to the constant name" do
    expect(@map.namespace("Object", String)).to eq("String")
    expect(@map.namespace("Module", Integer)).to eq("Integer")
    expect(@map.namespace("Class", Float)).to eq("Float")
  end
end

RSpec.describe NameMap, "#map" do
  before :each do
    @map = NameMap.new
  end

  it "flattens an object hierarchy into a single Hash" do
    expect(@map.map({}, [NameMapSpecs])).to eq({
      "NameMapSpecs."         => ["n"],
      "NameMapSpecs#"         => ["n"],
      "NameMapSpecs::A."      => ["a"],
      "NameMapSpecs::A#"      => ["a", "c"],
      "NameMapSpecs::A::B#"   => ["b"],
      "NameMapSpecs::Fixnum#" => ["f"]
    })
  end
end
