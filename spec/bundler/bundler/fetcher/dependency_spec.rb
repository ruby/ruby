# frozen_string_literal: true
require "spec_helper"

describe Bundler::Fetcher::Dependency do
  let(:downloader)  { double(:downloader) }
  let(:remote)      { double(:remote, :uri => URI("http://localhost:5000")) }
  let(:display_uri) { "http://sample_uri.com" }

  subject { described_class.new(downloader, remote, display_uri) }

  describe "#available?" do
    let(:dependency_api_uri) { double(:dependency_api_uri) }
    let(:fetched_spec)       { double(:fetched_spec) }

    before do
      allow(subject).to receive(:dependency_api_uri).and_return(dependency_api_uri)
      allow(downloader).to receive(:fetch).with(dependency_api_uri).and_return(fetched_spec)
    end

    it "should be truthy" do
      expect(subject.available?).to be_truthy
    end

    context "when there is no network access" do
      before do
        allow(downloader).to receive(:fetch).with(dependency_api_uri) {
          raise Bundler::Fetcher::NetworkDownError.new("Network Down Message")
        }
      end

      it "should raise an HTTPError with the original message" do
        expect { subject.available? }.to raise_error(Bundler::HTTPError, "Network Down Message")
      end
    end

    context "when authentication is required" do
      let(:remote_uri) { "http://remote_uri.org" }

      before do
        allow(downloader).to receive(:fetch).with(dependency_api_uri) {
          raise Bundler::Fetcher::AuthenticationRequiredError.new(remote_uri)
        }
      end

      it "should raise the original error" do
        expect { subject.available? }.to raise_error(Bundler::Fetcher::AuthenticationRequiredError,
          %r{Authentication is required for http://remote_uri.org})
      end
    end

    context "when there is an http error" do
      before { allow(downloader).to receive(:fetch).with(dependency_api_uri) { raise Bundler::HTTPError.new } }

      it "should be falsey" do
        expect(subject.available?).to be_falsey
      end
    end
  end

  describe "#api_fetcher?" do
    it "should return true" do
      expect(subject.api_fetcher?).to be_truthy
    end
  end

  describe "#specs" do
    let(:gem_names)            { %w(foo bar) }
    let(:full_dependency_list) { ["bar"] }
    let(:last_spec_list)       { [["boulder", gem_version1, "ruby", resque]] }
    let(:fail_errors)          { double(:fail_errors) }
    let(:bundler_retry)        { double(:bundler_retry) }
    let(:gem_version1)         { double(:gem_version1) }
    let(:resque)               { double(:resque) }
    let(:remote_uri)           { "http://remote-uri.org" }

    before do
      stub_const("Bundler::Fetcher::FAIL_ERRORS", fail_errors)
      allow(Bundler::Retry).to receive(:new).with("dependency api", fail_errors).and_return(bundler_retry)
      allow(bundler_retry).to receive(:attempts) {|&block| block.call }
      allow(subject).to receive(:log_specs) {}
      allow(subject).to receive(:remote_uri).and_return(remote_uri)
      allow(Bundler).to receive_message_chain(:ui, :debug?)
      allow(Bundler).to receive_message_chain(:ui, :info)
      allow(Bundler).to receive_message_chain(:ui, :debug)
    end

    context "when there are given gem names that are not in the full dependency list" do
      let(:spec_list)        { [["top", gem_version2, "ruby", faraday]] }
      let(:deps_list)        { [] }
      let(:dependency_specs) { [spec_list, deps_list] }
      let(:gem_version2)     { double(:gem_version2) }
      let(:faraday)          { double(:faraday) }

      before { allow(subject).to receive(:dependency_specs).with(["foo"]).and_return(dependency_specs) }

      it "should return a hash with the remote_uri and the list of specs" do
        expect(subject.specs(gem_names, full_dependency_list, last_spec_list)).to eq([
          ["top", gem_version2, "ruby", faraday],
          ["boulder", gem_version1, "ruby", resque],
        ])
      end
    end

    context "when all given gem names are in the full dependency list" do
      let(:gem_names)            { ["foo"] }
      let(:full_dependency_list) { %w(foo bar) }
      let(:last_spec_list)       { ["boulder"] }

      it "should return a hash with the remote_uri and the last spec list" do
        expect(subject.specs(gem_names, full_dependency_list, last_spec_list)).to eq(["boulder"])
      end
    end

    context "logging" do
      before { allow(subject).to receive(:log_specs).and_call_original }

      context "with debug on" do
        before do
          allow(Bundler).to receive_message_chain(:ui, :debug?).and_return(true)
          allow(subject).to receive(:dependency_specs).with(["foo"]).and_return([[], []])
        end

        it "should log the query list at debug level" do
          expect(Bundler).to receive_message_chain(:ui, :debug).with("Query List: [\"foo\"]")
          expect(Bundler).to receive_message_chain(:ui, :debug).with("Query List: []")
          subject.specs(gem_names, full_dependency_list, last_spec_list)
        end
      end

      context "with debug off" do
        before do
          allow(Bundler).to receive_message_chain(:ui, :debug?).and_return(false)
          allow(subject).to receive(:dependency_specs).with(["foo"]).and_return([[], []])
        end

        it "should log at info level" do
          expect(Bundler).to receive_message_chain(:ui, :info).with(".", false)
          expect(Bundler).to receive_message_chain(:ui, :info).with(".", false)
          subject.specs(gem_names, full_dependency_list, last_spec_list)
        end
      end
    end

    shared_examples_for "the error is properly handled" do
      it "should return nil" do
        expect(subject.specs(gem_names, full_dependency_list, last_spec_list)).to be_nil
      end

      context "debug logging is not on" do
        before { allow(Bundler).to receive_message_chain(:ui, :debug?).and_return(false) }

        it "should log a new line to info" do
          expect(Bundler).to receive_message_chain(:ui, :info).with("")
          subject.specs(gem_names, full_dependency_list, last_spec_list)
        end
      end
    end

    shared_examples_for "the error suggests retrying with the full index" do
      it "should log the inability to fetch from API at debug level" do
        expect(Bundler).to receive_message_chain(:ui, :debug).with("could not fetch from the dependency API\nit's suggested to retry using the full index via `bundle install --full-index`")
        subject.specs(gem_names, full_dependency_list, last_spec_list)
      end
    end

    context "when an HTTPError occurs" do
      before { allow(subject).to receive(:dependency_specs) { raise Bundler::HTTPError.new } }

      it_behaves_like "the error is properly handled"
      it_behaves_like "the error suggests retrying with the full index"
    end

    context "when a GemspecError occurs" do
      before { allow(subject).to receive(:dependency_specs) { raise Bundler::GemspecError.new } }

      it_behaves_like "the error is properly handled"
      it_behaves_like "the error suggests retrying with the full index"
    end

    context "when a MarshalError occurs" do
      before { allow(subject).to receive(:dependency_specs) { raise Bundler::MarshalError.new } }

      it_behaves_like "the error is properly handled"

      it "should log the inability to fetch from API and mention retrying" do
        expect(Bundler).to receive_message_chain(:ui, :debug).with("could not fetch from the dependency API, trying the full index")
        subject.specs(gem_names, full_dependency_list, last_spec_list)
      end
    end
  end

  describe "#dependency_specs" do
    let(:gem_names)                { [%w(foo bar), %w(bundler rubocop)] }
    let(:gem_list)                 { double(:gem_list) }
    let(:formatted_specs_and_deps) { double(:formatted_specs_and_deps) }

    before do
      allow(subject).to receive(:unmarshalled_dep_gems).with(gem_names).and_return(gem_list)
      allow(subject).to receive(:get_formatted_specs_and_deps).with(gem_list).and_return(formatted_specs_and_deps)
    end

    it "should log the query list at debug level" do
      expect(Bundler).to receive_message_chain(:ui, :debug).with(
        "Query Gemcutter Dependency Endpoint API: foo,bar,bundler,rubocop"
      )
      subject.dependency_specs(gem_names)
    end

    it "should return formatted specs and a unique list of dependencies" do
      expect(subject.dependency_specs(gem_names)).to eq(formatted_specs_and_deps)
    end
  end

  describe "#unmarshalled_dep_gems" do
    let(:gem_names)         { [%w(foo bar), %w(bundler rubocop)] }
    let(:dep_api_uri)       { double(:dep_api_uri) }
    let(:unmarshalled_gems) { double(:unmarshalled_gems) }
    let(:fetch_response)    { double(:fetch_response, :body => double(:body)) }
    let(:rubygems_limit)    { 50 }

    before { allow(subject).to receive(:dependency_api_uri).with(gem_names).and_return(dep_api_uri) }

    it "should fetch dependencies from Rubygems and unmarshal them" do
      expect(gem_names).to receive(:each_slice).with(rubygems_limit).and_call_original
      expect(downloader).to receive(:fetch).with(dep_api_uri).and_return(fetch_response)
      expect(Bundler).to receive(:load_marshal).with(fetch_response.body).and_return([unmarshalled_gems])
      expect(subject.unmarshalled_dep_gems(gem_names)).to eq([unmarshalled_gems])
    end
  end

  describe "#get_formatted_specs_and_deps" do
    let(:gem_list) do
      [
        {
          :dependencies => {
            "resque" => "req3,req4",
          },
          :name => "typhoeus",
          :number => "1.0.1",
          :platform => "ruby",
        },
        {
          :dependencies => {
            "faraday" => "req1,req2",
          },
          :name => "grape",
          :number => "2.0.2",
          :platform => "jruby",
        },
      ]
    end

    it "should return formatted specs and a unique list of dependencies" do
      spec_list, deps_list = subject.get_formatted_specs_and_deps(gem_list)
      expect(spec_list).to eq([["typhoeus", "1.0.1", "ruby", [["resque", ["req3,req4"]]]],
                               ["grape", "2.0.2", "jruby", [["faraday", ["req1,req2"]]]]])
      expect(deps_list).to eq(%w(resque faraday))
    end
  end

  describe "#dependency_api_uri" do
    let(:uri) { URI("http://gem-api.com") }

    context "with gem names" do
      let(:gem_names) { %w(foo bar bundler rubocop) }

      before { allow(subject).to receive(:fetch_uri).and_return(uri) }

      it "should return an api calling uri with the gems in the query" do
        expect(subject.dependency_api_uri(gem_names).to_s).to eq(
          "http://gem-api.com/api/v1/dependencies?gems=bar%2Cbundler%2Cfoo%2Crubocop"
        )
      end
    end

    context "with no gem names" do
      let(:gem_names) { [] }

      before { allow(subject).to receive(:fetch_uri).and_return(uri) }

      it "should return an api calling uri with no query" do
        expect(subject.dependency_api_uri(gem_names).to_s).to eq(
          "http://gem-api.com/api/v1/dependencies"
        )
      end
    end
  end
end
