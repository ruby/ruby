require_relative '../../../spec_helper'
require_relative 'fixtures/common'
require 'cgi'

describe "CGI::HtmlExtension#frameset" do
  before :each do
    @html = CGISpecs.cgi_new("html4Fr")
  end

  it "initializes the HTML Generation methods for the Frameset version of HTML4" do
    @html.frameset.should == "<FRAMESET></FRAMESET>"
    @html.frameset { "link text" }.should == "<FRAMESET>link text</FRAMESET>"
  end
end
