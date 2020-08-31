require_relative '../../spec_helper'

describe "Kernel#=~" do
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

  it "returns nil matching any object" do
    o = Object.new

    suppress_warning do
      (o =~ /Object/).should   be_nil
      (o =~ 'Object').should   be_nil
      (o =~ Object).should     be_nil
      (o =~ Object.new).should be_nil
      (o =~ nil).should        be_nil
      (o =~ true).should       be_nil
    end
  end

  ruby_version_is "2.6"..."3.0" do
    it "is deprecated" do
      -> do
        Object.new =~ /regexp/
      end.should complain(/deprecated Object#=~ is called on Object/, verbose: true)
    end
  end
end
