require File.expand_path('../../spec_helper', __FILE__)
require File.expand_path('../shared/verbose', __FILE__)

describe "The -v command line option" do
  it_behaves_like :command_line_verbose, "-v"

  describe "when used alone" do
    it "prints version and ends" do
      version = ruby_exe(nil, args: '--version')
      ruby_exe(nil, args: '-v').should == version
    end
  end
end
