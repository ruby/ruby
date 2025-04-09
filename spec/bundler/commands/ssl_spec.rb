# frozen_string_literal: true

require "bundler/cli"
require "bundler/cli/doctor"
require "bundler/cli/doctor/ssl"

RSpec.describe "bundle doctor ssl" do
  before(:each) do
    @previous_level = Bundler.ui.level
    Bundler.ui.instance_variable_get(:@warning_history).clear
    Bundler.ui.level = "info"
  end

  after(:each) do
    Bundler.ui.level = @previous_level
  end

  context "when a diagnostic fails" do
    it "prints the diagnostic when openssl can't be loaded" do
      subject = Bundler::CLI::Doctor::SSL.new({})
      allow(subject).to receive(:require).with("openssl").and_raise(LoadError)

      expected_err = <<~MSG
        Oh no! Your Ruby doesn't have OpenSSL, so it can't connect to rubygems.org.
        You'll need to recompile or reinstall Ruby with OpenSSL support and try again.
      MSG

      expect { subject.run }.to output("").to_stdout.and output(expected_err).to_stderr
    end
  end

  context "when no diagnostic fails" do
    it "prints the SSL environment" do
      expected_out = <<~MSG
        Here's your OpenSSL environment:

        OpenSSL:       #{OpenSSL::VERSION}
        Compiled with: #{OpenSSL::OPENSSL_VERSION}
        Loaded with:   #{OpenSSL::OPENSSL_LIBRARY_VERSION}
      MSG

      subject = Bundler::CLI::Doctor::SSL.new({})
      expect { subject.run }.to output(expected_out).to_stdout.and output("").to_stderr
    end
  end
end
