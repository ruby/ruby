require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/exponent'

ruby_version_is "2.5" do
  describe "Integer#pow" do
    context "one argument is passed" do
      it_behaves_like :integer_exponent, :pow
    end

    context "two arguments are passed" do
      it "returns modulo of self raised to the given power" do
        2.pow(5, 12).should == 8
        2.pow(6, 13).should == 12
        2.pow(7, 14).should == 2
        2.pow(8, 15).should == 1
      end

      ruby_bug '#13669', '2.5'...'2.5.1' do
        it "works well with bignums" do
          2.pow(61, 5843009213693951).should eql 3697379018277258
          2.pow(62, 5843009213693952).should eql 1551748822859776
          2.pow(63, 5843009213693953).should eql 3103497645717974
          2.pow(64, 5843009213693954).should eql  363986077738838
        end
      end

      it "handles sign like #divmod does" do
         2.pow(5,  12).should ==  8
         2.pow(5, -12).should == -4
        -2.pow(5,  12).should ==  4
        -2.pow(5, -12).should == -8
      end

      it "ensures all arguments are integers" do
        -> { 2.pow(5, 12.0) }.should raise_error(TypeError, /2nd argument not allowed unless all arguments are integers/)
        -> { 2.pow(5, Rational(12, 1)) }.should raise_error(TypeError, /2nd argument not allowed unless all arguments are integers/)
      end

      it "raises TypeError for non-numeric value" do
        -> { 2.pow(5, "12") }.should raise_error(TypeError)
        -> { 2.pow(5, []) }.should raise_error(TypeError)
        -> { 2.pow(5, nil) }.should raise_error(TypeError)
      end

      it "raises a ZeroDivisionError when the given argument is 0" do
        -> { 2.pow(5, 0) }.should raise_error(ZeroDivisionError)
      end
    end
  end
end
