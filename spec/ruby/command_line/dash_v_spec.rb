require_relative '../spec_helper'
require_relative 'shared/verbose'

describe "The -v command line option" do
  it_behaves_like :command_line_verbose, "-v"

  describe "when used alone" do
    it "prints version and ends" do
      ruby_exe(nil, args: '-v').gsub("+PRISM ", "").should include(RUBY_DESCRIPTION.gsub("+PRISM ", ""))
    end unless (defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?) ||
               (defined?(RubyVM::RJIT) && RubyVM::RJIT.enabled?) ||
               (ENV['RUBY_GC_LIBRARY'] && ENV['RUBY_GC_LIBRARY'].length > 0) ||
               (ENV['RUBY_MN_THREADS'] == '1')
  end
end
