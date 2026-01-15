# frozen_string_literal: true

require "rubygems/remote_fetcher"

RSpec.describe Bundler::Fetcher::Index do
  let(:downloader)  { nil }
  let(:remote)      { double(:remote, uri: remote_uri) }
  let(:remote_uri)  { Gem::URI("http://#{userinfo}remote-uri.org") }
  let(:userinfo)    { "" }
  let(:display_uri) { "http://sample_uri.com" }
  let(:rubygems)    { double(:rubygems) }
  let(:gem_names)   { %w[foo bar] }
  let(:gem_remote_fetcher) { nil }

  subject { described_class.new(downloader, remote, display_uri, gem_remote_fetcher) }

  before { allow(Bundler).to receive(:rubygems).and_return(rubygems) }

  it "fetches and returns the list of remote specs" do
    expect(rubygems).to receive(:fetch_all_remote_specs) { nil }
    subject.specs(gem_names)
  end

  context "error handling" do
    before do
      allow(rubygems).to receive(:fetch_all_remote_specs) { raise Gem::RemoteFetcher::FetchError.new(error_message, display_uri) }
    end

    context "when certificate verify failed" do
      let(:error_message) { "certificate verify failed" }

      it "should raise a Bundler::Fetcher::CertificateFailureError" do
        expect { subject.specs(gem_names) }.to raise_error(Bundler::Fetcher::CertificateFailureError,
          %r{Could not verify the SSL certificate for http://sample_uri.com})
      end
    end

    context "when a 401 response occurs" do
      let(:error_message) { "401" }

      it "should raise a Bundler::Fetcher::AuthenticationRequiredError" do
        expect { subject.specs(gem_names) }.to raise_error(Bundler::Fetcher::AuthenticationRequiredError,
          %r{Authentication is required for http://remote-uri.org})
      end

      context "and there was userinfo" do
        let(:userinfo) { "user:pass@" }

        it "should raise a Bundler::Fetcher::BadAuthenticationError" do
          expect { subject.specs(gem_names) }.to raise_error(Bundler::Fetcher::BadAuthenticationError,
            %r{Bad username or password for http://user@remote-uri.org})
        end
      end
    end

    context "when a 403 response occurs" do
      let(:error_message) { "403" }

      it "should raise a Bundler::Fetcher::AuthenticationForbiddenError" do
        expect { subject.specs(gem_names) }.to raise_error(Bundler::Fetcher::AuthenticationForbiddenError,
          %r{Access token could not be authenticated for http://remote-uri.org})
      end
    end

    context "any other message is returned" do
      let(:error_message) { "You get an error, you get an error!" }

      before { allow(Bundler).to receive(:ui).and_return(double(trace: nil)) }

      it "should raise a Bundler::HTTPError" do
        expect { subject.specs(gem_names) }.to raise_error(Bundler::HTTPError, "Could not fetch specs from http://sample_uri.com due to underlying error <You get an error, you get an error! (http://sample_uri.com)>")
      end
    end
  end
end
