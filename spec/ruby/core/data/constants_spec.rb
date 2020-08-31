require_relative '../../spec_helper'

describe "Data" do
  before :each do
    if Warning.respond_to?(:[])
      @deprecated = Warning[:deprecated]
      Warning[:deprecated] = true
    end
  end

  after :each do
    if Warning.respond_to?(:[])
      Warning[:deprecated] = @deprecated
    end
  end

  it "is a subclass of Object" do
    suppress_warning do
      Data.superclass.should == Object
    end
  end

  ruby_version_is "2.5" do
    it "is deprecated" do
      -> { Data }.should complain(/constant ::Data is deprecated/)
    end
  end
end
