require_relative '../../spec_helper'
require_relative '../../shared/process/abort'

describe "Process.abort" do
  it_behaves_like :process_abort, :abort, Process
end
