require_relative '../../spec_helper'
require_relative '../../shared/process/fork'

describe "Process.fork" do
  it_behaves_like :process_fork, :fork, Process
end
