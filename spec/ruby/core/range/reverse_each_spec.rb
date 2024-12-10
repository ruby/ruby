require_relative '../../spec_helper'

ruby_version_is "3.3" do
  describe "Range#reverse_each" do
    it "traverses the Range in reverse order and passes each element to block" do
      a = []
      (1..3).reverse_each { |i| a << i }
      a.should == [3, 2, 1]

      a = []
      (1...3).reverse_each { |i| a << i }
      a.should == [2, 1]
    end

    it "returns self" do
      r = (1..3)
      r.reverse_each { |x| }.should equal(r)
    end

    it "returns an Enumerator if no block given" do
      enum = (1..3).reverse_each
      enum.should be_an_instance_of(Enumerator)
      enum.to_a.should == [3, 2, 1]
    end

    it "raises a TypeError for endless Ranges of Integers" do
      -> {
        (1..).reverse_each.take(3)
      }.should raise_error(TypeError, "can't iterate from NilClass")
    end

    it "raises a TypeError for endless Ranges of non-Integers" do
      -> {
        ("a"..).reverse_each.take(3)
      }.should raise_error(TypeError, "can't iterate from NilClass")
    end

    context "Integer boundaries" do
      it "supports beginningless Ranges" do
        (..5).reverse_each.take(3).should == [5, 4, 3]
      end
    end

    context "non-Integer boundaries" do
      it "uses #succ to iterate a Range of non-Integer elements" do
        y = mock('y')
        x = mock('x')

        x.should_receive(:succ).any_number_of_times.and_return(y)
        x.should_receive(:<=>).with(y).any_number_of_times.and_return(-1)
        x.should_receive(:<=>).with(x).any_number_of_times.and_return(0)
        y.should_receive(:<=>).with(x).any_number_of_times.and_return(1)
        y.should_receive(:<=>).with(y).any_number_of_times.and_return(0)

        a = []
        (x..y).each { |i| a << i }
        a.should == [x, y]
      end

      it "uses #succ to iterate a Range of Strings" do
        a = []
        ('A'..'D').reverse_each { |i| a << i }
        a.should == ['D','C','B','A']
      end

      it "uses #succ to iterate a Range of Symbols" do
        a = []
        (:A..:D).reverse_each { |i| a << i }
        a.should == [:D, :C, :B, :A]
      end

      it "raises a TypeError when `begin` value does not respond to #succ" do
        -> { (Time.now..Time.now).reverse_each { |x| x } }.should raise_error(TypeError, /can't iterate from Time/)
        -> { (//..//).reverse_each { |x| x } }.should raise_error(TypeError, /can't iterate from Regexp/)
        -> { ([]..[]).reverse_each { |x| x } }.should raise_error(TypeError, /can't iterate from Array/)
      end

      it "does not support beginningless Ranges" do
        -> {
          (..'a').reverse_each { |x| x }
        }.should raise_error(TypeError, /can't iterate from NilClass/)
      end
    end

    context "when no block is given" do
      describe "returned Enumerator size" do
        it "returns the Range size when Range size is finite" do
          (1..3).reverse_each.size.should == 3
        end

        ruby_bug "#20936", "3.4"..."3.5" do
          it "returns Infinity when Range size is infinite" do
            (..3).reverse_each.size.should == Float::INFINITY
          end
        end

        it "returns nil when Range size is unknown" do
          ('a'..'z').reverse_each.size.should == nil
        end
      end
    end
  end
end
