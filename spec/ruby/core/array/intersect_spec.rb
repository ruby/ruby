require_relative '../../spec_helper'

describe 'Array#intersect?' do
  ruby_version_is '3.1' do # https://bugs.ruby-lang.org/issues/15198
    describe 'when at least one element in two Arrays is the same' do
      it 'returns true' do
        [1, 2].intersect?([2, 3]).should == true
      end
    end

    describe 'when there are no elements in common between two Arrays' do
      it 'returns false' do
        [1, 2].intersect?([3, 4]).should == false
      end
    end
  end
end
