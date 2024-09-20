# frozen_string_literal: true

require "bundler/fetcher"

RSpec.describe Bundler::Fetcher do
  let(:uri) { Gem::URI("https://example.com") }
  let(:remote) { double("remote", uri: uri, original_uri: nil) }

  subject(:fetcher) { Bundler::Fetcher.new(remote) }

  before do
    allow(Bundler).to receive(:root) { Pathname.new("root") }
  end

  describe "#connection" do
    context "when Gem.configuration doesn't specify http_proxy" do
      it "specify no http_proxy" do
        expect(fetcher.http_proxy).to be_nil
      end
      it "consider environment vars when determine proxy" do
        with_env_vars("HTTP_PROXY" => "http://proxy-example.com") do
          expect(fetcher.http_proxy).to match("http://proxy-example.com")
        end
      end
    end
    context "when Gem.configuration specifies http_proxy " do
      let(:proxy) { "http://proxy-example2.com" }
      before do
        allow(Gem.configuration).to receive(:[]).with(:http_proxy).and_return(proxy)
      end
      it "consider Gem.configuration when determine proxy" do
        expect(fetcher.http_proxy).to match("http://proxy-example2.com")
      end
      it "consider Gem.configuration when determine proxy" do
        with_env_vars("HTTP_PROXY" => "http://proxy-example.com") do
          expect(fetcher.http_proxy).to match("http://proxy-example2.com")
        end
      end
      context "when the proxy is :no_proxy" do
        let(:proxy) { :no_proxy }
        it "does not set a proxy" do
          expect(fetcher.http_proxy).to be_nil
        end
      end
    end

    context "when a rubygems source mirror is set" do
      let(:orig_uri) { Gem::URI("http://zombo.com") }
      let(:remote_with_mirror) do
        double("remote", uri: uri, original_uri: orig_uri, anonymized_uri: uri)
      end

      let(:fetcher) { Bundler::Fetcher.new(remote_with_mirror) }

      it "sets the 'X-Gemfile-Source' header containing the original source" do
        expect(
          fetcher.send(:connection).override_headers["X-Gemfile-Source"]
        ).to eq("http://zombo.com")
      end
    end

    context "when there is no rubygems source mirror set" do
      let(:remote_no_mirror) do
        double("remote", uri: uri, original_uri: nil, anonymized_uri: uri)
      end

      let(:fetcher) { Bundler::Fetcher.new(remote_no_mirror) }

      it "does not set the 'X-Gemfile-Source' header" do
        expect(fetcher.send(:connection).override_headers["X-Gemfile-Source"]).to be_nil
      end
    end

    context "when there are proxy environment variable(s) set" do
      it "consider http_proxy" do
        with_env_vars("HTTP_PROXY" => "http://proxy-example3.com") do
          expect(fetcher.http_proxy).to match("http://proxy-example3.com")
        end
      end
      it "consider no_proxy" do
        with_env_vars("HTTP_PROXY" => "http://proxy-example4.com", "NO_PROXY" => ".example.com,.example.net") do
          expect(
            fetcher.send(:connection).no_proxy
          ).to eq([".example.com", ".example.net"])
        end
      end
    end

    context "when no ssl configuration is set" do
      it "no cert" do
        expect(fetcher.send(:connection).cert).to be_nil
        expect(fetcher.send(:connection).key).to be_nil
      end
    end

    context "when bunder ssl ssl configuration is set" do
      before do
        cert = File.join(Spec::Path.tmpdir, "cert")
        File.open(cert, "w") {|f| f.write "PEM" }
        allow(Bundler.settings).to receive(:[]).and_return(nil)
        allow(Bundler.settings).to receive(:[]).with(:ssl_client_cert).and_return(cert)
        expect(OpenSSL::X509::Certificate).to receive(:new).with("PEM").and_return("cert")
        expect(OpenSSL::PKey::RSA).to receive(:new).with("PEM").and_return("key")
      end
      after do
        FileUtils.rm File.join(Spec::Path.tmpdir, "cert")
      end
      it "use bundler configuration" do
        expect(fetcher.send(:connection).cert).to eq("cert")
        expect(fetcher.send(:connection).key).to eq("key")
      end
    end

    context "when gem ssl configuration is set" do
      before do
        allow(Gem.configuration).to receive_messages(
          http_proxy: nil,
          ssl_client_cert: "cert",
          ssl_ca_cert: "ca"
        )
        expect(File).to receive(:read).and_return("")
        expect(OpenSSL::X509::Certificate).to receive(:new).and_return("cert")
        expect(OpenSSL::PKey::RSA).to receive(:new).and_return("key")
        store = double("ca store")
        expect(store).to receive(:add_file)
        expect(OpenSSL::X509::Store).to receive(:new).and_return(store)
      end
      it "use gem configuration" do
        expect(fetcher.send(:connection).cert).to eq("cert")
        expect(fetcher.send(:connection).key).to eq("key")
      end
    end
  end

  describe "#user_agent" do
    it "builds user_agent with current ruby version and Bundler settings" do
      allow(Bundler.settings).to receive(:all).and_return(%w[foo bar])
      expect(fetcher.user_agent).to match(%r{bundler/(\d.)})
      expect(fetcher.user_agent).to match(%r{rubygems/(\d.)})
      expect(fetcher.user_agent).to match(%r{ruby/(\d.)})
      expect(fetcher.user_agent).to match(%r{options/foo,bar})
    end

    describe "include CI information" do
      it "from one CI" do
        with_env_vars("CI" => nil, "JENKINS_URL" => "foo") do
          ci_part = fetcher.user_agent.split(" ").find {|x| x.start_with?("ci/") }
          cis = ci_part.split("/").last.split(",")
          expect(cis).to include("jenkins")
          expect(cis).not_to include("ci")
        end
      end

      it "from many CI" do
        with_env_vars("CI" => "true", "SEMAPHORE" => nil, "TRAVIS" => "foo", "GITLAB_CI" => "gitlab", "CI_NAME" => "MY_ci") do
          ci_part = fetcher.user_agent.split(" ").find {|x| x.start_with?("ci/") }
          cis = ci_part.split("/").last.split(",")
          expect(cis).to include("ci", "gitlab", "my_ci", "travis")
          expect(cis).not_to include("semaphore")
        end
      end
    end
  end

  describe "#fetch_spec" do
    let(:name) { "name" }
    let(:version) { "1.3.17" }
    let(:platform) { "platform" }
    let(:downloader) { double("downloader") }
    let(:body) { double(Gem::Net::HTTP::Get, body: downloaded_data) }

    context "when attempting to load a Gem::Specification" do
      let(:spec) { Gem::Specification.new(name, version) }
      let(:downloaded_data) { Zlib::Deflate.deflate(Marshal.dump(spec)) }

      it "returns the spec" do
        expect(Bundler::Fetcher::Downloader).to receive(:new).and_return(downloader)
        expect(downloader).to receive(:fetch).once.and_return(body)
        result = fetcher.fetch_spec([name, version, platform])
        expect(result).to eq(spec)
      end
    end

    context "when attempting to load an unexpected class" do
      let(:downloaded_data) { Zlib::Deflate.deflate(Marshal.dump(3)) }

      it "raises a HTTPError error" do
        expect(Bundler::Fetcher::Downloader).to receive(:new).and_return(downloader)
        expect(downloader).to receive(:fetch).once.and_return(body)
        expect { fetcher.fetch_spec([name, version, platform]) }.to raise_error(Bundler::HTTPError, /Gemspec .* contained invalid data/i)
      end
    end
  end

  describe "#specs_with_retry" do
    let(:downloader)  { double(:downloader) }
    let(:remote)      { double(:remote, cache_slug: "slug", uri: uri, original_uri: nil, anonymized_uri: uri) }
    let(:compact_index) { double(Bundler::Fetcher::CompactIndex, available?: true, api_fetcher?: true) }
    let(:dependency)    { double(Bundler::Fetcher::Dependency, available?: true, api_fetcher?: true) }
    let(:index)         { double(Bundler::Fetcher::Index, available?: true, api_fetcher?: false) }

    before do
      allow(Bundler::Fetcher::CompactIndex).to receive(:new).and_return(compact_index)
      allow(Bundler::Fetcher::Dependency).to receive(:new).and_return(dependency)
      allow(Bundler::Fetcher::Index).to receive(:new).and_return(index)
    end

    it "picks the first fetcher that works" do
      expect(compact_index).to receive(:specs).with("name").and_return([["name", "1.2.3", "ruby"]])
      expect(dependency).not_to receive(:specs)
      expect(index).not_to receive(:specs)
      fetcher.specs_with_retry("name", double(Bundler::Source::Rubygems))
    end

    context "when APIs are not available" do
      before do
        allow(compact_index).to receive(:available?).and_return(false)
        allow(dependency).to receive(:available?).and_return(false)
      end

      it "uses the index" do
        expect(compact_index).not_to receive(:specs)
        expect(dependency).not_to receive(:specs)
        expect(index).to receive(:specs).with("name").and_return([["name", "1.2.3", "ruby"]])

        fetcher.specs_with_retry("name", double(Bundler::Source::Rubygems))
      end
    end
  end

  describe "#api_fetcher?" do
    let(:downloader)  { double(:downloader) }
    let(:remote)      { double(:remote, cache_slug: "slug", uri: uri, original_uri: nil, anonymized_uri: uri) }
    let(:compact_index) { double(Bundler::Fetcher::CompactIndex, available?: false, api_fetcher?: true) }
    let(:dependency)    { double(Bundler::Fetcher::Dependency, available?: false, api_fetcher?: true) }
    let(:index)         { double(Bundler::Fetcher::Index, available?: true, api_fetcher?: false) }

    before do
      allow(Bundler::Fetcher::CompactIndex).to receive(:new).and_return(compact_index)
      allow(Bundler::Fetcher::Dependency).to receive(:new).and_return(dependency)
      allow(Bundler::Fetcher::Index).to receive(:new).and_return(index)
    end

    context "when an api fetcher is available" do
      before do
        allow(compact_index).to receive(:available?).and_return(true)
      end

      it "is truthy" do
        expect(fetcher).to be_api_fetcher
      end
    end

    context "when only the index fetcher is available" do
      it "is falsey" do
        expect(fetcher).not_to be_api_fetcher
      end
    end
  end
end
