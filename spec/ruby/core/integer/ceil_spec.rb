require_relative '../../spec_helper'
require_relative 'shared/to_i'
require_relative 'shared/integer_rounding'

describe "Integer#ceil" do
  it_behaves_like :integer_to_i, :ceil
  it_behaves_like :integer_rounding_positive_precision, :ceil

  ruby_version_is "2.4" do
    context "precision argument specified as part of the ceil method is negative" do
      it "returns the smallest integer greater than self with at least precision.abs trailing zeros" do
        18.ceil(-1).should eql(20)
        18.ceil(-2).should eql(100)
        18.ceil(-3).should eql(1000)
        -1832.ceil(-1).should eql(-1830)
        -1832.ceil(-2).should eql(-1800)
        -1832.ceil(-3).should eql(-1000)
      end
    end
  end
end
