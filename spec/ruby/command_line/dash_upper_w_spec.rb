require_relative '../spec_helper'
require_relative 'shared/verbose'

describe "The -W command line option" do
  before :each do
    @script = fixture __FILE__, "verbose.rb"
  end

  it "with 0 sets $VERBOSE to nil" do
    ruby_exe(@script, options: "-W0").chomp.should == "nil"
  end

  it "with 1 sets $VERBOSE to false" do
    ruby_exe(@script, options: "-W1").chomp.should == "false"
  end
end

describe "The -W command line option with 2" do
  it_behaves_like :command_line_verbose, "-W2"
end

# Regarding the defaults, see core/warning/element_reference_spec.rb
ruby_version_is "2.7" do
  describe "The -W command line option with :deprecated" do
    it "enables deprecation warnings" do
      ruby_exe('p Warning[:deprecated]', options: '-W:deprecated').should == "true\n"
    end
  end

  describe "The -W command line option with :no-deprecated" do
    it "suppresses deprecation warnings" do
      ruby_exe('p Warning[:deprecated]', options: '-w -W:no-deprecated').should == "false\n"
    end
  end

  describe "The -W command line option with :experimental" do
    it "enables experimental warnings" do
      ruby_exe('p Warning[:experimental]', options: '-W:experimental').should == "true\n"
    end
  end

  describe "The -W command line option with :no-experimental" do
    it "suppresses experimental warnings" do
      ruby_exe('p Warning[:experimental]', options: '-w -W:no-experimental').should == "false\n"
    end
  end
end
