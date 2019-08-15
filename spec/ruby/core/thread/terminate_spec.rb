require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/exit'

describe "Thread#terminate" do
  it_behaves_like :thread_exit, :terminate
end
