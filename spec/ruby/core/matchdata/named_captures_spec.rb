require_relative '../../spec_helper'

describe 'MatchData#named_captures' do
  it 'returns a Hash that has captured name and the matched string pairs' do
    /(?<a>.)(?<b>.)?/.match('0').named_captures.should == { 'a' => '0', 'b' => nil }
  end

  it 'prefers later captures' do
    /\A(?<a>.)(?<b>.)(?<b>.)(?<a>.)\z/.match('0123').named_captures.should == { 'a' => '3', 'b' => '2' }
  end

  it 'returns the latest matched capture, even if a later one that does not match exists' do
    /\A(?<a>.)(?<b>.)(?<b>.)(?<a>.)?\z/.match('012').named_captures.should == { 'a' => '0', 'b' => '2' }
  end
end
