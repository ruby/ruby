require 'spec_helper'
require 'mspec/expectations/expectations'
require 'mspec/matchers'

describe BlockingMatcher do
  it 'matches when a Proc blocks the caller' do
    BlockingMatcher.new.matches?(proc { sleep }).should == true
  end

  it 'does not match when a Proc does not block the caller' do
    BlockingMatcher.new.matches?(proc { 1 }).should == false
  end
end
