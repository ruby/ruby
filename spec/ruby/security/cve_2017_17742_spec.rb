require_relative '../spec_helper'

require "webrick"
require "stringio"
require "net/http"

guard -> {
  ruby_version_is "2.3.7"..."2.4" or
  ruby_version_is "2.4.4"..."2.5" or
  ruby_version_is "2.5.1"
} do
  describe "WEBrick" do
    describe "resists CVE-2017-17742" do
      it "for a response splitting headers" do
        config = WEBrick::Config::HTTP
        res = WEBrick::HTTPResponse.new config
        res['X-header'] = "malicious\r\nCookie: hack"
        io = StringIO.new
        res.send_response io
        io.rewind
        res = Net::HTTPResponse.read_new(Net::BufferedIO.new(io))
        res.code.should == '500'
        io.string.should_not =~ /hack/
      end

      it "for a response splitting cookie headers" do
        user_input = "malicious\r\nCookie: hack"
        config = WEBrick::Config::HTTP
        res = WEBrick::HTTPResponse.new config
        res.cookies << WEBrick::Cookie.new('author', user_input)
        io = StringIO.new
        res.send_response io
        io.rewind
        res = Net::HTTPResponse.read_new(Net::BufferedIO.new(io))
        res.code.should == '500'
        io.string.should_not =~ /hack/
      end
    end
  end
end
