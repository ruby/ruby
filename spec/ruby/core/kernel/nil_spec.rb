require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe 'Kernel#nil?' do
  it 'returns false' do
    Object.should_not.nil?
    Object.new.should_not.nil?
    ''.should_not.nil?
    [].should_not.nil?
    {}.should_not.nil?
  end
end
