require_relative 'enumerable_enumeratorized'

describe :enumerable_collect, shared: true do
  before :each do
    ScratchPad.record []
  end

  it "returns a new array with the results of passing each element to block" do
    entries = [0, 1, 3, 4, 5, 6]
    numerous = EnumerableSpecs::Numerous.new(*entries)
    numerous.send(@method) { |i| i % 2 }.should == [0, 1, 1, 0, 1, 0]
    numerous.send(@method) { |i| i }.should == entries
  end

  it "passes through the values yielded by #each_with_index" do
    [:a, :b].each_with_index.send(@method) { |x, i| ScratchPad << [x, i]; nil }
    ScratchPad.recorded.should == [[:a, 0], [:b, 1]]
  end

  it "gathers initial args as elements when each yields multiple" do
    multi = EnumerableSpecs::YieldsMulti.new
    multi.send(@method) {|e| e}.should == [1,3,6]
  end

  it "only yields increasing values for a Range" do
    (1..0).send(@method) { |x| x }.should == []
    (1..1).send(@method) { |x| x }.should == [1]
    (1..2).send(@method) { |x| x }.should == [1, 2]
  end

  it "returns an enumerator when no block given" do
    enum = EnumerableSpecs::Numerous.new.send(@method)
    enum.should be_an_instance_of(Enumerator)
    enum.each { |i| -i }.should == [-2, -5, -3, -6, -1, -4]
  end

  it "reports the same arity as the given block" do
    entries = [0, 1, 3, 4, 5, 6]
    numerous = EnumerableSpecs::Numerous.new(*entries)

    def numerous.each(&block)
      ScratchPad << block.arity
      super
    end

    numerous.send(@method) { |a, b| a % 2 }.should == [0, 1, 1, 0, 1, 0]
    ScratchPad.recorded.should == [2]
    ScratchPad.clear
    ScratchPad.record []
    numerous.send(@method) { |i| i }.should == entries
    ScratchPad.recorded.should == [1]
  end

  it "yields 2 arguments for a Hash" do
    c = Class.new do
      def register(a, b)
        ScratchPad << [a, b]
      end
    end
    m = c.new.method(:register)

    ScratchPad.record []
    { 1 => 'a', 2 => 'b' }.map(&m)
    ScratchPad.recorded.should == [[1, 'a'], [2, 'b']]
  end

  it_should_behave_like :enumerable_enumeratorized_with_origin_size
end
