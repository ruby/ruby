require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/wakeup'

describe "Thread#wakeup" do
  it_behaves_like :thread_wakeup, :wakeup
end
