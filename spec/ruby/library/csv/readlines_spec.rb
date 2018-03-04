require_relative '../../spec_helper'
require 'csv'

describe "CSV.readlines" do
  it "needs to be reviewed for spec completeness"
end

describe "CSV#readlines" do
  it "returns an Array of Array containing each element in a one-line CSV file" do
    file = CSV.new "a, b, c"
    file.readlines.should == [["a", " b", " c"]]
  end

  it "returns an Array of Arrays containing each element in a multi-line CSV file" do
    file = CSV.new "a, b, c\nd, e, f"
    file.readlines.should == [["a", " b", " c"], ["d", " e", " f"]]
  end

  it "returns nil for a missing value" do
    file = CSV.new "a,, b, c"
    file.readlines.should == [["a", nil, " b", " c"]]
  end

  it "raises CSV::MalformedCSVError exception if input is illegal" do
    csv = CSV.new('"quoted" field')
    -> { csv.readlines }.should raise_error(CSV::MalformedCSVError)
  end

  ruby_version_is '2.4' do
    it "handles illegal input with the liberal_parsing option" do
      illegal_input = '"Johnson, Dwayne",Dwayne "The Rock" Johnson'
      csv = CSV.new(illegal_input, liberal_parsing: true)
      result = csv.readlines
      result.should == [["Johnson, Dwayne", 'Dwayne "The Rock" Johnson']]
    end
  end
end
