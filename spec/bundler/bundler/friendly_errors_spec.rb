# frozen_string_literal: true

require "bundler"
require "bundler/friendly_errors"
require "cgi"

RSpec.describe Bundler, "friendly errors" do
  context "with invalid YAML in .gemrc" do
    before do
      File.open(home(".gemrc"), "w") do |f|
        f.write "invalid: yaml: hah"
      end
    end

    after do
      FileUtils.rm(home(".gemrc"))
    end

    it "reports a relevant friendly error message" do
      gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"
      G

      bundle :install, :env => { "DEBUG" => "true" }

      expect(err).to include("Failed to load #{home(".gemrc")}")
    end
  end

  it "calls log_error in case of exception" do
    exception = Exception.new
    expect(Bundler::FriendlyErrors).to receive(:exit_status).with(exception).and_return(1)
    expect do
      Bundler.with_friendly_errors do
        raise exception
      end
    end.to raise_error(SystemExit)
  end

  it "calls exit_status on exception" do
    exception = Exception.new
    expect(Bundler::FriendlyErrors).to receive(:log_error).with(exception)
    expect do
      Bundler.with_friendly_errors do
        raise exception
      end
    end.to raise_error(SystemExit)
  end

  describe "#log_error" do
    shared_examples "Bundler.ui receive error" do |error, message|
      it "" do
        expect(Bundler.ui).to receive(:error).with(message || error.message)
        Bundler::FriendlyErrors.log_error(error)
      end
    end

    shared_examples "Bundler.ui receive trace" do |error|
      it "" do
        expect(Bundler.ui).to receive(:trace).with(error)
        Bundler::FriendlyErrors.log_error(error)
      end
    end

    context "YamlSyntaxError" do
      it_behaves_like "Bundler.ui receive error", Bundler::YamlSyntaxError.new(StandardError.new, "sample_message")

      it "Bundler.ui receive trace" do
        std_error = StandardError.new
        exception = Bundler::YamlSyntaxError.new(std_error, "sample_message")
        expect(Bundler.ui).to receive(:trace).with(std_error)
        Bundler::FriendlyErrors.log_error(exception)
      end
    end

    context "Dsl::DSLError, GemspecError" do
      it_behaves_like "Bundler.ui receive error", Bundler::Dsl::DSLError.new("description", "dsl_path", "backtrace")
      it_behaves_like "Bundler.ui receive error", Bundler::GemspecError.new
    end

    context "GemRequireError" do
      let(:orig_error) { StandardError.new }
      let(:error) { Bundler::GemRequireError.new(orig_error, "sample_message") }

      before do
        allow(orig_error).to receive(:backtrace).and_return([])
      end

      it "Bundler.ui receive error" do
        expect(Bundler.ui).to receive(:error).with(error.message)
        Bundler::FriendlyErrors.log_error(error)
      end

      it "writes to Bundler.ui.trace" do
        expect(Bundler.ui).to receive(:trace).with(orig_error)
        Bundler::FriendlyErrors.log_error(error)
      end
    end

    context "BundlerError" do
      it "Bundler.ui receive error" do
        error = Bundler::BundlerError.new
        expect(Bundler.ui).to receive(:error).with(error.message, :wrap => true)
        Bundler::FriendlyErrors.log_error(error)
      end
      it_behaves_like "Bundler.ui receive trace", Bundler::BundlerError.new
    end

    context "Thor::Error" do
      it_behaves_like "Bundler.ui receive error", Bundler::Thor::Error.new
    end

    context "LoadError" do
      let(:error) { LoadError.new("cannot load such file -- openssl") }

      before do
        allow(error).to receive(:backtrace).and_return(["backtrace"])
      end

      it "Bundler.ui receive error" do
        expect(Bundler.ui).to receive(:error).with("\nCould not load OpenSSL. LoadError: cannot load such file -- openssl\nbacktrace")
        Bundler::FriendlyErrors.log_error(error)
      end
    end

    context "Interrupt" do
      it "Bundler.ui receive error" do
        expect(Bundler.ui).to receive(:error).with("\nQuitting...")
        Bundler::FriendlyErrors.log_error(Interrupt.new)
      end
      it_behaves_like "Bundler.ui receive trace", Interrupt.new
    end

    context "Gem::InvalidSpecificationException" do
      it "Bundler.ui receive error" do
        error = Gem::InvalidSpecificationException.new
        expect(Bundler.ui).to receive(:error).with(error.message, :wrap => true)
        Bundler::FriendlyErrors.log_error(error)
      end
    end

    context "SystemExit" do
      # Does nothing
    end

    context "Java::JavaLang::OutOfMemoryError" do
      module Java
        module JavaLang
          class OutOfMemoryError < StandardError; end
        end
      end

      it "Bundler.ui receive error" do
        error = Java::JavaLang::OutOfMemoryError.new
        expect(Bundler.ui).to receive(:error).with(/JVM has run out of memory/)
        Bundler::FriendlyErrors.log_error(error)
      end
    end

    context "unexpected error" do
      it "calls request_issue_report_for with error" do
        error = StandardError.new
        expect(Bundler::FriendlyErrors).to receive(:request_issue_report_for).with(error)
        Bundler::FriendlyErrors.log_error(error)
      end
    end
  end

  describe "#exit_status" do
    it "calls status_code for BundlerError" do
      error = Bundler::BundlerError.new
      expect(error).to receive(:status_code).and_return("sample_status_code")
      expect(Bundler::FriendlyErrors.exit_status(error)).to eq("sample_status_code")
    end

    it "returns 15 for Thor::Error" do
      error = Bundler::Thor::Error.new
      expect(Bundler::FriendlyErrors.exit_status(error)).to eq(15)
    end

    it "calls status for SystemExit" do
      error = SystemExit.new
      expect(error).to receive(:status).and_return("sample_status")
      expect(Bundler::FriendlyErrors.exit_status(error)).to eq("sample_status")
    end

    it "returns 1 in other cases" do
      error = StandardError.new
      expect(Bundler::FriendlyErrors.exit_status(error)).to eq(1)
    end
  end

  describe "#request_issue_report_for" do
    it "calls relevant methods for Bundler.ui" do
      expect(Bundler.ui).not_to receive(:info)
      expect(Bundler.ui).to receive(:error).exactly(3).times
      expect(Bundler.ui).not_to receive(:warn)
      Bundler::FriendlyErrors.request_issue_report_for(StandardError.new)
    end

    it "includes error class, message and backlog" do
      error = StandardError.new
      allow(Bundler::FriendlyErrors).to receive(:issues_url).and_return("")

      expect(error).to receive(:class).at_least(:once)
      expect(error).to receive(:message).at_least(:once)
      expect(error).to receive(:backtrace).at_least(:once)
      Bundler::FriendlyErrors.request_issue_report_for(error)
    end
  end

  describe "#issues_url" do
    it "generates a search URL for the exception message" do
      exception = Exception.new("Exception message")

      expect(Bundler::FriendlyErrors.issues_url(exception)).to eq("https://github.com/rubygems/rubygems/search?q=Exception+message&type=Issues")
    end

    it "generates a search URL for only the first line of a multi-line exception message" do
      exception = Exception.new(<<END)
First line of the exception message
Second line of the exception message
END

      expect(Bundler::FriendlyErrors.issues_url(exception)).to eq("https://github.com/rubygems/rubygems/search?q=First+line+of+the+exception+message&type=Issues")
    end

    it "generates the url without colons" do
      exception = Exception.new(<<END)
Exception ::: with ::: colons :::
END
      issues_url = Bundler::FriendlyErrors.issues_url(exception)
      expect(issues_url).not_to include("%3A")
      expect(issues_url).to eq("https://github.com/rubygems/rubygems/search?q=#{CGI.escape("Exception     with     colons    ")}&type=Issues")
    end

    it "removes information after - for Errono::EACCES" do
      exception = Exception.new(<<END)
Errno::EACCES: Permission denied @ dir_s_mkdir - /Users/foo/bar/
END
      allow(exception).to receive(:is_a?).with(Errno).and_return(true)
      issues_url = Bundler::FriendlyErrors.issues_url(exception)
      expect(issues_url).not_to include("/Users/foo/bar")
      expect(issues_url).to eq("https://github.com/rubygems/rubygems/search?q=#{CGI.escape("Errno  EACCES  Permission denied @ dir_s_mkdir ")}&type=Issues")
    end
  end
end
