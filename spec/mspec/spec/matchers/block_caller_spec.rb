require 'spec_helper'
require 'mspec/expectations/expectations'
require 'mspec/matchers'

RSpec.describe BlockingMatcher do
  it 'matches when a Proc blocks the caller' do
    expect(BlockingMatcher.new.matches?(proc { sleep })).to eq(true)
  end

  it 'does not match when a Proc does not block the caller' do
    expect(BlockingMatcher.new.matches?(proc { 1 })).to eq(false)
  end
end
