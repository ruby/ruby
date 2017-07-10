# frozen_string_literal: true
require "spec_helper"
require "bundler"
require "bundler/friendly_errors"
require "cgi"

describe Bundler, "friendly errors" do
  context "with invalid YAML in .gemrc" do
    before do
      File.open(Gem.configuration.config_file_name, "w") do |f|
        f.write "invalid: yaml: hah"
      end
    end

    after do
      FileUtils.rm(Gem.configuration.config_file_name)
    end

    it "reports a relevant friendly error message", :ruby => ">= 1.9", :rubygems => "< 2.5.0" do
      gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack"
      G

      bundle :install, :env => { "DEBUG" => true }

      expect(out).to include("Your RubyGems configuration")
      expect(out).to include("invalid YAML syntax")
      expect(out).to include("Psych::SyntaxError")
      expect(out).not_to include("ERROR REPORT TEMPLATE")
      expect(exitstatus).to eq(25) if exitstatus
    end

    it "reports a relevant friendly error message", :ruby => ">= 1.9", :rubygems => ">= 2.5.0" do
      gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack"
      G

      bundle :install, :env => { "DEBUG" => true }

      expect(err).to include("Failed to load #{home(".gemrc")}")
      expect(exitstatus).to eq(0) if exitstatus
    end
  end

  it "rescues Thor::AmbiguousTaskError and raises SystemExit" do
    expect do
      Bundler.with_friendly_errors do
        raise Thor::AmbiguousTaskError.new("")
      end
    end.to raise_error(SystemExit)
  end

  describe "#issues_url" do
    it "generates a search URL for the exception message" do
      exception = Exception.new("Exception message")

      expect(Bundler::FriendlyErrors.issues_url(exception)).to eq("https://github.com/bundler/bundler/search?q=Exception+message&type=Issues")
    end

    it "generates a search URL for only the first line of a multi-line exception message" do
      exception = Exception.new(<<END)
First line of the exception message
Second line of the exception message
END

      expect(Bundler::FriendlyErrors.issues_url(exception)).to eq("https://github.com/bundler/bundler/search?q=First+line+of+the+exception+message&type=Issues")
    end

    it "generates the url without colons" do
      exception = Exception.new(<<END)
Exception ::: with ::: colons :::
END
      issues_url = Bundler::FriendlyErrors.issues_url(exception)
      expect(issues_url).not_to include("%3A")
      expect(issues_url).to eq("https://github.com/bundler/bundler/search?q=#{CGI.escape("Exception     with     colons    ")}&type=Issues")
    end

    it "removes information after - for Errono::EACCES" do
      exception = Exception.new(<<END)
Errno::EACCES: Permission denied @ dir_s_mkdir - /Users/foo/bar/
END
      allow(exception).to receive(:is_a?).with(Errno).and_return(true)
      issues_url = Bundler::FriendlyErrors.issues_url(exception)
      expect(issues_url).not_to include("/Users/foo/bar")
      expect(issues_url).to eq("https://github.com/bundler/bundler/search?q=#{CGI.escape("Errno  EACCES  Permission denied @ dir_s_mkdir ")}&type=Issues")
    end
  end
end
