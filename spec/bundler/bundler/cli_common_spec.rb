# frozen_string_literal: true

require "bundler/cli"

RSpec.describe Bundler::CLI::Common do
  describe "gem_not_found_message" do
    it "should suggest alternate gem names" do
      message = subject.gem_not_found_message("ralis", ["BOGUS"])
      expect(message).to match("Could not find gem 'ralis'.$")
      message = subject.gem_not_found_message("ralis", ["rails"])
      expect(message).to match("Did you mean 'rails'?")
      message = subject.gem_not_found_message("Rails", ["rails"])
      expect(message).to match("Did you mean 'rails'?")
      message = subject.gem_not_found_message("meail", %w[email fail eval])
      expect(message).to match("Did you mean 'email'?")
      message = subject.gem_not_found_message("nokogri", %w[nokogiri rails sidekiq dog])
      expect(message).to match("Did you mean 'nokogiri'?")
      message = subject.gem_not_found_message("methosd", %w[method methods bogus])
      expect(message).to match(/Did you mean 'method(|s)' or 'method(|s)'?/)
    end
  end

  describe "validate_cooldown!" do
    def warning(inspected)
      "Invalid cooldown value #{inspected}, so the cooldown is disabled for all sources. " \
        "Expected a non-negative integer number of days."
    end

    it "rejects a negative flag value" do
      expect { subject.validate_cooldown!(-1) }.to raise_error(
        Bundler::InvalidOption, "Expected `--cooldown` to be a non-negative integer, got -1"
      )
    end

    it "accepts a non-negative flag value without reading the settings" do
      expect(Bundler.ui).not_to receive(:warn)
      expect { subject.validate_cooldown!(0) }.not_to raise_error
      expect { subject.validate_cooldown!(7) }.not_to raise_error
    end

    context "when no flag is given" do
      it "warns when the configured value is not a number" do
        Bundler.settings.temporary(cooldown: "abc") do
          expect(Bundler.ui).to receive(:warn).with(warning('"abc"')).once
          subject.validate_cooldown!(nil)
        end
      end

      it "warns when the configured value is negative" do
        Bundler.settings.temporary(cooldown: "-5") do
          expect(Bundler.ui).to receive(:warn).with(warning('"-5"')).once
          subject.validate_cooldown!(nil)
        end
      end

      it "warns when the configured value is only partly a number" do
        Bundler.settings.temporary(cooldown: "7days") do
          expect(Bundler.ui).to receive(:warn).with(warning('"7days"')).once
          subject.validate_cooldown!(nil)
        end
      end

      it "stays quiet for a valid value, an explicit 0, and an unset value" do
        expect(Bundler.ui).not_to receive(:warn)
        Bundler.settings.temporary(cooldown: "7") { subject.validate_cooldown!(nil) }
        Bundler.settings.temporary(cooldown: "0") { subject.validate_cooldown!(nil) }
        subject.validate_cooldown!(nil)
      end
    end
  end
end
