require_relative '../../../spec_helper'
require 'net/http'
require_relative 'fixtures/classes'

describe "Net::HTTPHeader#set_content_type" do
  describe "when passed type, params" do
    before :each do
      @headers = NetHTTPHeaderSpecs::Example.new
    end

    it "sets the 'Content-Type' header entry based on the passed type and params" do
      @headers.set_content_type("text/html")
      @headers["Content-Type"].should == "text/html"

      @headers.set_content_type("text/html", "charset" => "utf-8")
      @headers["Content-Type"].should == "text/html; charset=utf-8"

      @headers.set_content_type("text/html", "charset" => "utf-8", "rubyspec" => "rocks")
      @headers["Content-Type"].split(/; /).sort.should == %w[charset=utf-8 rubyspec=rocks text/html]
    end
  end
end
