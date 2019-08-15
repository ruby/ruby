require_relative '../spec_helper'
require_relative 'shared/verbose'

describe "The -w command line option" do
  it_behaves_like :command_line_verbose, "-w"
end
