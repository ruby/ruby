require_relative '../../../spec_helper'
require 'cgi'
require_relative 'fixtures/common'

describe "CGI::HtmlExtension#password_field" do
  before :each do
    @html = CGISpecs.cgi_new
  end

  describe "when passed no arguments" do
    it "returns an password-'input'-element without a name" do
      output = @html.password_field
      output.should equal_element("INPUT", {"NAME" => "", "TYPE" => "password", "SIZE" => "40"}, "", not_closed: true)
    end

    it "ignores a passed block" do
      output = @html.password_field { "test" }
      output.should equal_element("INPUT", {"NAME" => "", "TYPE" => "password", "SIZE" => "40"}, "", not_closed: true)
    end
  end

  describe "when passed name" do
    it "returns an password-'input'-element with the passed name" do
      output = @html.password_field("test")
      output.should equal_element("INPUT", {"NAME" => "test", "TYPE" => "password", "SIZE" => "40"}, "", not_closed: true)
    end

    it "ignores a passed block" do
      output = @html.password_field("test") { "test" }
      output.should equal_element("INPUT", {"NAME" => "test", "TYPE" => "password", "SIZE" => "40"}, "", not_closed: true)
    end
  end

  describe "when passed name, value" do
    it "returns an password-'input'-element with the passed name and value" do
      output = @html.password_field("test", "some value")
      output.should equal_element("INPUT", {"NAME" => "test", "TYPE" => "password", "VALUE" => "some value", "SIZE" => "40"}, "", not_closed: true)
    end

    it "ignores a passed block" do
      output = @html.password_field("test", "some value") { "test" }
      output.should equal_element("INPUT", {"NAME" => "test", "TYPE" => "password", "VALUE" => "some value", "SIZE" => "40"}, "", not_closed: true)
    end
  end

  describe "when passed name, value, size" do
    it "returns an password-'input'-element with the passed name, value and size" do
      output = @html.password_field("test", "some value", 60)
      output.should equal_element("INPUT", {"NAME" => "test", "TYPE" => "password", "VALUE" => "some value", "SIZE" => "60"}, "", not_closed: true)
    end

    it "ignores a passed block" do
      output = @html.password_field("test", "some value", 60) { "test" }
      output.should equal_element("INPUT", {"NAME" => "test", "TYPE" => "password", "VALUE" => "some value", "SIZE" => "60"}, "", not_closed: true)
    end
  end

  describe "when passed name, value, size, maxlength" do
    it "returns an password-'input'-element with the passed name, value, size and maxlength" do
      output = @html.password_field("test", "some value", 60, 12)
      output.should equal_element("INPUT", {"NAME" => "test", "TYPE" => "password", "VALUE" => "some value", "SIZE" => "60", "MAXLENGTH" => 12}, "", not_closed: true)
    end

    it "ignores a passed block" do
      output = @html.password_field("test", "some value", 60, 12) { "test" }
      output.should equal_element("INPUT", {"NAME" => "test", "TYPE" => "password", "VALUE" => "some value", "SIZE" => "60", "MAXLENGTH" => 12}, "", not_closed: true)
    end
  end

  describe "when passed Hash" do
    it "returns a checkbox-'input'-element using the passed Hash for attributes" do
      output = @html.password_field("NAME" => "test", "VALUE" => "some value")
      output.should equal_element("INPUT", { "NAME" => "test", "VALUE" => "some value", "TYPE" => "password" }, "", not_closed: true)

      output = @html.password_field("TYPE" => "hidden")
      output.should equal_element("INPUT", {"TYPE" => "password"}, "", not_closed: true)
    end

    it "ignores a passed block" do
      output = @html.password_field("NAME" => "test", "VALUE" => "some value") { "test" }
      output.should equal_element("INPUT", { "NAME" => "test", "VALUE" => "some value", "TYPE" => "password" }, "", not_closed: true)
    end
  end
end
