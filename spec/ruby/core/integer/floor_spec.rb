require File.expand_path('../../../spec_helper', __FILE__)
require File.expand_path('../shared/to_i', __FILE__)
require File.expand_path('../shared/integer_rounding', __FILE__)

describe "Integer#floor" do
  it_behaves_like(:integer_to_i, :floor)
  it_behaves_like(:integer_rounding_positive_precision, :floor)

  ruby_version_is "2.4" do
    context "precision argument specified as part of the floor method is negative" do
      it "returns the largest integer less than self with at least precision.abs trailing zeros" do
        1832.floor(-1).should eql(1830)
        1832.floor(-2).should eql(1800)
        1832.floor(-3).should eql(1000)
        -1832.floor(-1).should eql(-1840)
        -1832.floor(-2).should eql(-1900)
        -1832.floor(-3).should eql(-2000)
      end
    end
  end
end
