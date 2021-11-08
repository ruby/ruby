require_relative '../../spec_helper'
require_relative '../enumerable/shared/enumeratorized'

describe "Range#each" do
  it "passes each element to the given block by using #succ" do
    a = []
    (-5..5).each { |i| a << i }
    a.should == [-5, -4, -3, -2, -1, 0, 1, 2, 3, 4, 5]

    a = []
    ('A'..'D').each { |i| a << i }
    a.should == ['A','B','C','D']

    a = []
    ('A'...'D').each { |i| a << i }
    a.should == ['A','B','C']

    a = []
    (0xfffd...0xffff).each { |i| a << i }
    a.should == [0xfffd, 0xfffe]

    y = mock('y')
    x = mock('x')
    x.should_receive(:<=>).with(y).any_number_of_times.and_return(-1)
    x.should_receive(:<=>).with(x).any_number_of_times.and_return(0)
    x.should_receive(:succ).any_number_of_times.and_return(y)
    y.should_receive(:<=>).with(x).any_number_of_times.and_return(1)
    y.should_receive(:<=>).with(y).any_number_of_times.and_return(0)

    a = []
    (x..y).each { |i| a << i }
    a.should == [x, y]
  end

  it "works for non-ASCII ranges" do
    a = []
    ('Σ'..'Ω').each { |i| a << i }
    a.should == ["Σ", "Τ", "Υ", "Φ", "Χ", "Ψ", "Ω"]
  end

  it "works with endless ranges" do
    a = []
    eval("(-2..)").each { |x| break if x > 2; a << x }
    a.should == [-2, -1, 0, 1, 2]

    a = []
    eval("(-2...)").each { |x| break if x > 2; a << x }
    a.should == [-2, -1, 0, 1, 2]
  end

  it "works with String endless ranges" do
    a = []
    eval("('A'..)").each { |x| break if x > "D"; a << x }
    a.should == ["A", "B", "C", "D"]

    a = []
    eval("('A'...)").each { |x| break if x > "D"; a << x }
    a.should == ["A", "B", "C", "D"]
  end

  ruby_version_is "2.7" do
    it "raises a TypeError beginless ranges" do
      -> { eval("(..2)").each { |x| x } }.should raise_error(TypeError)
    end
  end

  it "raises a TypeError if the first element does not respond to #succ" do
    -> { (0.5..2.4).each { |i| i } }.should raise_error(TypeError)

    b = mock('x')
    (a = mock('1')).should_receive(:<=>).with(b).and_return(1)

    -> { (a..b).each { |i| i } }.should raise_error(TypeError)
  end

  it "returns self" do
    range = 1..10
    range.each{}.should equal(range)
  end

  it "returns an enumerator when no block given" do
    enum = (1..3).each
    enum.should be_an_instance_of(Enumerator)
    enum.to_a.should == [1, 2, 3]
  end

  ruby_version_is "3.1" do
    it "supports Time objects that respond to #succ" do
      t = Time.utc(1970)
      def t.succ; self + 1 end
      t_succ = t.succ
      def t_succ.succ; self + 1; end

      (t..t_succ).to_a.should == [Time.utc(1970), Time.utc(1970, nil, nil, nil, nil, 1)]
      (t...t_succ).to_a.should == [Time.utc(1970)]
    end
  end

  ruby_version_is ""..."3.1" do
    it "raises a TypeError if the first element is a Time object even if it responds to #succ" do
      t = Time.utc(1970)
      def t.succ; self + 1 end
      t_succ = t.succ
      def t_succ.succ; self + 1; end

      -> { (t..t_succ).each { |i| i } }.should raise_error(TypeError)
    end
  end

  it "passes each Symbol element by using #succ" do
    (:aa..:ac).each.to_a.should == [:aa, :ab, :ac]
    (:aa...:ac).each.to_a.should == [:aa, :ab]
  end

  it_behaves_like :enumeratorized_with_origin_size, :each, (1..3)
end
