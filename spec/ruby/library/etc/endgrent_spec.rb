require_relative '../../spec_helper'
require_relative 'shared/windows'
require 'etc'

describe "Etc.endgrent" do
  it_behaves_like :etc_on_windows, :endgrent
end
