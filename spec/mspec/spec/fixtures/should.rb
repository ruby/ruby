$: << File.dirname(__FILE__) + '/../../lib'
require 'mspec'
require 'mspec/utils/script'

# The purpose of these specs is to confirm that the #should
# and #should_not methods are functioning appropriately. We
# use a separate spec file that is invoked from the MSpec
# specs but is run by MSpec. This avoids conflicting with
# RSpec's #should and #should_not methods.

raise "RSpec should not be loaded" if defined?(RSpec)

class ShouldSpecsMonitor
  def initialize
    @called = 0
  end

  def expectation(state)
    @called += 1
  end

  def finish
    puts "I was called #{@called} times"
  end
end

# Simplistic runner
formatter = DottedFormatter.new
formatter.register

monitor = ShouldSpecsMonitor.new
MSpec.register :expectation, monitor
MSpec.register :finish, monitor

at_exit { MSpec.actions :finish }

MSpec.actions :start
MSpec.setup_env

# Specs
describe "MSpec expectation method #should" do
  it "accepts a matcher" do
    :sym.should be_kind_of(Symbol)
  end

  it "causes a failure to be recorded" do
    1.should == 2
  end

  it "registers that an expectation has been encountered" do
    # an empty example block causes an exception because
    # no expectation was encountered
  end

  it "invokes the MSpec :expectation actions" do
    1.should == 1
  end
end

describe "MSpec expectation method #should_not" do
  it "accepts a matcher" do
    "sym".should_not be_kind_of(Symbol)
  end

  it "causes a failure to be recorded" do
    1.should_not == 1
  end

  it "registers that an expectation has been encountered" do
  end

  it "invokes the MSpec :expectation actions" do
    1.should_not == 2
  end
end
