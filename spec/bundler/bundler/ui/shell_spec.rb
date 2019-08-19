# frozen_string_literal: true

RSpec.describe Bundler::UI::Shell do
  subject { described_class.new }

  before { subject.level = "debug" }

  describe "#info" do
    before { subject.level = "info" }
    it "prints to stdout" do
      expect { subject.info("info") }.to output("info\n").to_stdout
    end
  end

  describe "#confirm" do
    before { subject.level = "confirm" }
    it "prints to stdout" do
      expect { subject.confirm("confirm") }.to output("confirm\n").to_stdout
    end
  end

  describe "#warn" do
    before { subject.level = "warn" }
    it "prints to stderr" do
      expect { subject.warn("warning") }.to output("warning\n").to_stderr
    end
  end

  describe "#debug" do
    it "prints to stdout" do
      expect { subject.debug("debug") }.to output("debug\n").to_stdout
    end
  end

  describe "#error" do
    before { subject.level = "error" }

    it "prints to stderr" do
      expect { subject.error("error!!!") }.to output("error!!!\n").to_stderr
    end

    context "when stderr is closed" do
      it "doesn't report anything" do
        output = capture(:stderr, :closed => true) do
          subject.error("Something went wrong")
        end
        expect(output).to_not eq("Something went wrong\n")
      end
    end
  end
end
