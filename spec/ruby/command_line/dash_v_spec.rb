require_relative '../spec_helper'
require_relative 'shared/verbose'

describe "The -v command line option" do
  it_behaves_like :command_line_verbose, "-v"

  describe "when used alone" do
    it "prints version and ends" do
      ruby_description =
        if defined?(RubyVM::MJIT) && RubyVM::MJIT.enabled?
          # fake.rb always drops +JIT from RUBY_DESCRIPTION. This resurrects that.
          RUBY_DESCRIPTION.sub(/ \[[^\]]+\]$/, ' +JIT\0')
        else
          RUBY_DESCRIPTION
        end
      ruby_exe(nil, args: '-v').include?(ruby_description).should == true
    end
  end
end
