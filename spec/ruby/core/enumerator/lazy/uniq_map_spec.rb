require_relative '../../../spec_helper'
require_relative 'fixtures/classes'

ruby_version_is "3.4" do
  describe 'Enumerator::Lazy#uniq_map' do
    context 'when yielded with an argument' do
      before :each do
        @lazy = [0, 1, 0, 1].to_enum.lazy.uniq_map { |i| (i * 2).to_s }
      end

      it 'returns a lazy enumerator' do
        @lazy.should be_an_instance_of(Enumerator::Lazy)
        @lazy.force.should == ["0", "2"]
      end

      it 'sets the size to nil' do
        @lazy.size.should == nil
      end
    end

    context 'when yielded with multiple arguments' do
      before :each do
        enum = Object.new.to_enum
        class << enum
          def each
            yield 0, 'foo'
            yield 1, 'FOO'
            yield 2, 'bar'
          end
        end
        @lazy = enum.lazy
      end

      it 'returns all yield arguments as an array' do
        @lazy.uniq_map { |_, label| label.downcase }.force.should == ['foo', 'bar']
      end
    end

    it "works with an infinite enumerable" do
      s = 0..Float::INFINITY
      s.lazy.uniq_map { |i| i }.first(100).should == s.first(100).uniq_map { |i| i }
    end
  end
end
