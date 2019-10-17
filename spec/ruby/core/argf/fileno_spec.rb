require_relative '../../spec_helper'
require_relative 'shared/fileno'

describe "ARGF.fileno" do
  it_behaves_like :argf_fileno, :fileno
end
