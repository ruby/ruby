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

  ruby_version_is "3.3" do
    it 'returns a Hash with Symbol keys when symbolize_names is provided a true value' do
      /(?<a>.)(?<b>.)?/.match('0').named_captures(symbolize_names: true).should == { a: '0', b: nil }
      /(?<a>.)(?<b>.)?/.match('0').named_captures(symbolize_names: "truly").should == { a: '0', b: nil }
    end

    it 'returns a Hash with String keys when symbolize_names is provided a false value' do
      /(?<a>.)(?<b>.)?/.match('02').named_captures(symbolize_names: false).should == { 'a' => '0', 'b' => '2' }
      /(?<a>.)(?<b>.)?/.match('02').named_captures(symbolize_names: nil).should == { 'a' => '0', 'b' => '2' }
    end
  end
end
