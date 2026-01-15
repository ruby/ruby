# frozen_string_literal: true

require "bundler/worker"

RSpec.describe Bundler::Worker do
  let(:size) { 5 }
  let(:name) { "Spec Worker" }
  let(:function) { proc {|object, worker_number| [object, worker_number] } }
  subject { described_class.new(size, name, function) }

  after { subject.stop }

  describe "#initialize" do
    context "when Thread.start raises ThreadError" do
      it "raises when no threads can be created" do
        allow(Thread).to receive(:start).and_raise(ThreadError, "error creating thread")

        expect { subject.enq "a" }.to raise_error(Bundler::ThreadCreationError, "Failed to create threads for the Spec Worker worker: error creating thread")
      end
    end
  end

  describe "handling interrupts" do
    let(:status) do
      pid = Process.fork do
        $stderr.reopen File.new("/dev/null", "w")
        Signal.trap "INT", previous_interrupt_handler
        subject.enq "a"
        subject.stop unless interrupt_before_stopping
        Process.kill "INT", Process.pid
      end

      Process.wait2(pid).last
    end

    before do
      skip "requires Process.fork" unless Process.respond_to?(:fork)
    end

    context "when interrupted before stopping" do
      let(:interrupt_before_stopping) { true }
      let(:previous_interrupt_handler) { ->(*) { exit 0 } }

      it "aborts" do
        expect(status.exitstatus).to eq(1)
      end
    end

    context "when interrupted after stopping" do
      let(:interrupt_before_stopping) { false }

      context "when the previous interrupt handler was the default" do
        let(:previous_interrupt_handler) { "DEFAULT" }

        it "uses the default interrupt handler" do
          expect(status).to be_signaled
        end
      end

      context "when the previous interrupt handler was customized" do
        let(:previous_interrupt_handler) { ->(*) { exit 42 } }

        it "restores the custom interrupt handler after stopping" do
          expect(status.exitstatus).to eq(42)
        end
      end
    end
  end
end
