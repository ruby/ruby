require_relative '../../../spec_helper'

ruby_version_is ""..."4.0" do
  require 'cgi'

  describe "CGI::Cookie#secure" do
    before :each do
      @cookie = CGI::Cookie.new("test-cookie")
    end

    it "returns whether self is a secure cookie or not" do
      @cookie.secure = true
      @cookie.secure.should == true

      @cookie.secure = false
      @cookie.secure.should == false
    end
  end

  describe "CGI::Cookie#secure= when passed true" do
    before :each do
      @cookie = CGI::Cookie.new("test-cookie")
    end

    it "returns true" do
      (@cookie.secure = true).should == true
    end

    it "sets self to a secure cookie" do
      @cookie.secure = true
      @cookie.secure.should == true
    end
  end

  describe "CGI::Cookie#secure= when passed false" do
    before :each do
      @cookie = CGI::Cookie.new("test-cookie")
    end

    it "returns false" do
      (@cookie.secure = false).should == false
    end

    it "sets self to a non-secure cookie" do
      @cookie.secure = false
      @cookie.secure.should == false
    end
  end

  describe "CGI::Cookie#secure= when passed Object" do
    before :each do
      @cookie = CGI::Cookie.new("test-cookie")
    end

    it "does not change self's secure value" do
      @cookie.secure = false

      @cookie.secure = Object.new
      @cookie.secure.should == false

      @cookie.secure = "Test"
      @cookie.secure.should == false

      @cookie.secure = true

      @cookie.secure = Object.new
      @cookie.secure.should == true

      @cookie.secure = "Test"
      @cookie.secure.should == true
    end
  end
end
