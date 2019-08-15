require_relative '../spec_helper'
require_relative 'shared/change_directory'

describe "The -X command line option" do
  it_behaves_like :command_line_change_directory, "-X"
end
