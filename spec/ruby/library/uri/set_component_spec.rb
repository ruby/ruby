require_relative '../../spec_helper'
require 'uri'

#TODO: make this more BDD
describe "URI#select" do
  it "conforms to the MatzRuby tests" do
    uri = URI.parse('http://foo:bar@baz')
    (uri.user = 'oof').should == 'oof'
    uri.to_s.should == 'http://oof:bar@baz'
    (uri.password = 'rab').should == 'rab'
    uri.to_s.should == 'http://oof:rab@baz'
    (uri.userinfo = 'foo').should == 'foo'
    uri.to_s.should == 'http://foo:rab@baz'
    (uri.userinfo = ['foo', 'bar']).should == ['foo', 'bar']
    uri.to_s.should == 'http://foo:bar@baz'
    (uri.userinfo = ['foo']).should == ['foo']
    uri.to_s.should == 'http://foo:bar@baz'
    (uri.host = 'zab').should == 'zab'
    uri.to_s.should == 'http://foo:bar@zab'
    (uri.port = 8080).should == 8080
    uri.to_s.should == 'http://foo:bar@zab:8080'
    (uri.path = '/').should == '/'
    uri.to_s.should == 'http://foo:bar@zab:8080/'
    (uri.query = 'a=1').should == 'a=1'
    uri.to_s.should == 'http://foo:bar@zab:8080/?a=1'
    (uri.fragment = 'b123').should == 'b123'
    uri.to_s.should == 'http://foo:bar@zab:8080/?a=1#b123'

    uri = URI.parse('http://example.com')
    -> { uri.password = 'bar' }.should raise_error(URI::InvalidURIError)
    uri.userinfo = 'foo:bar'
    uri.to_s.should == 'http://foo:bar@example.com'
    -> { uri.registry = 'bar' }.should raise_error(URI::InvalidURIError)
    -> { uri.opaque = 'bar' }.should raise_error(URI::InvalidURIError)

    uri = URI.parse('mailto:foo@example.com')
    -> { uri.user = 'bar' }.should raise_error(URI::InvalidURIError)
    -> { uri.password = 'bar' }.should raise_error(URI::InvalidURIError)
    -> { uri.userinfo = ['bar', 'baz'] }.should raise_error(URI::InvalidURIError)
    -> { uri.host = 'bar' }.should raise_error(URI::InvalidURIError)
    -> { uri.port = 'bar' }.should raise_error(URI::InvalidURIError)
    -> { uri.path = 'bar' }.should raise_error(URI::InvalidURIError)
    -> { uri.query = 'bar' }.should raise_error(URI::InvalidURIError)
  end
end
