require File.dirname(__FILE__) + '/../../spec_helper'
require 'mspec/runner/mspec'
require 'mspec/runner/filters/match'
require 'mspec/runner/filters/tag'

describe TagFilter, "#load" do
  before :each do
    @match = double("match filter").as_null_object
    @filter = TagFilter.new :include, "tag", "key"
    @tag = SpecTag.new "tag(comment):description"
    MSpec.stub(:read_tags).and_return([@tag])
    MSpec.stub(:register)
  end

  it "loads tags from the tag file" do
    MSpec.should_receive(:read_tags).with(["tag", "key"]).and_return([])
    @filter.load
  end


  it "registers itself with MSpec for the :include action" do
    filter = TagFilter.new(:include)
    MSpec.should_receive(:register).with(:include, filter)
    filter.load
  end

  it "registers itself with MSpec for the :exclude action" do
    filter = TagFilter.new(:exclude)
    MSpec.should_receive(:register).with(:exclude, filter)
    filter.load
  end
end

describe TagFilter, "#unload" do
  before :each do
    @filter = TagFilter.new :include, "tag", "key"
    @tag = SpecTag.new "tag(comment):description"
    MSpec.stub(:read_tags).and_return([@tag])
    MSpec.stub(:register)
  end

  it "unregisters itself" do
    @filter.load
    MSpec.should_receive(:unregister).with(:include, @filter)
    @filter.unload
  end
end

describe TagFilter, "#register" do
  before :each do
    MSpec.stub(:register)
  end

  it "registers itself with MSpec for the :load, :unload actions" do
    filter = TagFilter.new(nil)
    MSpec.should_receive(:register).with(:load, filter)
    MSpec.should_receive(:register).with(:unload, filter)
    filter.register
  end
end

describe TagFilter, "#unregister" do
  before :each do
    MSpec.stub(:unregister)
  end

  it "unregisters itself with MSpec for the :load, :unload actions" do
    filter = TagFilter.new(nil)
    MSpec.should_receive(:unregister).with(:load, filter)
    MSpec.should_receive(:unregister).with(:unload, filter)
    filter.unregister
  end
end

describe TagFilter, "#===" do
  before :each do
    @filter = TagFilter.new nil, "tag", "key"
    @tag = SpecTag.new "tag(comment):description"
    MSpec.stub(:read_tags).and_return([@tag])
    MSpec.stub(:register)
    @filter.load
  end

  it "returns true if the argument matches any of the descriptions" do
    @filter.===('description').should == true
  end

  it "returns false if the argument matches none of the descriptions" do
    @filter.===('descriptionA').should == false
    @filter.===('adescription').should == false
  end
end
