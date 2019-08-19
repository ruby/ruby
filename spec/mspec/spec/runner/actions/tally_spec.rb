require File.dirname(__FILE__) + '/../../spec_helper'
require 'mspec/expectations/expectations'
require 'mspec/runner/actions/tally'
require 'mspec/runner/mspec'
require 'mspec/runner/example'

describe Tally, "#files!" do
  before :each do
    @tally = Tally.new
  end

  it "increments the count returned by #files" do
    @tally.files! 3
    @tally.files.should == 3
    @tally.files!
    @tally.files.should == 4
  end
end

describe Tally, "#examples!" do
  before :each do
    @tally = Tally.new
  end

  it "increments the count returned by #examples" do
    @tally.examples! 2
    @tally.examples.should == 2
    @tally.examples! 2
    @tally.examples.should == 4
  end
end

describe Tally, "#expectations!" do
  before :each do
    @tally = Tally.new
  end

  it "increments the count returned by #expectations" do
    @tally.expectations!
    @tally.expectations.should == 1
    @tally.expectations! 3
    @tally.expectations.should == 4
  end
end

describe Tally, "#failures!" do
  before :each do
    @tally = Tally.new
  end

  it "increments the count returned by #failures" do
    @tally.failures! 1
    @tally.failures.should == 1
    @tally.failures!
    @tally.failures.should == 2
  end
end

describe Tally, "#errors!" do
  before :each do
    @tally = Tally.new
  end

  it "increments the count returned by #errors" do
    @tally.errors!
    @tally.errors.should == 1
    @tally.errors! 2
    @tally.errors.should == 3
  end
end

describe Tally, "#guards!" do
  before :each do
    @tally = Tally.new
  end

  it "increments the count returned by #guards" do
    @tally.guards!
    @tally.guards.should == 1
    @tally.guards! 2
    @tally.guards.should == 3
  end
end

describe Tally, "#file" do
  before :each do
    @tally = Tally.new
  end

  it "returns a formatted string of the number of #files" do
    @tally.file.should == "0 files"
    @tally.files!
    @tally.file.should == "1 file"
    @tally.files!
    @tally.file.should == "2 files"
  end
end

describe Tally, "#example" do
  before :each do
    @tally = Tally.new
  end

  it "returns a formatted string of the number of #examples" do
    @tally.example.should == "0 examples"
    @tally.examples!
    @tally.example.should == "1 example"
    @tally.examples!
    @tally.example.should == "2 examples"
  end
end

describe Tally, "#expectation" do
  before :each do
    @tally = Tally.new
  end

  it "returns a formatted string of the number of #expectations" do
    @tally.expectation.should == "0 expectations"
    @tally.expectations!
    @tally.expectation.should == "1 expectation"
    @tally.expectations!
    @tally.expectation.should == "2 expectations"
  end
end

describe Tally, "#failure" do
  before :each do
    @tally = Tally.new
  end

  it "returns a formatted string of the number of #failures" do
    @tally.failure.should == "0 failures"
    @tally.failures!
    @tally.failure.should == "1 failure"
    @tally.failures!
    @tally.failure.should == "2 failures"
  end
end

describe Tally, "#error" do
  before :each do
    @tally = Tally.new
  end

  it "returns a formatted string of the number of #errors" do
    @tally.error.should == "0 errors"
    @tally.errors!
    @tally.error.should == "1 error"
    @tally.errors!
    @tally.error.should == "2 errors"
  end
end

describe Tally, "#guard" do
  before :each do
    @tally = Tally.new
  end

  it "returns a formatted string of the number of #guards" do
    @tally.guard.should == "0 guards"
    @tally.guards!
    @tally.guard.should == "1 guard"
    @tally.guards!
    @tally.guard.should == "2 guards"
  end
end

describe Tally, "#format" do
  before :each do
    @tally = Tally.new
  end

  after :each do
    MSpec.clear_modes
  end

  it "returns a formatted string of counts" do
    @tally.files!
    @tally.examples! 2
    @tally.expectations! 4
    @tally.errors!
    @tally.tagged!
    @tally.format.should == "1 file, 2 examples, 4 expectations, 0 failures, 1 error, 1 tagged"
  end

  it "includes guards if MSpec is in verify mode" do
    MSpec.register_mode :verify
    @tally.files!
    @tally.examples! 2
    @tally.expectations! 4
    @tally.errors!
    @tally.tagged!
    @tally.guards!
    @tally.format.should ==
      "1 file, 2 examples, 4 expectations, 0 failures, 1 error, 1 tagged, 1 guard"
  end

  it "includes guards if MSpec is in report mode" do
    MSpec.register_mode :report
    @tally.files!
    @tally.examples! 2
    @tally.expectations! 4
    @tally.errors!
    @tally.tagged!
    @tally.guards! 2
    @tally.format.should ==
      "1 file, 2 examples, 4 expectations, 0 failures, 1 error, 1 tagged, 2 guards"
  end

  it "includes guards if MSpec is in report_on mode" do
    MSpec.register_mode :report_on
    @tally.files!
    @tally.examples! 2
    @tally.expectations! 4
    @tally.errors!
    @tally.guards! 2
    @tally.format.should ==
      "1 file, 2 examples, 4 expectations, 0 failures, 1 error, 0 tagged, 2 guards"
  end
end

describe TallyAction, "#counter" do
  before :each do
    @tally = TallyAction.new
    @state = ExampleState.new("describe", "it")
  end

  it "returns the Tally object" do
    @tally.counter.should be_kind_of(Tally)
  end
end

describe TallyAction, "#load" do
  before :each do
    @tally = TallyAction.new
    @state = ExampleState.new("describe", "it")
  end

  it "increments the count returned by Tally#files" do
    @tally.load
    @tally.counter.files.should == 1
  end
end

describe TallyAction, "#expectation" do
  before :each do
    @tally = TallyAction.new
    @state = ExampleState.new("describe", "it")
  end

  it "increments the count returned by Tally#expectations" do
    @tally.expectation @state
    @tally.counter.expectations.should == 1
  end
end

describe TallyAction, "#example" do
  before :each do
    @tally = TallyAction.new
    @state = ExampleState.new("describe", "it")
  end

  it "increments counts returned by Tally#examples" do
    @tally.example @state, nil
    @tally.counter.examples.should == 1
    @tally.counter.expectations.should == 0
    @tally.counter.failures.should == 0
    @tally.counter.errors.should == 0
  end
end

describe TallyAction, "#exception" do
  before :each do
    @tally = TallyAction.new
    @state = ExampleState.new("describe", "it")
  end

  it "increments counts returned by Tally#failures" do
    exc = ExceptionState.new nil, nil, SpecExpectationNotMetError.new("Failed!")
    @tally.exception exc
    @tally.counter.examples.should == 0
    @tally.counter.expectations.should == 0
    @tally.counter.failures.should == 1
    @tally.counter.errors.should == 0
  end
end

describe TallyAction, "#exception" do
  before :each do
    @tally = TallyAction.new
    @state = ExampleState.new("describe", "it")
  end

  it "increments counts returned by Tally#errors" do
    exc = ExceptionState.new nil, nil, Exception.new("Error!")
    @tally.exception exc
    @tally.counter.examples.should == 0
    @tally.counter.expectations.should == 0
    @tally.counter.failures.should == 0
    @tally.counter.errors.should == 1
  end
end

describe TallyAction, "#format" do
  before :each do
    @tally = TallyAction.new
    @state = ExampleState.new("describe", "it")
  end

  it "returns a readable string of counts" do
    @tally.load
    @tally.example @state, nil
    @tally.expectation @state
    @tally.expectation @state
    exc = ExceptionState.new nil, nil, SpecExpectationNotMetError.new("Failed!")
    @tally.exception exc
    @tally.format.should == "1 file, 1 example, 2 expectations, 1 failure, 0 errors, 0 tagged"
  end
end

describe TallyAction, "#register" do
  before :each do
    @tally = TallyAction.new
    @state = ExampleState.new("describe", "it")
  end

  it "registers itself with MSpec for appropriate actions" do
    MSpec.should_receive(:register).with(:load, @tally)
    MSpec.should_receive(:register).with(:exception, @tally)
    MSpec.should_receive(:register).with(:example, @tally)
    MSpec.should_receive(:register).with(:tagged, @tally)
    MSpec.should_receive(:register).with(:expectation, @tally)
    @tally.register
  end
end

describe TallyAction, "#unregister" do
  before :each do
    @tally = TallyAction.new
    @state = ExampleState.new("describe", "it")
  end

  it "unregisters itself with MSpec for appropriate actions" do
    MSpec.should_receive(:unregister).with(:load, @tally)
    MSpec.should_receive(:unregister).with(:exception, @tally)
    MSpec.should_receive(:unregister).with(:example, @tally)
    MSpec.should_receive(:unregister).with(:tagged, @tally)
    MSpec.should_receive(:unregister).with(:expectation, @tally)
    @tally.unregister
  end
end
