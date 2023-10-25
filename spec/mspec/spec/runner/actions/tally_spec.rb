require File.dirname(__FILE__) + '/../../spec_helper'
require 'mspec/expectations/expectations'
require 'mspec/runner/actions/tally'
require 'mspec/runner/mspec'
require 'mspec/runner/example'

RSpec.describe Tally, "#files!" do
  before :each do
    @tally = Tally.new
  end

  it "increments the count returned by #files" do
    @tally.files! 3
    expect(@tally.files).to eq(3)
    @tally.files!
    expect(@tally.files).to eq(4)
  end
end

RSpec.describe Tally, "#examples!" do
  before :each do
    @tally = Tally.new
  end

  it "increments the count returned by #examples" do
    @tally.examples! 2
    expect(@tally.examples).to eq(2)
    @tally.examples! 2
    expect(@tally.examples).to eq(4)
  end
end

RSpec.describe Tally, "#expectations!" do
  before :each do
    @tally = Tally.new
  end

  it "increments the count returned by #expectations" do
    @tally.expectations!
    expect(@tally.expectations).to eq(1)
    @tally.expectations! 3
    expect(@tally.expectations).to eq(4)
  end
end

RSpec.describe Tally, "#failures!" do
  before :each do
    @tally = Tally.new
  end

  it "increments the count returned by #failures" do
    @tally.failures! 1
    expect(@tally.failures).to eq(1)
    @tally.failures!
    expect(@tally.failures).to eq(2)
  end
end

RSpec.describe Tally, "#errors!" do
  before :each do
    @tally = Tally.new
  end

  it "increments the count returned by #errors" do
    @tally.errors!
    expect(@tally.errors).to eq(1)
    @tally.errors! 2
    expect(@tally.errors).to eq(3)
  end
end

RSpec.describe Tally, "#guards!" do
  before :each do
    @tally = Tally.new
  end

  it "increments the count returned by #guards" do
    @tally.guards!
    expect(@tally.guards).to eq(1)
    @tally.guards! 2
    expect(@tally.guards).to eq(3)
  end
end

RSpec.describe Tally, "#file" do
  before :each do
    @tally = Tally.new
  end

  it "returns a formatted string of the number of #files" do
    expect(@tally.file).to eq("0 files")
    @tally.files!
    expect(@tally.file).to eq("1 file")
    @tally.files!
    expect(@tally.file).to eq("2 files")
  end
end

RSpec.describe Tally, "#example" do
  before :each do
    @tally = Tally.new
  end

  it "returns a formatted string of the number of #examples" do
    expect(@tally.example).to eq("0 examples")
    @tally.examples!
    expect(@tally.example).to eq("1 example")
    @tally.examples!
    expect(@tally.example).to eq("2 examples")
  end
end

RSpec.describe Tally, "#expectation" do
  before :each do
    @tally = Tally.new
  end

  it "returns a formatted string of the number of #expectations" do
    expect(@tally.expectation).to eq("0 expectations")
    @tally.expectations!
    expect(@tally.expectation).to eq("1 expectation")
    @tally.expectations!
    expect(@tally.expectation).to eq("2 expectations")
  end
end

RSpec.describe Tally, "#failure" do
  before :each do
    @tally = Tally.new
  end

  it "returns a formatted string of the number of #failures" do
    expect(@tally.failure).to eq("0 failures")
    @tally.failures!
    expect(@tally.failure).to eq("1 failure")
    @tally.failures!
    expect(@tally.failure).to eq("2 failures")
  end
end

RSpec.describe Tally, "#error" do
  before :each do
    @tally = Tally.new
  end

  it "returns a formatted string of the number of #errors" do
    expect(@tally.error).to eq("0 errors")
    @tally.errors!
    expect(@tally.error).to eq("1 error")
    @tally.errors!
    expect(@tally.error).to eq("2 errors")
  end
end

RSpec.describe Tally, "#guard" do
  before :each do
    @tally = Tally.new
  end

  it "returns a formatted string of the number of #guards" do
    expect(@tally.guard).to eq("0 guards")
    @tally.guards!
    expect(@tally.guard).to eq("1 guard")
    @tally.guards!
    expect(@tally.guard).to eq("2 guards")
  end
end

RSpec.describe Tally, "#format" do
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
    expect(@tally.format).to eq("1 file, 2 examples, 4 expectations, 0 failures, 1 error, 1 tagged")
  end

  it "includes guards if MSpec is in verify mode" do
    MSpec.register_mode :verify
    @tally.files!
    @tally.examples! 2
    @tally.expectations! 4
    @tally.errors!
    @tally.tagged!
    @tally.guards!
    expect(@tally.format).to eq(
      "1 file, 2 examples, 4 expectations, 0 failures, 1 error, 1 tagged, 1 guard"
    )
  end

  it "includes guards if MSpec is in report mode" do
    MSpec.register_mode :report
    @tally.files!
    @tally.examples! 2
    @tally.expectations! 4
    @tally.errors!
    @tally.tagged!
    @tally.guards! 2
    expect(@tally.format).to eq(
      "1 file, 2 examples, 4 expectations, 0 failures, 1 error, 1 tagged, 2 guards"
    )
  end

  it "includes guards if MSpec is in report_on mode" do
    MSpec.register_mode :report_on
    @tally.files!
    @tally.examples! 2
    @tally.expectations! 4
    @tally.errors!
    @tally.guards! 2
    expect(@tally.format).to eq(
      "1 file, 2 examples, 4 expectations, 0 failures, 1 error, 0 tagged, 2 guards"
    )
  end
end

RSpec.describe TallyAction, "#counter" do
  before :each do
    @tally = TallyAction.new
    @state = ExampleState.new("describe", "it")
  end

  it "returns the Tally object" do
    expect(@tally.counter).to be_kind_of(Tally)
  end
end

RSpec.describe TallyAction, "#load" do
  before :each do
    @tally = TallyAction.new
    @state = ExampleState.new("describe", "it")
  end

  it "increments the count returned by Tally#files" do
    @tally.load
    expect(@tally.counter.files).to eq(1)
  end
end

RSpec.describe TallyAction, "#expectation" do
  before :each do
    @tally = TallyAction.new
    @state = ExampleState.new("describe", "it")
  end

  it "increments the count returned by Tally#expectations" do
    @tally.expectation @state
    expect(@tally.counter.expectations).to eq(1)
  end
end

RSpec.describe TallyAction, "#example" do
  before :each do
    @tally = TallyAction.new
    @state = ExampleState.new("describe", "it")
  end

  it "increments counts returned by Tally#examples" do
    @tally.example @state, nil
    expect(@tally.counter.examples).to eq(1)
    expect(@tally.counter.expectations).to eq(0)
    expect(@tally.counter.failures).to eq(0)
    expect(@tally.counter.errors).to eq(0)
  end
end

RSpec.describe TallyAction, "#exception" do
  before :each do
    @tally = TallyAction.new
    @state = ExampleState.new("describe", "it")
  end

  it "increments counts returned by Tally#failures" do
    exc = ExceptionState.new nil, nil, SpecExpectationNotMetError.new("Failed!")
    @tally.exception exc
    expect(@tally.counter.examples).to eq(0)
    expect(@tally.counter.expectations).to eq(0)
    expect(@tally.counter.failures).to eq(1)
    expect(@tally.counter.errors).to eq(0)
  end
end

RSpec.describe TallyAction, "#exception" do
  before :each do
    @tally = TallyAction.new
    @state = ExampleState.new("describe", "it")
  end

  it "increments counts returned by Tally#errors" do
    exc = ExceptionState.new nil, nil, Exception.new("Error!")
    @tally.exception exc
    expect(@tally.counter.examples).to eq(0)
    expect(@tally.counter.expectations).to eq(0)
    expect(@tally.counter.failures).to eq(0)
    expect(@tally.counter.errors).to eq(1)
  end
end

RSpec.describe TallyAction, "#format" do
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
    expect(@tally.format).to eq("1 file, 1 example, 2 expectations, 1 failure, 0 errors, 0 tagged")
  end
end

RSpec.describe TallyAction, "#register" do
  before :each do
    @tally = TallyAction.new
    @state = ExampleState.new("describe", "it")
  end

  it "registers itself with MSpec for appropriate actions" do
    expect(MSpec).to receive(:register).with(:load, @tally)
    expect(MSpec).to receive(:register).with(:exception, @tally)
    expect(MSpec).to receive(:register).with(:example, @tally)
    expect(MSpec).to receive(:register).with(:tagged, @tally)
    expect(MSpec).to receive(:register).with(:expectation, @tally)
    @tally.register
  end
end

RSpec.describe TallyAction, "#unregister" do
  before :each do
    @tally = TallyAction.new
    @state = ExampleState.new("describe", "it")
  end

  it "unregisters itself with MSpec for appropriate actions" do
    expect(MSpec).to receive(:unregister).with(:load, @tally)
    expect(MSpec).to receive(:unregister).with(:exception, @tally)
    expect(MSpec).to receive(:unregister).with(:example, @tally)
    expect(MSpec).to receive(:unregister).with(:tagged, @tally)
    expect(MSpec).to receive(:unregister).with(:expectation, @tally)
    @tally.unregister
  end
end
