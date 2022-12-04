require File.dirname(__FILE__) + '/../../spec_helper'
require 'mspec/runner/mspec'
require 'mspec/runner/filters/match'
require 'mspec/runner/filters/tag'

RSpec.describe TagFilter, "#load" do
  before :each do
    @match = double("match filter").as_null_object
    @filter = TagFilter.new :include, "tag", "key"
    @tag = SpecTag.new "tag(comment):description"
    allow(MSpec).to receive(:read_tags).and_return([@tag])
    allow(MSpec).to receive(:register)
  end

  it "loads tags from the tag file" do
    expect(MSpec).to receive(:read_tags).with(["tag", "key"]).and_return([])
    @filter.load
  end


  it "registers itself with MSpec for the :include action" do
    filter = TagFilter.new(:include)
    expect(MSpec).to receive(:register).with(:include, filter)
    filter.load
  end

  it "registers itself with MSpec for the :exclude action" do
    filter = TagFilter.new(:exclude)
    expect(MSpec).to receive(:register).with(:exclude, filter)
    filter.load
  end
end

RSpec.describe TagFilter, "#unload" do
  before :each do
    @filter = TagFilter.new :include, "tag", "key"
    @tag = SpecTag.new "tag(comment):description"
    allow(MSpec).to receive(:read_tags).and_return([@tag])
    allow(MSpec).to receive(:register)
  end

  it "unregisters itself" do
    @filter.load
    expect(MSpec).to receive(:unregister).with(:include, @filter)
    @filter.unload
  end
end

RSpec.describe TagFilter, "#register" do
  before :each do
    allow(MSpec).to receive(:register)
  end

  it "registers itself with MSpec for the :load, :unload actions" do
    filter = TagFilter.new(nil)
    expect(MSpec).to receive(:register).with(:load, filter)
    expect(MSpec).to receive(:register).with(:unload, filter)
    filter.register
  end
end

RSpec.describe TagFilter, "#unregister" do
  before :each do
    allow(MSpec).to receive(:unregister)
  end

  it "unregisters itself with MSpec for the :load, :unload actions" do
    filter = TagFilter.new(nil)
    expect(MSpec).to receive(:unregister).with(:load, filter)
    expect(MSpec).to receive(:unregister).with(:unload, filter)
    filter.unregister
  end
end

RSpec.describe TagFilter, "#===" do
  before :each do
    @filter = TagFilter.new nil, "tag", "key"
    @tag = SpecTag.new "tag(comment):description"
    allow(MSpec).to receive(:read_tags).and_return([@tag])
    allow(MSpec).to receive(:register)
    @filter.load
  end

  it "returns true if the argument matches any of the descriptions" do
    expect(@filter.===('description')).to eq(true)
  end

  it "returns false if the argument matches none of the descriptions" do
    expect(@filter.===('descriptionA')).to eq(false)
    expect(@filter.===('adescription')).to eq(false)
  end
end
