# frozen_string_literal: true
require "spec_helper"

describe Bundler::RubygemsIntegration do
  it "uses the same chdir lock as rubygems", :rubygems => "2.1" do
    expect(Bundler.rubygems.ext_lock).to eq(Gem::Ext::Builder::CHDIR_MONITOR)
  end

  context "#validate" do
    let(:spec) do
      Gem::Specification.new do |s|
        s.name = "to-validate"
        s.version = "1.0.0"
        s.loaded_from = __FILE__
      end
    end
    subject { Bundler.rubygems.validate(spec) }

    it "skips overly-strict gemspec validation", :rubygems => "< 1.7" do
      expect(spec).to_not receive(:validate)
      subject
    end

    it "validates with packaging mode disabled", :rubygems => "1.7" do
      expect(spec).to receive(:validate).with(false)
      subject
    end

    it "should set a summary to avoid an overly-strict error", :rubygems => "~> 1.7.0" do
      spec.summary = nil
      expect { subject }.not_to raise_error
      expect(spec.summary).to eq("")
    end

    context "with an invalid spec" do
      before do
        expect(spec).to receive(:validate).with(false).
          and_raise(Gem::InvalidSpecificationException.new("TODO is not an author"))
      end

      it "should raise a Gem::InvalidSpecificationException and produce a helpful warning message",
        :rubygems => "1.7" do
        expect { subject }.to raise_error(Gem::InvalidSpecificationException,
          "The gemspec at #{__FILE__} is not valid. "\
          "Please fix this gemspec.\nThe validation error was 'TODO is not an author'\n")
      end
    end
  end

  describe "#configuration" do
    it "handles Gem::SystemExitException errors" do
      allow(Gem).to receive(:configuration) { raise Gem::SystemExitException.new(1) }
      expect { Bundler.rubygems.configuration }.to raise_error(Gem::SystemExitException)
    end
  end

  describe "#fetch_all_remote_specs", :rubygems => ">= 2.0" do
    let(:uri) { URI("https://example.com") }
    let(:fetcher) { double("gem_remote_fetcher") }
    let(:specs_response) { Marshal.dump(["specs"]) }
    let(:prerelease_specs_response) { Marshal.dump(["prerelease_specs"]) }

    context "when a rubygems source mirror is set" do
      let(:orig_uri) { URI("http://zombo.com") }
      let(:remote_with_mirror) { double("remote", :uri => uri, :original_uri => orig_uri) }

      it "sets the 'X-Gemfile-Source' header containing the original source" do
        expect(Bundler.rubygems).to receive(:gem_remote_fetcher).twice.and_return(fetcher)
        expect(fetcher).to receive(:headers=).with("X-Gemfile-Source" => "http://zombo.com").twice
        expect(fetcher).to receive(:fetch_path).with(uri + "specs.4.8.gz").and_return(specs_response)
        expect(fetcher).to receive(:fetch_path).with(uri + "prerelease_specs.4.8.gz").and_return(prerelease_specs_response)
        result = Bundler.rubygems.fetch_all_remote_specs(remote_with_mirror)
        expect(result).to eq(%w(specs prerelease_specs))
      end
    end

    context "when there is no rubygems source mirror set" do
      let(:remote_no_mirror) { double("remote", :uri => uri, :original_uri => nil) }

      it "does not set the 'X-Gemfile-Source' header" do
        expect(Bundler.rubygems).to receive(:gem_remote_fetcher).twice.and_return(fetcher)
        expect(fetcher).to_not receive(:headers=)
        expect(fetcher).to receive(:fetch_path).with(uri + "specs.4.8.gz").and_return(specs_response)
        expect(fetcher).to receive(:fetch_path).with(uri + "prerelease_specs.4.8.gz").and_return(prerelease_specs_response)
        result = Bundler.rubygems.fetch_all_remote_specs(remote_no_mirror)
        expect(result).to eq(%w(specs prerelease_specs))
      end
    end
  end
end
