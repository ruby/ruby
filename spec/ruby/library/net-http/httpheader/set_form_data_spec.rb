require_relative '../../../spec_helper'
require 'net/http'
require_relative 'fixtures/classes'

describe "Net::HTTPHeader#set_form_data" do
  before :each do
    @headers = NetHTTPHeaderSpecs::Example.new
  end

  describe "when passed params" do
    it "automatically set the 'Content-Type' to 'application/x-www-form-urlencoded'" do
      @headers.set_form_data("cmd" => "search", "q" => "ruby", "max" => "50")
      @headers["Content-Type"].should == "application/x-www-form-urlencoded"
    end

    it "sets self's body based on the passed form parameters" do
      @headers.set_form_data("cmd" => "search", "q" => "ruby", "max" => "50")
      @headers.body.split("&").sort.should == ["cmd=search", "max=50", "q=ruby"]
    end
  end

  describe "when passed params, separator" do
    it "sets self's body based on the passed form parameters and the passed separator" do
      @headers.set_form_data({"cmd" => "search", "q" => "ruby", "max" => "50"}, "&")
      @headers.body.split("&").sort.should == ["cmd=search", "max=50", "q=ruby"]

      @headers.set_form_data({"cmd" => "search", "q" => "ruby", "max" => "50"}, ";")
      @headers.body.split(";").sort.should == ["cmd=search", "max=50", "q=ruby"]
    end
  end
end
