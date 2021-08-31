require_relative '../spec_helper'

# webrick is no longer in stdlib in Ruby 3+
ruby_version_is ""..."3.0" do
  require "webrick"
  require "stringio"
  require "net/http"

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
