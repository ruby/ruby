require_relative '../../spec_helper'
require_relative 'shared/windows'
require 'etc'

describe "Etc.getpwent" do
  it_behaves_like :etc_on_windows, :getpwent
end
