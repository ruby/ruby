require_relative '../../spec_helper'
require_relative 'fixtures/classes'

ruby_version_is "3.4" do
  describe 'Enumerable#uniq_map' do
    it 'returns an enumerator when no block given' do
      EnumerableSpecs::Empty.new.uniq_map.should be_an_instance_of(Enumerator)
    end

    it 'returns an empty array if there are no elements' do
      EnumerableSpecs::Empty.new.uniq_map { true }.should == []
    end

    it 'returns an array that contains only unique elements' do
      [0, 1, 1].to_enum.uniq_map { |i| i }.should == [0, 1]
      [0, 1, 1].to_enum.uniq_map(&:to_s).should == ['0', '1']
      [0, 1, 1].to_enum.uniq_map { |i| i * 2 }.should == [0, 2]
      (0..5).uniq_map { |i| i.odd? ? i * 2 : i }.should == [0, 2, 6, 4, 10]
      {foo: 0, bar: 1, baz: 1}.uniq_map { |_key, value| value * 2 }.should == [0, 2]
    end

    it 'returns the same result as calling #uniq on #map' do
      a_map_uniq = [0, 1, 1].to_enum.map { |i| i * 2 }.uniq
      a_uniq_map = [0, 1, 1].to_enum.uniq_map { |i| i * 2 }
      a_map_uniq.should == a_uniq_map

      h_map_uniq = {foo: 0, bar: 1, baz: 1}.map { |_key, value| value * 2 }.uniq
      h_uniq_map = {foo: 0, bar: 1, baz: 1}.uniq_map { |_key, value| value * 2 }
      h_map_uniq.should == h_uniq_map
    end

    it "uses eql? semantics" do
      [1.0, 1].to_enum.uniq_map { |i| i }.should == [1.0, 1]
    end

    it "compares elements first with hash" do
      x = mock('0')
      x.should_receive(:hash).at_least(1).and_return(0)
      y = mock('0')
      y.should_receive(:hash).at_least(1).and_return(0)

      [x, y].to_enum.uniq_map { |i| i }.should == [x, y]
    end

    it "does not compare elements with different hash codes via eql?" do
      x = mock('0')
      x.should_not_receive(:eql?)
      y = mock('1')
      y.should_not_receive(:eql?)

      x.should_receive(:hash).at_least(1).and_return(0)
      y.should_receive(:hash).at_least(1).and_return(1)

      [x, y].to_enum.uniq_map { |i| i }.should == [x, y]
    end

    it "compares elements with matching hash codes with #eql?" do
      a = Array.new(2) do
        obj = mock('0')
        obj.should_receive(:hash).at_least(1).and_return(0)

        def obj.eql?(o)
          false
        end

        obj
      end

      a.uniq_map { |i| i }.should == a

      a = Array.new(2) do
        obj = mock('0')
        obj.should_receive(:hash).at_least(1).and_return(0)

        def obj.eql?(o)
          true
        end

        obj
      end

      a.to_enum.uniq_map { |i| i }.size.should == 1
    end

    context 'when yielded with multiple arguments' do
      before :each do
        @enum = Object.new.to_enum
        class << @enum
          def each
            yield 0, 'foo'
            yield 1, 'FOO'
            yield 2, 'bar'
          end
        end
      end

      it 'returns all yield arguments as an array' do
        @enum.uniq_map { |_, label| label.downcase }.should == ['foo', 'bar']
      end
    end
  end
end
