require_relative '../../spec_helper'
require_relative 'shared/arithmetic_coerce'

describe "Integer#+" do
  it_behaves_like :integer_arithmetic_coerce_not_rescue, :+

  context "fixnum" do
    it "returns self plus the given Integer" do
      (491 + 2).should == 493
      (90210 + 10).should == 90220

      (9 + bignum_value).should == 9223372036854775817
      (1001 + 5.219).should == 1006.219
    end

    it "raises a TypeError when given a non-Integer" do
      -> {
        (obj = mock('10')).should_receive(:to_int).any_number_of_times.and_return(10)
        13 + obj
      }.should raise_error(TypeError)
      -> { 13 + "10"    }.should raise_error(TypeError)
      -> { 13 + :symbol }.should raise_error(TypeError)
    end
  end

  context "bignum" do
    before :each do
      @bignum = bignum_value(76)
    end

    it "returns self plus the given Integer" do
      (@bignum + 4).should == 9223372036854775888
      (@bignum + 4.2).should be_close(9223372036854775888.2, TOLERANCE)
      (@bignum + bignum_value(3)).should == 18446744073709551695
    end

    it "raises a TypeError when given a non-Integer" do
      -> { @bignum + mock('10') }.should raise_error(TypeError)
      -> { @bignum + "10" }.should raise_error(TypeError)
      -> { @bignum + :symbol}.should raise_error(TypeError)
    end
  end

  it "can be redefined" do
    code = <<~RUBY
      class Integer
        alias_method :old_plus, :+
        def +(other)
          self - other
        end
      end
      result = 1 + 2
      Integer.alias_method :+, :old_plus
      print result
    RUBY
    ruby_exe(code).should == "-1"
  end
end
