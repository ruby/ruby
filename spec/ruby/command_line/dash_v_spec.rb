require File.expand_path('../../spec_helper', __FILE__)
require File.expand_path('../shared/verbose', __FILE__)

describe "The -v command line option" do
  it_behaves_like :command_line_verbose, "-v"

  describe "when used alone" do
    it "prints version and ends" do
      ruby_exe(nil, args: '-v').include?(RUBY_DESCRIPTION).should == true
    end
  end
end
