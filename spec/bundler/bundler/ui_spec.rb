# frozen_string_literal: true

RSpec.describe Bundler::UI do
  describe Bundler::UI::Silent do
    it "has the same instance methods as Shell", :ruby => ">= 1.9" do
      shell = Bundler::UI::Shell
      methods = proc do |cls|
        cls.instance_methods.map do |i|
          m = shell.instance_method(i)
          [i, m.parameters]
        end.sort_by(&:first)
      end
      expect(methods.call(described_class)).to eq(methods.call(shell))
    end

    it "has the same instance class as Shell", :ruby => ">= 1.9" do
      shell = Bundler::UI::Shell
      methods = proc do |cls|
        cls.methods.map do |i|
          m = shell.method(i)
          [i, m.parameters]
        end.sort_by(&:first)
      end
      expect(methods.call(described_class)).to eq(methods.call(shell))
    end
  end

  describe Bundler::UI::Shell do
    let(:options) { {} }
    subject { described_class.new(options) }
    describe "debug?" do
      it "returns a boolean" do
        subject.level = :debug
        expect(subject.debug?).to eq(true)

        subject.level = :error
        expect(subject.debug?).to eq(false)
      end
    end
  end
end
