require_relative '../../spec_helper'
require_relative 'shared/windows'
require 'etc'

describe "Etc.group" do
  it_behaves_like :etc_on_windows, :group

  platform_is_not :windows do
    it "raises a RuntimeError for parallel iteration" do
      proc {
        Etc.group do | group |
          Etc.group do | group2 |
          end
        end
      }.should raise_error(RuntimeError)
    end
  end
end
