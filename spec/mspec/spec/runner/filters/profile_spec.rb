require File.dirname(__FILE__) + '/../../spec_helper'
require 'mspec/runner/mspec'
require 'mspec/runner/filters/profile'

RSpec.describe ProfileFilter, "#find" do
  before :each do
    @filter = ProfileFilter.new nil
    allow(File).to receive(:exist?).and_return(false)
    @file = "rails.yaml"
  end

  it "attempts to locate the file through the expanded path name" do
    expect(File).to receive(:expand_path).with(@file).and_return(@file)
    expect(File).to receive(:exist?).with(@file).and_return(true)
    expect(@filter.find(@file)).to eq(@file)
  end

  it "attempts to locate the file in 'spec/profiles'" do
    path = File.join "spec/profiles", @file
    expect(File).to receive(:exist?).with(path).and_return(true)
    expect(@filter.find(@file)).to eq(path)
  end

  it "attempts to locate the file in 'spec'" do
    path = File.join "spec", @file
    expect(File).to receive(:exist?).with(path).and_return(true)
    expect(@filter.find(@file)).to eq(path)
  end

  it "attempts to locate the file in 'profiles'" do
    path = File.join "profiles", @file
    expect(File).to receive(:exist?).with(path).and_return(true)
    expect(@filter.find(@file)).to eq(path)
  end

  it "attempts to locate the file in '.'" do
    path = File.join ".", @file
    expect(File).to receive(:exist?).with(path).and_return(true)
    expect(@filter.find(@file)).to eq(path)
  end
end

RSpec.describe ProfileFilter, "#parse" do
  before :each do
    @filter = ProfileFilter.new nil
    @file = File.open(File.dirname(__FILE__) + "/b.yaml", "r")
  end

  after :each do
    @file.close
  end

  it "creates a Hash of the contents of the YAML file" do
    expect(@filter.parse(@file)).to eq({
      "B." => ["b", "bb"],
      "B::C#" => ["b!", "b=", "b?", "-", "[]", "[]="]
    })
  end
end

RSpec.describe ProfileFilter, "#load" do
  before :each do
    @filter = ProfileFilter.new nil
    @files = [
      File.dirname(__FILE__) + "/a.yaml",
      File.dirname(__FILE__) + "/b.yaml"
      ]
  end

  it "generates a composite hash from multiple YAML files" do
    expect(@filter.load(*@files)).to eq({
      "A#"    => ["a", "aa"],
      "B."    => ["b", "bb"],
      "B::C#" => ["b!", "b=", "b?", "-", "[]", "[]="]
    })
  end
end

RSpec.describe ProfileFilter, "#===" do
  before :each do
    @filter = ProfileFilter.new nil
    allow(@filter).to receive(:load).and_return({ "A#" => ["[]=", "a", "a!", "a?", "aa="]})
    @filter.send :initialize, nil
  end

  it "returns true if the spec description is for a method in the profile" do
    expect(@filter.===("The A#[]= method")).to eq(true)
    expect(@filter.===("A#a returns")).to eq(true)
    expect(@filter.===("A#a! replaces")).to eq(true)
    expect(@filter.===("A#a? returns")).to eq(true)
    expect(@filter.===("A#aa= raises")).to eq(true)
  end

  it "returns false if the spec description is for a method not in the profile" do
    expect(@filter.===("The A#[] method")).to eq(false)
    expect(@filter.===("B#a returns")).to eq(false)
    expect(@filter.===("A.a! replaces")).to eq(false)
    expect(@filter.===("AA#a? returns")).to eq(false)
    expect(@filter.===("A#aa raises")).to eq(false)
  end
end

RSpec.describe ProfileFilter, "#register" do
  it "registers itself with MSpec for the designated action list" do
    filter = ProfileFilter.new :include
    expect(MSpec).to receive(:register).with(:include, filter)
    filter.register
  end
end

RSpec.describe ProfileFilter, "#unregister" do
  it "unregisters itself with MSpec for the designated action list" do
    filter = ProfileFilter.new :exclude
    expect(MSpec).to receive(:unregister).with(:exclude, filter)
    filter.unregister
  end
end
