# encoding: utf-8
require_relative 'spec_helper'

load_extension('st')

describe "st hash table function" do
  before :each do
    @s = CApiStSpecs.new
  end

  describe "st_init_numtable" do
    it "initializes without error" do
      @s.st_init_numtable.should == 0
    end
  end

  describe "st_init_numtable_with_size" do
    it "initializes without error" do
      @s.st_init_numtable_with_size.should == 0
    end
  end

  describe "st_insert" do
    it "returns size 1 after insert" do
      @s.st_insert.should == 1
    end
  end

  describe "st_foreach" do
    it "iterates over each pair of key and value" do
      @s.st_foreach.should == 7
    end
  end

  describe "st_lookup" do
    it "returns the expected value" do
      @s.st_lookup.should == 42
    end
  end

end
