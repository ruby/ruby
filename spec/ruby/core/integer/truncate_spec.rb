require_relative '../../spec_helper'
require_relative 'shared/to_i'
require_relative 'shared/integer_rounding'

describe "Integer#truncate" do
  it_behaves_like :integer_to_i, :truncate
  it_behaves_like :integer_rounding_positive_precision, :truncate

  ruby_version_is "2.4" do
    context "precision argument specified as part of the truncate method is negative" do
      it "returns an integer with at least precision.abs trailing zeros" do
        1832.truncate(-1).should eql(1830)
        1832.truncate(-2).should eql(1800)
        1832.truncate(-3).should eql(1000)
        -1832.truncate(-1).should eql(-1830)
        -1832.truncate(-2).should eql(-1800)
        -1832.truncate(-3).should eql(-1000)
      end
    end
  end
end
