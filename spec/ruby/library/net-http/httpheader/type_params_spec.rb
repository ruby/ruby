require_relative '../../../spec_helper'
require 'net/http'
require_relative 'fixtures/classes'

describe "Net::HTTPHeader#type_params" do
  before :each do
    @headers = NetHTTPHeaderSpecs::Example.new
  end

  it "returns additional 'Content-Type' information as a Hash" do
    @headers["Content-Type"] = "text/html;charset=utf-8"
    @headers.type_params.should == {"charset" => "utf-8"}

    @headers["Content-Type"] = "text/html; charset=utf-8; rubyspec=rocks"
    @headers.type_params.should == {"charset" => "utf-8", "rubyspec" => "rocks"}
  end

  it "returns an empty Hash when no additional 'Content-Type' information is set" do
    @headers.type_params.should == {}

    @headers["Content-Type"] = "text/html"
    @headers.type_params.should == {}
  end
end
