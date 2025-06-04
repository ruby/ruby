require_relative '../../spec_helper'

ruby_version_is ""..."3.5" do
  require 'cgi'
end
ruby_version_is "3.5" do
  require 'cgi/escape'
end

describe "CGI.unescapeElement when passed String, elements, ..." do
  it "unescapes only the tags of the passed elements in the passed String" do
    res = CGI.unescapeElement("&lt;BR&gt;&lt;A HREF=&quot;url&quot;&gt;&lt;/A&gt;", "A", "IMG")
    res.should == '&lt;BR&gt;<A HREF="url"></A>'

    res = CGI.unescapeElement('&lt;BR&gt;&lt;A HREF=&quot;url&quot;&gt;&lt;/A&gt;', ["A", "IMG"])
    res.should == '&lt;BR&gt;<A HREF="url"></A>'
  end

  it "is case-insensitive" do
    res = CGI.unescapeElement("&lt;BR&gt;&lt;A HREF=&quot;url&quot;&gt;&lt;/A&gt;", "a", "img")
    res.should == '&lt;BR&gt;<A HREF="url"></A>'

    res = CGI.unescapeElement("&lt;br&gt;&lt;a href=&quot;url&quot;&gt;&lt;/a&gt;", "A", "IMG")
    res.should == '&lt;br&gt;<a href="url"></a>'
  end
end
