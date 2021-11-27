require_relative '../spec_helper'
require_relative 'shared/verbose'

describe "The -w command line option" do
  it_behaves_like :command_line_verbose, "-w"

  ruby_version_is "2.7" do
    it "enables both deprecated and experimental warnings" do
      ruby_exe('p Warning[:deprecated]; p Warning[:experimental]', options: '-w').should == "true\ntrue\n"
    end
  end
end
