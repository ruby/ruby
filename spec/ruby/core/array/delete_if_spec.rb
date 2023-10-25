require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/enumeratorize'
require_relative 'shared/delete_if'
require_relative 'shared/iterable_and_tolerating_size_increasing'
require_relative '../enumerable/shared/enumeratorized'

describe "Array#delete_if" do
  before do
    @a = [ "a", "b", "c" ]
  end

  it "removes each element for which block returns true" do
    @a = [ "a", "b", "c" ]
    @a.delete_if { |x| x >= "b" }
    @a.should == ["a"]
  end

  it "returns self" do
    @a.delete_if{ true }.equal?(@a).should be_true
  end

  it_behaves_like :enumeratorize, :delete_if

  it "returns self when called on an Array emptied with #shift" do
    array = [1]
    array.shift
    array.delete_if { |x| true }.should equal(array)
  end

  it "returns an Enumerator if no block given, and the enumerator can modify the original array" do
    enum = @a.delete_if
    enum.should be_an_instance_of(Enumerator)
    @a.should_not be_empty
    enum.each { true }
    @a.should be_empty
  end

  it "returns an Enumerator if no block given, and the array is frozen" do
    @a.freeze.delete_if.should be_an_instance_of(Enumerator)
  end

  it "raises a FrozenError on a frozen array" do
    -> { ArraySpecs.frozen_array.delete_if {} }.should raise_error(FrozenError)
  end

  it "raises a FrozenError on an empty frozen array" do
    -> { ArraySpecs.empty_frozen_array.delete_if {} }.should raise_error(FrozenError)
  end

  it "does not truncate the array is the block raises an exception" do
    a = [1, 2, 3]
    begin
      a.delete_if { raise StandardError, 'Oops' }
    rescue
    end

    a.should == [1, 2, 3]
  end

  it "only removes elements for which the block returns true, keeping the element which raised an error." do
    a = [1, 2, 3, 4]
    begin
      a.delete_if do |e|
        case e
        when 2 then true
        when 3 then raise StandardError, 'Oops'
        else false
        end
      end
    rescue StandardError
    end

    a.should == [1, 3, 4]
  end

  it_behaves_like :enumeratorized_with_origin_size, :delete_if, [1,2,3]
  it_behaves_like :delete_if, :delete_if

  @value_to_return = -> _ { false }
  it_behaves_like :array_iterable_and_tolerating_size_increasing, :delete_if
end
