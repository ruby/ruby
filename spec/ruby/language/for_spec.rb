require_relative '../spec_helper'
require_relative 'fixtures/for_scope'

# for name[, name]... in expr [do]
#   body
# end
describe "The for expression" do
  it "iterates over an Enumerable passing each element to the block" do
    j = 0
    for i in 1..3
      j += i
    end
    j.should == 6
  end

  it "iterates over a list of arrays and destructures with empty comma" do
    for i, in [[1,2]]
      i.should == 1
    end
  end

  it "iterates over a list of arrays and destructures with an empty splat" do
    for i, * in [[1,2]]
      i.should == 1
    end
  end

  it "iterates over a list of arrays and destructures with a splat" do
    for i, *j in [[1,2]]
      i.should == 1
      j.should == [2]
    end
  end

  it "iterates over a list of arrays and destructures with a splat and additional targets" do
    for i, *j, k in [[1,2,3,4]]
      i.should == 1
      j.should == [2,3]
      k.should == 4
    end
  end

  it "iterates over an Hash passing each key-value pair to the block" do
    k = 0
    l = 0

    for i, j in { 1 => 10, 2 => 20 }
      k += i
      l += j
    end

    k.should == 3
    l.should == 30
  end

  it "iterates over any object responding to 'each'" do
    obj = Object.new
    def obj.each
      (0..10).each { |i| yield i }
    end

    j = 0
    for i in obj
      j += i
    end
    j.should == 55
  end

  it "allows an instance variable as an iterator name" do
    m = [1,2,3]
    n = 0
    for @var in m
      n += 1
    end
    @var.should == 3
    n.should == 3
  end

  it "allows a class variable as an iterator name" do
    class OFor
      m = [1,2,3]
      n = 0
      for @@var in m
        n += 1
      end
      @@var.should == 3
      n.should == 3
    end
  end

  it "allows a constant as an iterator name" do
    class OFor
      m = [1,2,3]
      n = 0
      -> {
        for CONST in m
          n += 1
        end
      }.should complain(/already initialized constant/)
      CONST.should == 3
      n.should == 3
    end
  end

  it "allows a global variable as an iterator name" do
    old_global_var = $var
    m = [1,2,3]
    n = 0
    for $var in m
      n += 1
    end
    $var.should == 3
    n.should == 3
    $var = old_global_var
  end

  it "allows an attribute as an iterator name" do
    class OFor
      attr_accessor :target
    end

    ofor = OFor.new
    m = [1,2,3]
    n = 0
    for ofor.target in m
      n += 1
    end
    ofor.target.should == 3
    n.should == 3
  end

  # Segfault in MRI 3.3 and lower: https://bugs.ruby-lang.org/issues/20468
  ruby_bug "#20468", ""..."3.4" do
    it "allows an attribute with safe navigation as an iterator name" do
      class OFor
        attr_accessor :target
      end

      ofor = OFor.new
      m = [1,2,3]
      n = 0
      eval <<~RUBY
        for ofor&.target in m
          n += 1
        end
      RUBY
      ofor.target.should == 3
      n.should == 3
    end

    it "allows an attribute with safe navigation on a nil base as an iterator name" do
      ofor = nil
      m = [1,2,3]
      n = 0
      eval <<~RUBY
        for ofor&.target in m
          n += 1
        end
      RUBY
      ofor.should be_nil
      n.should == 3
    end
  end

  it "allows an array index writer as an iterator name" do
    arr = [:a, :b, :c]
    m = [1,2,3]
    n = 0
    for arr[1] in m
      n += 1
    end
    arr.should == [:a, 3, :c]
    n.should == 3
  end

  it "allows a hash index writer as an iterator name" do
    hash = { a: 10, b: 20, c: 30 }
    m = [1,2,3]
    n = 0
    for hash[:b] in m
      n += 1
    end
    hash.should == { a: 10, b: 3, c: 30 }
    n.should == 3
  end

  # 1.9 behaviour verified by nobu in
  # http://redmine.ruby-lang.org/issues/show/2053
  it "yields only as many values as there are arguments" do
    class OFor
      def each
        [[1,2,3], [4,5,6]].each do |a|
          yield(a[0],a[1],a[2])
        end
      end
    end
    o = OFor.new
    qs = []
    for q in o
      qs << q
    end
    qs.should == [1, 4]
    q.should == 4
  end

  it "optionally takes a 'do' after the expression" do
    j = 0
    for i in 1..3 do
      j += i
    end
    j.should == 6
  end

  it "allows body begin on the same line if do is used" do
    j = 0
    for i in 1..3 do j += i
    end
    j.should == 6
  end

  it "executes code in containing variable scope" do
    for i in 1..2
      a = 123
    end

    a.should == 123
  end

  it "executes code in containing variable scope with 'do'" do
    for i in 1..2 do
      a = 123
    end

    a.should == 123
  end

  it "does not try to access variables outside the method" do
    ForSpecs::ForInClassMethod.foo.should == [:bar, :baz]
    ForSpecs::ForInClassMethod::READER.call.should == :same_variable_set_outside
  end

  it "returns expr" do
    for i in 1..3; end.should == (1..3)
    for i,j in { 1 => 10, 2 => 20 }; end.should == { 1 => 10, 2 => 20 }
  end

  it "breaks out of a loop upon 'break', returning nil" do
    j = 0
    for i in 1..3
      j += i

      break if i == 2
    end.should == nil

    j.should == 3
  end

  it "allows 'break' to have an argument which becomes the value of the for expression" do
    for i in 1..3
      break 10 if i == 2
    end.should == 10
  end

  it "starts the next iteration with 'next'" do
    j = 0
    for i in 1..5
      next if i == 2

      j += i
    end

    j.should == 13
  end

  it "repeats current iteration with 'redo'" do
    j = 0
    for i in 1..3
      j += i

      redo if i == 2 && j < 4
    end

    j.should == 8
  end
end
