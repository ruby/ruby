require_relative '../../spec_helper'

describe 'String#+@' do
  it 'returns an unfrozen copy of a frozen String' do
    input  = 'foo'.freeze
    output = +input

    output.should_not.frozen?
    output.should == 'foo'
  end

  it 'returns self if the String is not frozen' do
    input  = 'foo'
    output = +input

    output.equal?(input).should == true
  end

  it 'returns mutable copy despite freeze-magic-comment in file' do
    ruby_exe(fixture(__FILE__, "freeze_magic_comment.rb")).should == 'mutable'
  end
end
