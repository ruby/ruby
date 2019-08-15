require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/exit'

describe "Thread#exit!" do
  it "needs to be reviewed for spec completeness"
end

describe "Thread.exit" do
  it "causes the current thread to exit" do
    thread = Thread.new { Thread.exit; sleep }
    thread.join
    thread.status.should be_false
  end
end
