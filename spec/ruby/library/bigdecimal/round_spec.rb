require_relative '../../spec_helper'
require 'bigdecimal'

describe "BigDecimal#round" do
  before :each do
    @one   = BigDecimal("1")
    @two   = BigDecimal("2")
    @three = BigDecimal("3")

    @neg_one   = BigDecimal("-1")
    @neg_two   = BigDecimal("-2")
    @neg_three = BigDecimal("-3")

    @p1_50 = BigDecimal("1.50")
    @p1_51 = BigDecimal("1.51")
    @p1_49 = BigDecimal("1.49")
    @n1_50 = BigDecimal("-1.50")
    @n1_51 = BigDecimal("-1.51")
    @n1_49 = BigDecimal("-1.49")

    @p2_50 = BigDecimal("2.50")
    @p2_51 = BigDecimal("2.51")
    @p2_49 = BigDecimal("2.49")
    @n2_50 = BigDecimal("-2.50")
    @n2_51 = BigDecimal("-2.51")
    @n2_49 = BigDecimal("-2.49")
  end

  after :each do
    BigDecimal.mode(BigDecimal::ROUND_MODE, BigDecimal::ROUND_HALF_UP)
  end

  it "uses default rounding method unless given" do
    @p1_50.round(0).should == @two
    @p1_51.round(0).should == @two
    @p1_49.round(0).should == @one
    @n1_50.round(0).should == @neg_two
    @n1_51.round(0).should == @neg_two
    @n1_49.round(0).should == @neg_one

    @p2_50.round(0).should == @three
    @p2_51.round(0).should == @three
    @p2_49.round(0).should == @two
    @n2_50.round(0).should == @neg_three
    @n2_51.round(0).should == @neg_three
    @n2_49.round(0).should == @neg_two

    BigDecimal.mode(BigDecimal::ROUND_MODE, BigDecimal::ROUND_DOWN)

    @p1_50.round(0).should == @one
    @p1_51.round(0).should == @one
    @p1_49.round(0).should == @one
    @n1_50.round(0).should == @neg_one
    @n1_51.round(0).should == @neg_one
    @n1_49.round(0).should == @neg_one

    @p2_50.round(0).should == @two
    @p2_51.round(0).should == @two
    @p2_49.round(0).should == @two
    @n2_50.round(0).should == @neg_two
    @n2_51.round(0).should == @neg_two
    @n2_49.round(0).should == @neg_two
  end

  ["BigDecimal::ROUND_UP", ":up"].each do |way|
    describe way do
      it "rounds values away from zero" do
        mode = eval(way)

        @p1_50.round(0, mode).should == @two
        @p1_51.round(0, mode).should == @two
        @p1_49.round(0, mode).should == @two
        @n1_50.round(0, mode).should == @neg_two
        @n1_51.round(0, mode).should == @neg_two
        @n1_49.round(0, mode).should == @neg_two

        @p2_50.round(0, mode).should == @three
        @p2_51.round(0, mode).should == @three
        @p2_49.round(0, mode).should == @three
        @n2_50.round(0, mode).should == @neg_three
        @n2_51.round(0, mode).should == @neg_three
        @n2_49.round(0, mode).should == @neg_three
      end
    end
  end

  ["BigDecimal::ROUND_DOWN", ":down", ":truncate"].each do |way|
    describe way do
      it "rounds values towards zero" do
        mode = eval(way)

        @p1_50.round(0, mode).should == @one
        @p1_51.round(0, mode).should == @one
        @p1_49.round(0, mode).should == @one
        @n1_50.round(0, mode).should == @neg_one
        @n1_51.round(0, mode).should == @neg_one
        @n1_49.round(0, mode).should == @neg_one

        @p2_50.round(0, mode).should == @two
        @p2_51.round(0, mode).should == @two
        @p2_49.round(0, mode).should == @two
        @n2_50.round(0, mode).should == @neg_two
        @n2_51.round(0, mode).should == @neg_two
        @n2_49.round(0, mode).should == @neg_two
      end
    end
  end

  ["BigDecimal::ROUND_HALF_UP", ":half_up", ":default"].each do |way|
    describe way do
      it "rounds values >= 5 up, otherwise down" do
        mode = eval(way)

        @p1_50.round(0, mode).should == @two
        @p1_51.round(0, mode).should == @two
        @p1_49.round(0, mode).should == @one
        @n1_50.round(0, mode).should == @neg_two
        @n1_51.round(0, mode).should == @neg_two
        @n1_49.round(0, mode).should == @neg_one

        @p2_50.round(0, mode).should == @three
        @p2_51.round(0, mode).should == @three
        @p2_49.round(0, mode).should == @two
        @n2_50.round(0, mode).should == @neg_three
        @n2_51.round(0, mode).should == @neg_three
        @n2_49.round(0, mode).should == @neg_two
      end
    end
  end

  ["BigDecimal::ROUND_HALF_DOWN", ":half_down"].each do |way|
    describe way do
      it "rounds values > 5 up, otherwise down" do
        mode = eval(way)

        @p1_50.round(0, mode).should == @one
        @p1_51.round(0, mode).should == @two
        @p1_49.round(0, mode).should == @one
        @n1_50.round(0, mode).should == @neg_one
        @n1_51.round(0, mode).should == @neg_two
        @n1_49.round(0, mode).should == @neg_one

        @p2_50.round(0, mode).should == @two
        @p2_51.round(0, mode).should == @three
        @p2_49.round(0, mode).should == @two
        @n2_50.round(0, mode).should == @neg_two
        @n2_51.round(0, mode).should == @neg_three
        @n2_49.round(0, mode).should == @neg_two
      end
    end
  end

  ["BigDecimal::ROUND_CEILING", ":ceiling", ":ceil"].each do |way|
    describe way do
      it "rounds values towards +infinity" do
        mode = eval(way)

        @p1_50.round(0, mode).should == @two
        @p1_51.round(0, mode).should == @two
        @p1_49.round(0, mode).should == @two
        @n1_50.round(0, mode).should == @neg_one
        @n1_51.round(0, mode).should == @neg_one
        @n1_49.round(0, mode).should == @neg_one

        @p2_50.round(0, mode).should == @three
        @p2_51.round(0, mode).should == @three
        @p2_49.round(0, mode).should == @three
        @n2_50.round(0, mode).should == @neg_two
        @n2_51.round(0, mode).should == @neg_two
        @n2_49.round(0, mode).should == @neg_two
      end
    end
  end

  ["BigDecimal::ROUND_FLOOR", ":floor"].each do |way|
    describe way do
      it "rounds values towards -infinity" do
        mode = eval(way)

        @p1_50.round(0, mode).should == @one
        @p1_51.round(0, mode).should == @one
        @p1_49.round(0, mode).should == @one
        @n1_50.round(0, mode).should == @neg_two
        @n1_51.round(0, mode).should == @neg_two
        @n1_49.round(0, mode).should == @neg_two

        @p2_50.round(0, mode).should == @two
        @p2_51.round(0, mode).should == @two
        @p2_49.round(0, mode).should == @two
        @n2_50.round(0, mode).should == @neg_three
        @n2_51.round(0, mode).should == @neg_three
        @n2_49.round(0, mode).should == @neg_three
      end
    end
  end

  ["BigDecimal::ROUND_HALF_EVEN", ":half_even", ":banker"].each do |way|
    describe way do
      it "rounds values > 5 up, < 5 down and == 5 towards even neighbor" do
        mode = eval(way)

        @p1_50.round(0, mode).should == @two
        @p1_51.round(0, mode).should == @two
        @p1_49.round(0, mode).should == @one
        @n1_50.round(0, mode).should == @neg_two
        @n1_51.round(0, mode).should == @neg_two
        @n1_49.round(0, mode).should == @neg_one

        @p2_50.round(0, mode).should == @two
        @p2_51.round(0, mode).should == @three
        @p2_49.round(0, mode).should == @two
        @n2_50.round(0, mode).should == @neg_two
        @n2_51.round(0, mode).should == @neg_three
        @n2_49.round(0, mode).should == @neg_two
      end
    end
  end

  it 'raise exception, if self is special value' do
    -> { BigDecimal('NaN').round }.should raise_error(FloatDomainError)
    -> { BigDecimal('Infinity').round }.should raise_error(FloatDomainError)
    -> { BigDecimal('-Infinity').round }.should raise_error(FloatDomainError)
  end

  it 'do not raise exception, if self is special value and precision is given' do
    -> { BigDecimal('NaN').round(2) }.should_not raise_error(FloatDomainError)
    -> { BigDecimal('Infinity').round(2) }.should_not raise_error(FloatDomainError)
    -> { BigDecimal('-Infinity').round(2) }.should_not raise_error(FloatDomainError)
  end

  it 'raise for a non-existent round mode' do
    -> { @p1_50.round(0, :nonsense) }.should raise_error(ArgumentError, "invalid rounding mode (nonsense)")
  end
end
