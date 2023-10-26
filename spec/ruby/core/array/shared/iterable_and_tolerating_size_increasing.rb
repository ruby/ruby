describe :array_iterable_and_tolerating_size_increasing, shared: true do
  before do
    @value_to_return ||= -> _ { nil }
  end

  it "tolerates increasing an array size during iteration" do
    # The goal is to trigger potential reallocation of internal array storage, so we:
    # - use elements of different types, starting with the less generic (Integer)
    # - add reasonably big number of new elements (~ 100)
    array = [1, 2, 3] # to test some methods we need several uniq elements
    array_to_join = [:a, :b, :c] + (4..100).to_a

    ScratchPad.record []
    i = 0

    array.send(@method) do |e|
      ScratchPad << e
      array << array_to_join[i] if i < array_to_join.size
      i += 1
      @value_to_return.call(e)
    end

    ScratchPad.recorded.should == [1, 2, 3] + array_to_join
  end
end
