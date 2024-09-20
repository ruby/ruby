# -*- encoding: utf-8 -*-
require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative '../../shared/string/start_with'

describe "String#start_with?" do
  it_behaves_like :start_with, :to_s

  # Here and not in the shared examples because this is invalid as a Symbol
  it "matches part of a character with the same part" do
    "\xA9".should.start_with?("\xA9") # A9 is not a character head for UTF-8
  end

  ruby_version_is ""..."3.3" do
    it "does not check we are matching only part of a character" do
      "\xe3\x81\x82".size.should == 1
      "\xe3\x81\x82".should.start_with?("\xe3")
    end
  end

  ruby_version_is "3.3" do # #19784
    it "checks we are matching only part of a character" do
      "\xe3\x81\x82".size.should == 1
      "\xe3\x81\x82".should_not.start_with?("\xe3")
    end
  end
end
