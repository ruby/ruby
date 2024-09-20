require_relative '../../spec_helper'

describe 'Set' do
  ruby_version_is '3.2' do
    it 'is available without explicit requiring' do
      output = ruby_exe(<<~RUBY, options: '--disable-gems', args: '2>&1')
        puts Set.new([1, 2, 3])
      RUBY
      output.chomp.should == "#<Set: {1, 2, 3}>"
    end
  end
end
