require_relative '../../spec_helper'
require_relative '../../shared/process/exit'

describe "Process.exit" do
  it_behaves_like :process_exit, :exit, Process
end

describe "Process.exit!" do
  it_behaves_like :process_exit!, :exit!, Process
end
