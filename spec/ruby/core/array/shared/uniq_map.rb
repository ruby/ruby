require_relative '../../../spec_helper'
require_relative '../fixtures/classes'
require_relative 'collect'

ruby_version_is "3.4" do
  describe :array_uniq_map, shared: true do
    it "compares elements returned by the block" do
      a = [1, 2, 3, 4]
      a.send(@method) { |x| x >= 3 ? x : 0 }.should == [0, 3, 4]
    end

    it "yields items in order" do
      a = [1, 2, 3]
      yielded = []
      a.send(@method) { |i| yielded << i; i }
      yielded.should == a
    end

    it "properly handles recursive arrays" do
      empty = ArraySpecs.empty_recursive_array
      empty.send(@method) { |i| i }.should == [empty]

      array = ArraySpecs.recursive_array
      array.send(@method) { |i| i }.should == [1, 'two', 3.0, array]
    end

    it "handles nil and false like any other values" do
      [nil, false, 42].send(@method) { |i| i }.should == [nil, false, 42]
      [false, nil, 42].send(@method) { |i| i }.should == [false, nil, 42]
    end

    it "uses eql? semantics" do
      [1.0, 1].send(@method) { |i| i }.should == [1.0, 1]
    end

    it "compares elements first with hash" do
      x = mock('0')
      x.should_receive(:hash).at_least(1).and_return(0)
      y = mock('0')
      y.should_receive(:hash).at_least(1).and_return(0)

      [x, y].send(@method) { |i| i }.should == [x, y]
    end

    it "does not compare elements with different hash codes via eql?" do
      x = mock('0')
      x.should_not_receive(:eql?)
      y = mock('1')
      y.should_not_receive(:eql?)

      x.should_receive(:hash).at_least(1).and_return(0)
      y.should_receive(:hash).at_least(1).and_return(1)

      [x, y].send(@method) { |i| i }.should == [x, y]
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

      a.send(@method) { |i| i }.should == a

      a = Array.new(2) do
        obj = mock('0')
        obj.should_receive(:hash).at_least(1).and_return(0)

        def obj.eql?(o)
          true
        end

        obj
      end

      a.send(@method) { |i| i }.size.should == 1
    end

    it "properly handles an identical item even when its #eql? isn't reflexive" do
      x = mock('x')
      x.should_receive(:hash).at_least(1).and_return(42)
      x.stub!(:eql?).and_return(false)

      [x, x].send(@method) { |i| i }.should == [x]
    end


    describe "given an array of BasicObject subclasses that define ==, eql?, and hash" do
      it "filters equivalent elements using those definitions" do
        basic = Class.new(BasicObject) do
          attr_reader :x

          def initialize(x)
            @x = x
          end

          def ==(rhs)
            @x == rhs.x
          end
          alias_method :eql?, :==

          def hash
            @x.hash
          end
        end

        a = [basic.new(3), basic.new(2), basic.new(1), basic.new(4), basic.new(1), basic.new(2), basic.new(3)]
        a.send(@method) { |i| i }.should == [basic.new(3), basic.new(2), basic.new(1), basic.new(4)]
      end
    end
  end
end
