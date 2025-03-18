# frozen_string_literal: true

RSpec.describe Bundler::RubygemsIntegration do
  context "#validate" do
    let(:spec) do
      Gem::Specification.new do |s|
        s.name = "to-validate"
        s.version = "1.0.0"
        s.loaded_from = __FILE__
      end
    end
    subject { Bundler.rubygems.validate(spec) }

    it "validates for resolution" do
      expect(spec).to receive(:validate_for_resolution)
      subject
    end

    context "with an invalid spec" do
      before do
        expect(spec).to receive(:validate_for_resolution).
          and_raise(Gem::InvalidSpecificationException.new("TODO is not an author"))
      end

      it "should raise a Gem::InvalidSpecificationException and produce a helpful warning message" do
        expect { subject }.to raise_error(Gem::InvalidSpecificationException,
          "The gemspec at #{__FILE__} is not valid. "\
          "Please fix this gemspec.\nThe validation error was 'TODO is not an author'\n")
      end
    end
  end

  describe "#download_gem" do
    let(:bundler_retry) { double(Bundler::Retry) }
    let(:cache_dir) { "#{Gem.path.first}/cache" }
    let(:spec) do
      spec = Gem::Specification.new("Foo", Gem::Version.new("2.5.2"))
      spec.remote = Bundler::Source::Rubygems::Remote.new(uri.to_s)
      spec
    end
    let(:fetcher) { double("gem_remote_fetcher") }

    context "when uri is public" do
      let(:uri) { Gem::URI.parse("https://foo.bar") }

      it "successfully downloads gem with retries" do
        expect(Bundler::Retry).to receive(:new).with("download gem from #{uri}/").
          and_return(bundler_retry)
        expect(bundler_retry).to receive(:attempts).and_yield
        expect(fetcher).to receive(:cache_update_path)

        Bundler.rubygems.download_gem(spec, uri, cache_dir, fetcher)
      end
    end

    context "when uri contains userinfo part" do
      let(:uri) { Gem::URI.parse("https://#{userinfo}@foo.bar") }

      context "with user and password" do
        let(:userinfo) { "user:password" }

        it "successfully downloads gem with retries with filtered log" do
          expect(Bundler::Retry).to receive(:new).with("download gem from https://user:REDACTED@foo.bar/").
            and_return(bundler_retry)
          expect(bundler_retry).to receive(:attempts).and_yield
          expect(fetcher).to receive(:cache_update_path)

          Bundler.rubygems.download_gem(spec, uri, cache_dir, fetcher)
        end
      end

      context "with token [as user]" do
        let(:userinfo) { "token" }

        it "successfully downloads gem with retries with filtered log" do
          expect(Bundler::Retry).to receive(:new).with("download gem from https://REDACTED@foo.bar/").
            and_return(bundler_retry)
          expect(bundler_retry).to receive(:attempts).and_yield
          expect(fetcher).to receive(:cache_update_path)

          Bundler.rubygems.download_gem(spec, uri, cache_dir, fetcher)
        end
      end
    end
  end

  describe "#fetch_all_remote_specs" do
    let(:uri) { "https://example.com" }
    let(:fetcher) { double("gem_remote_fetcher") }
    let(:specs_response) { Marshal.dump(["specs"]) }
    let(:prerelease_specs_response) { Marshal.dump(["prerelease_specs"]) }

    context "when a rubygems source mirror is set" do
      let(:orig_uri) { Gem::URI("http://zombo.com") }
      let(:remote_with_mirror) { double("remote", uri: uri, original_uri: orig_uri) }

      it "sets the 'X-Gemfile-Source' header containing the original source" do
        expect(fetcher).to receive(:fetch_path).with(uri + "specs.4.8.gz").and_return(specs_response)
        expect(fetcher).to receive(:fetch_path).with(uri + "prerelease_specs.4.8.gz").and_return(prerelease_specs_response)
        result = Bundler.rubygems.fetch_all_remote_specs(remote_with_mirror, fetcher)
        expect(result).to eq(%w[specs prerelease_specs])
      end
    end

    context "when there is no rubygems source mirror set" do
      let(:remote_no_mirror) { double("remote", uri: uri, original_uri: nil) }

      it "does not set the 'X-Gemfile-Source' header" do
        expect(fetcher).to receive(:fetch_path).with(uri + "specs.4.8.gz").and_return(specs_response)
        expect(fetcher).to receive(:fetch_path).with(uri + "prerelease_specs.4.8.gz").and_return(prerelease_specs_response)
        result = Bundler.rubygems.fetch_all_remote_specs(remote_no_mirror, fetcher)
        expect(result).to eq(%w[specs prerelease_specs])
      end
    end

    context "when loading an unexpected class" do
      let(:remote_no_mirror) { double("remote", uri: uri, original_uri: nil) }
      let(:unexpected_specs_response) { Marshal.dump(3) }

      it "raises a MarshalError error" do
        expect(fetcher).to receive(:fetch_path).with(uri + "specs.4.8.gz").and_return(unexpected_specs_response)
        expect { Bundler.rubygems.fetch_all_remote_specs(remote_no_mirror, fetcher) }.to raise_error(Bundler::MarshalError, /unexpected class/i)
      end
    end
  end
end
