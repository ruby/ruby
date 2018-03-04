require_relative '../../spec_helper'

ruby_version_is '2.5' do
  describe 'Thread#fetch' do
    describe 'with 2 arguments' do
      it 'returns the value of the fiber-local variable if value has been assigned' do
        th = Thread.new { Thread.current[:cat] = 'meow' }
        th.join
        th.fetch(:cat, true).should == 'meow'
      end

      it "returns the default value if fiber-local variable hasn't been assigned" do
        th = Thread.new {}
        th.join
        th.fetch(:cat, true).should == true
      end
    end

    describe 'with 1 argument' do
      it 'raises a KeyError when the Thread does not have a fiber-local variable of the same name' do
        th = Thread.new {}
        th.join
        -> { th.fetch(:cat) }.should raise_error(KeyError)
      end

      it 'returns the value of the fiber-local variable if value has been assigned' do
        th = Thread.new { Thread.current[:cat] = 'meow' }
        th.join
        th.fetch(:cat).should == 'meow'
      end
    end

    it 'raises an ArgumentError when not passed one or two arguments' do
      -> { Thread.current.fetch() }.should raise_error(ArgumentError)
      -> { Thread.current.fetch(1, 2, 3) }.should raise_error(ArgumentError)
    end
  end
end
