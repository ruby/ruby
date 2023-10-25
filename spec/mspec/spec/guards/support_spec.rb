require 'spec_helper'
require 'mspec/guards'

RSpec.describe Object, "#not_supported_on" do
  before :each do
    ScratchPad.clear
  end

  it "raises an Exception when passed :ruby" do
    stub_const "RUBY_ENGINE", "jruby"
    expect {
      not_supported_on(:ruby) { ScratchPad.record :yield }
    }.to raise_error(Exception)
    expect(ScratchPad.recorded).not_to eq(:yield)
  end

  it "does not yield when #implementation? returns true" do
    stub_const "RUBY_ENGINE", "jruby"
    not_supported_on(:jruby) { ScratchPad.record :yield }
    expect(ScratchPad.recorded).not_to eq(:yield)
  end

  it "yields when #standard? returns true" do
    stub_const "RUBY_ENGINE", "ruby"
    not_supported_on(:rubinius) { ScratchPad.record :yield }
    expect(ScratchPad.recorded).to eq(:yield)
  end

  it "yields when #implementation? returns false" do
    stub_const "RUBY_ENGINE", "jruby"
    not_supported_on(:rubinius) { ScratchPad.record :yield }
    expect(ScratchPad.recorded).to eq(:yield)
  end
end

RSpec.describe Object, "#not_supported_on" do
  before :each do
    @guard = SupportedGuard.new
    allow(SupportedGuard).to receive(:new).and_return(@guard)
  end

  it "sets the name of the guard to :not_supported_on" do
    not_supported_on(:rubinius) { }
    expect(@guard.name).to eq(:not_supported_on)
  end

  it "calls #unregister even when an exception is raised in the guard block" do
    expect(@guard).to receive(:match?).and_return(false)
    expect(@guard).to receive(:unregister)
    expect do
      not_supported_on(:rubinius) { raise Exception }
    end.to raise_error(Exception)
  end
end
