require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/enumeratorized'

describe "Enumerable#each_slice" do
  before :each do
    @enum = EnumerableSpecs::Numerous.new(7,6,5,4,3,2,1)
    @sliced = [[7,6,5],[4,3,2],[1]]
  end

  it "passes element groups to the block" do
    acc = []
    @enum.each_slice(3){|g| acc << g}
    acc.should == @sliced
  end

  it "raises an ArgumentError if there is not a single parameter > 0" do
    ->{ @enum.each_slice(0){}    }.should raise_error(ArgumentError)
    ->{ @enum.each_slice(-2){}   }.should raise_error(ArgumentError)
    ->{ @enum.each_slice{}       }.should raise_error(ArgumentError)
    ->{ @enum.each_slice(2,2){}  }.should raise_error(ArgumentError)
    ->{ @enum.each_slice(0)      }.should raise_error(ArgumentError)
    ->{ @enum.each_slice(-2)     }.should raise_error(ArgumentError)
    ->{ @enum.each_slice         }.should raise_error(ArgumentError)
    ->{ @enum.each_slice(2,2)    }.should raise_error(ArgumentError)
  end

  it "tries to convert n to an Integer using #to_int" do
    acc = []
    @enum.each_slice(3.3){|g| acc << g}
    acc.should == @sliced

    obj = mock('to_int')
    obj.should_receive(:to_int).and_return(3)
    @enum.each_slice(obj){|g| break g.length}.should == 3
  end

  it "works when n is >= full length" do
    full = @enum.to_a
    acc = []
    @enum.each_slice(full.length){|g| acc << g}
    acc.should == [full]
    acc = []
    @enum.each_slice(full.length+1){|g| acc << g}
    acc.should == [full]
  end

  it "yields only as much as needed" do
    cnt = EnumerableSpecs::EachCounter.new(1, 2, :stop, "I said stop!", :got_it)
    cnt.each_slice(2) {|g| break 42 if g[0] == :stop }.should == 42
    cnt.times_yielded.should == 4
  end

  it "returns an enumerator if no block" do
    e = @enum.each_slice(3)
    e.should be_an_instance_of(Enumerator)
    e.to_a.should == @sliced
  end

  ruby_version_is "3.1" do
    it "returns self when a block is given" do
      @enum.each_slice(3){}.should == @enum
    end
  end

  it "gathers whole arrays as elements when each yields multiple" do
    multi = EnumerableSpecs::YieldsMulti.new
    multi.each_slice(2).to_a.should == [[[1, 2], [3, 4, 5]], [[6, 7, 8, 9]]]
  end

  describe "when no block is given" do
    it "returns an enumerator" do
      e = @enum.each_slice(3)
      e.should be_an_instance_of(Enumerator)
      e.to_a.should == @sliced
    end

    describe "Enumerable with size" do
      describe "returned Enumerator" do
        describe "size" do
          it "returns the ceil of Enumerable size divided by the argument value" do
            enum = EnumerableSpecs::NumerousWithSize.new(1, 2, 3, 4, 5, 6, 7, 8, 9, 10)
            enum.each_slice(10).size.should == 1
            enum.each_slice(9).size.should == 2
            enum.each_slice(3).size.should == 4
            enum.each_slice(2).size.should == 5
            enum.each_slice(1).size.should == 10
          end

          it "returns 0 when the Enumerable is empty" do
            enum = EnumerableSpecs::EmptyWithSize.new
            enum.each_slice(10).size.should == 0
          end
        end
      end
    end

    describe "Enumerable with no size" do
      before :all do
        @object = EnumerableSpecs::Numerous.new(1, 2, 3, 4)
        @method = [:each_slice, 8]
      end
      it_should_behave_like :enumeratorized_with_unknown_size
    end
  end

end
