require File.dirname(__FILE__) + '/../../spec_helper'
require 'mspec/runner/mspec'
require 'mspec/runner/filters/profile'

describe ProfileFilter, "#find" do
  before :each do
    @filter = ProfileFilter.new nil
    File.stub(:exist?).and_return(false)
    @file = "rails.yaml"
  end

  it "attempts to locate the file through the expanded path name" do
    File.should_receive(:expand_path).with(@file).and_return(@file)
    File.should_receive(:exist?).with(@file).and_return(true)
    @filter.find(@file).should == @file
  end

  it "attempts to locate the file in 'spec/profiles'" do
    path = File.join "spec/profiles", @file
    File.should_receive(:exist?).with(path).and_return(true)
    @filter.find(@file).should == path
  end

  it "attempts to locate the file in 'spec'" do
    path = File.join "spec", @file
    File.should_receive(:exist?).with(path).and_return(true)
    @filter.find(@file).should == path
  end

  it "attempts to locate the file in 'profiles'" do
    path = File.join "profiles", @file
    File.should_receive(:exist?).with(path).and_return(true)
    @filter.find(@file).should == path
  end

  it "attempts to locate the file in '.'" do
    path = File.join ".", @file
    File.should_receive(:exist?).with(path).and_return(true)
    @filter.find(@file).should == path
  end
end

describe ProfileFilter, "#parse" do
  before :each do
    @filter = ProfileFilter.new nil
    @file = File.open(File.dirname(__FILE__) + "/b.yaml", "r")
  end

  after :each do
    @file.close
  end

  it "creates a Hash of the contents of the YAML file" do
    @filter.parse(@file).should == {
      "B." => ["b", "bb"],
      "B::C#" => ["b!", "b=", "b?", "-", "[]", "[]="]
    }
  end
end

describe ProfileFilter, "#load" do
  before :each do
    @filter = ProfileFilter.new nil
    @files = [
      File.dirname(__FILE__) + "/a.yaml",
      File.dirname(__FILE__) + "/b.yaml"
      ]
  end

  it "generates a composite hash from multiple YAML files" do
    @filter.load(*@files).should == {
      "A#"    => ["a", "aa"],
      "B."    => ["b", "bb"],
      "B::C#" => ["b!", "b=", "b?", "-", "[]", "[]="]
    }
  end
end

describe ProfileFilter, "#===" do
  before :each do
    @filter = ProfileFilter.new nil
    @filter.stub(:load).and_return({ "A#" => ["[]=", "a", "a!", "a?", "aa="]})
    @filter.send :initialize, nil
  end

  it "returns true if the spec description is for a method in the profile" do
    @filter.===("The A#[]= method").should == true
    @filter.===("A#a returns").should == true
    @filter.===("A#a! replaces").should == true
    @filter.===("A#a? returns").should == true
    @filter.===("A#aa= raises").should == true
  end

  it "returns false if the spec description is for a method not in the profile" do
    @filter.===("The A#[] method").should == false
    @filter.===("B#a returns").should == false
    @filter.===("A.a! replaces").should == false
    @filter.===("AA#a? returns").should == false
    @filter.===("A#aa raises").should == false
  end
end

describe ProfileFilter, "#register" do
  it "registers itself with MSpec for the designated action list" do
    filter = ProfileFilter.new :include
    MSpec.should_receive(:register).with(:include, filter)
    filter.register
  end
end

describe ProfileFilter, "#unregister" do
  it "unregisters itself with MSpec for the designated action list" do
    filter = ProfileFilter.new :exclude
    MSpec.should_receive(:unregister).with(:exclude, filter)
    filter.unregister
  end
end
