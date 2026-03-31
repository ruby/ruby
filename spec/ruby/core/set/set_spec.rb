require_relative '../../spec_helper'

describe 'Set' do
  it 'is available without explicit requiring' do
    output = ruby_exe(<<~RUBY, options: '--disable-gems', args: '2>&1')
      puts Set.new([1, 2, 3]).to_a.inspect
    RUBY
    output.chomp.should == "[1, 2, 3]"
  end
end
