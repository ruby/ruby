# frozen_string_literal: true

RSpec.describe Bundler::Settings::Validator do
  describe ".validate!" do
    def validate!(key, value, settings)
      transformed_key = Bundler.settings.key_for(key)
      if value.nil?
        settings.delete(transformed_key)
      else
        settings[transformed_key] = value
      end
      described_class.validate!(key, value, settings)
      settings
    end

    it "path and path.system are mutually exclusive" do
      expect(validate!("path", "bundle", {})).to eq("BUNDLE_PATH" => "bundle")
      expect(validate!("path", "bundle", "BUNDLE_PATH__SYSTEM" => false)).to eq("BUNDLE_PATH" => "bundle")
      expect(validate!("path", "bundle", "BUNDLE_PATH__SYSTEM" => true)).to eq("BUNDLE_PATH" => "bundle")
      expect(validate!("path", nil, "BUNDLE_PATH__SYSTEM" => true)).to eq("BUNDLE_PATH__SYSTEM" => true)
      expect(validate!("path", nil, "BUNDLE_PATH__SYSTEM" => false)).to eq("BUNDLE_PATH__SYSTEM" => false)
      expect(validate!("path", nil, {})).to eq({})

      expect(validate!("path.system", true, "BUNDLE_PATH" => "bundle")).to eq("BUNDLE_PATH__SYSTEM" => true)
      expect(validate!("path.system", false, "BUNDLE_PATH" => "bundle")).to eq("BUNDLE_PATH" => "bundle", "BUNDLE_PATH__SYSTEM" => false)
      expect(validate!("path.system", nil, "BUNDLE_PATH" => "bundle")).to eq("BUNDLE_PATH" => "bundle")
      expect(validate!("path.system", true, {})).to eq("BUNDLE_PATH__SYSTEM" => true)
      expect(validate!("path.system", false, {})).to eq("BUNDLE_PATH__SYSTEM" => false)
      expect(validate!("path.system", nil, {})).to eq({})
    end

    it "a group cannot be in both `with` & `without` simultaneously" do
      expect do
        validate!("with", "", {})
        validate!("with", nil, {})
        validate!("with", "", "BUNDLE_WITHOUT" => "a")
        validate!("with", nil, "BUNDLE_WITHOUT" => "a")
        validate!("with", "b:c", "BUNDLE_WITHOUT" => "a")

        validate!("without", "", {})
        validate!("without", nil, {})
        validate!("without", "", "BUNDLE_WITH" => "a")
        validate!("without", nil, "BUNDLE_WITH" => "a")
        validate!("without", "b:c", "BUNDLE_WITH" => "a")
      end.not_to raise_error

      expect { validate!("with", "b:c", "BUNDLE_WITHOUT" => "c:d") }.to raise_error Bundler::InvalidOption, strip_whitespace(<<-EOS).strip
        Setting `with` to "b:c" failed:
         - a group cannot be in both `with` & `without` simultaneously
         - `without` is current set to [:c, :d]
         - the `c` groups conflict
      EOS

      expect { validate!("without", "b:c", "BUNDLE_WITH" => "c:d") }.to raise_error Bundler::InvalidOption, strip_whitespace(<<-EOS).strip
        Setting `without` to "b:c" failed:
         - a group cannot be in both `with` & `without` simultaneously
         - `with` is current set to [:c, :d]
         - the `c` groups conflict
      EOS
    end
  end

  describe described_class::Rule do
    let(:keys) { %w[key] }
    let(:description) { "rule description" }
    let(:validate) { proc { raise "validate called!" } }
    subject(:rule) { described_class.new(keys, description, &validate) }

    describe "#validate!" do
      it "calls the block" do
        expect { rule.validate!("key", nil, {}) }.to raise_error(RuntimeError, /validate called!/)
      end
    end

    describe "#fail!" do
      it "raises with a helpful message" do
        expect { subject.fail!("key", "value", "reason1", "reason2") }.to raise_error Bundler::InvalidOption, strip_whitespace(<<-EOS).strip
          Setting `key` to "value" failed:
           - rule description
           - reason1
           - reason2
        EOS
      end
    end

    describe "#set" do
      it "works when the value has not changed" do
        allow(Bundler.ui).to receive(:info).never

        subject.set({}, "key", nil)
        subject.set({ "BUNDLE_KEY" => "value" }, "key", "value")
      end

      it "prints out when the value is changing" do
        settings = {}

        expect(Bundler.ui).to receive(:info).with("Setting `key` to \"value\", since rule description, reason1")
        subject.set(settings, "key", "value", "reason1")
        expect(settings).to eq("BUNDLE_KEY" => "value")

        expect(Bundler.ui).to receive(:info).with("Setting `key` to \"value2\", since rule description, reason2")
        subject.set(settings, "key", "value2", "reason2")
        expect(settings).to eq("BUNDLE_KEY" => "value2")

        expect(Bundler.ui).to receive(:info).with("Setting `key` to nil, since rule description, reason3")
        subject.set(settings, "key", nil, "reason3")
        expect(settings).to eq({})
      end
    end
  end
end
