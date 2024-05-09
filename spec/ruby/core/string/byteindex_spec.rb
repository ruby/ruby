# -*- encoding: utf-8 -*-
require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "String#byteindex with Regexp" do
  ruby_version_is "3.2" do
    it "always clear $~" do
      "a".byteindex(/a/)
      $~.should_not == nil

      string = "blablabla"
      string.byteindex(/bla/, string.bytesize + 1)
      $~.should == nil
    end
  end
end
