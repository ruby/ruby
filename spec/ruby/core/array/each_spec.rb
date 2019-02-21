require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/enumeratorize'
require_relative '../enumerable/shared/enumeratorized'

# Modifying a collection while the contents are being iterated
# gives undefined behavior. See
# http://blade.nagaokaut.ac.jp/cgi-bin/scat.rb/ruby/ruby-core/23633

describe "Array#each" do
  it "yields each element to the block" do
    a = []
    x = [1, 2, 3]
    x.each { |item| a << item }.should equal(x)
    a.should == [1, 2, 3]
  end

  it "yields each element to a block that takes multiple arguments" do
    a = [[1, 2], :a, [3, 4]]
    b = []

    a.each { |x, y| b << x }
    b.should == [1, :a, 3]

    b = []
    a.each { |x, y| b << y }
    b.should == [2, nil, 4]
  end

  it "yields elements added to the end of the array by the block" do
    a = [2]
    iterated = []
    a.each { |x| iterated << x; x.times { a << 0 } }

    iterated.should == [2, 0, 0]
  end

  it "does not yield elements deleted from the end of the array" do
    a = [2, 3, 1]
    iterated = []
    a.each { |x| iterated << x; a.delete_at(2) if x == 3 }

    iterated.should == [2, 3]
  end

  it_behaves_like :enumeratorize, :each
  it_behaves_like :enumeratorized_with_origin_size, :each, [1,2,3]
end
