# frozen_string_literal: true

require "rubygems/remote_fetcher"

RSpec.describe Bundler::Fetcher::Downloader do
  let(:connections)    { double(:connections) }
  let(:redirect_limit) { 5 }
  let(:uri)            { Gem::URI("http://www.uri-to-fetch.com/api/v2/endpoint") }
  let(:options)        { double(:options) }

  subject { described_class.new(connections, redirect_limit) }

  describe "fetch" do
    let(:counter)      { 0 }
    let(:httpv)        { "1.1" }
    let(:http_response) { double(:response) }

    before do
      allow(subject).to receive(:request).with(uri, options).and_return(http_response)
      allow(http_response).to receive(:body).and_return("Body with info")
    end

    context "when the # requests counter is greater than the redirect limit" do
      let(:counter) { redirect_limit + 1 }

      it "should raise a Bundler::HTTPError specifying too many redirects" do
        expect { subject.fetch(uri, options, counter) }.to raise_error(Bundler::HTTPError, "Too many redirects")
      end
    end

    context "logging" do
      let(:http_response) { Gem::Net::HTTPSuccess.new("1.1", 200, "Success") }

      it "should log the HTTP response code and message to debug" do
        expect(Bundler).to receive_message_chain(:ui, :debug).with("HTTP 200 Success #{uri}")
        subject.fetch(uri, options, counter)
      end
    end

    context "when the request response is a Gem::Net::HTTPRedirection" do
      let(:http_response) { Gem::Net::HTTPRedirection.new(httpv, 308, "Moved") }

      before { http_response["location"] = "http://www.redirect-uri.com/api/v2/endpoint" }

      it "should try to fetch the redirect uri and iterate the # requests counter" do
        expect(subject).to receive(:fetch).with(Gem::URI("http://www.uri-to-fetch.com/api/v2/endpoint"), options, 0).and_call_original
        expect(subject).to receive(:fetch).with(Gem::URI("http://www.redirect-uri.com/api/v2/endpoint"), options, 1)
        subject.fetch(uri, options, counter)
      end

      context "when the redirect uri and original uri are the same" do
        let(:uri) { Gem::URI("ssh://username:password@www.uri-to-fetch.com/api/v2/endpoint") }

        before { http_response["location"] = "ssh://www.uri-to-fetch.com/api/v1/endpoint" }

        it "should set the same user and password for the redirect uri" do
          expect(subject).to receive(:fetch).with(Gem::URI("ssh://username:password@www.uri-to-fetch.com/api/v2/endpoint"), options, 0).and_call_original
          expect(subject).to receive(:fetch).with(Gem::URI("ssh://username:password@www.uri-to-fetch.com/api/v1/endpoint"), options, 1)
          subject.fetch(uri, options, counter)
        end
      end

      context "when the redirect uri downgrades https to http" do
        let(:uri) { Gem::URI("https://username:password@www.uri-to-fetch.com/api/v2/endpoint") }

        before { http_response["location"] = "http://www.uri-to-fetch.com/api/v2/endpoint" }

        it "should raise a Bundler::HTTPError instead of following the redirect" do
          expect(subject).to receive(:fetch).with(uri, options, 0).and_call_original
          expect(subject).not_to receive(:fetch).with(Gem::URI("http://username:password@www.uri-to-fetch.com/api/v2/endpoint"), options, 1)
          expect { subject.fetch(uri, options, counter) }.to raise_error(Bundler::HTTPError,
            "Redirecting to a non-https URI is not allowed: http://www.uri-to-fetch.com/api/v2/endpoint")
        end
      end
    end

    context "when the request response is a Gem::Net::HTTPSuccess" do
      let(:http_response) { Gem::Net::HTTPSuccess.new("1.1", 200, "Success") }

      it "should return the response body" do
        expect(subject.fetch(uri, options, counter)).to eq(http_response)
      end
    end

    context "when the request response is a Gem::Net::HTTPRequestEntityTooLarge" do
      let(:http_response) { Gem::Net::HTTPRequestEntityTooLarge.new("1.1", 413, "Too Big") }

      it "should raise a Bundler::Fetcher::FallbackError with the response body" do
        expect { subject.fetch(uri, options, counter) }.to raise_error(Bundler::Fetcher::FallbackError, "Body with info")
      end
    end

    context "when the request response is a Gem::Net::HTTPUnauthorized" do
      let(:http_response) { Gem::Net::HTTPUnauthorized.new("1.1", 401, "Unauthorized") }

      it "should raise a Bundler::Fetcher::AuthenticationRequiredError with the uri host" do
        expect { subject.fetch(uri, options, counter) }.to raise_error(Bundler::Fetcher::AuthenticationRequiredError,
          /Authentication is required for www.uri-to-fetch.com/)
      end

      it "should raise a Bundler::Fetcher::AuthenticationRequiredError with advice" do
        expect { subject.fetch(uri, options, counter) }.to raise_error(Bundler::Fetcher::AuthenticationRequiredError,
          /`bundle config set --global www\.uri-to-fetch\.com username:password`.*`BUNDLE_WWW__URI___TO___FETCH__COM`/m)
      end

      context "when there are credentials provided in the request" do
        let(:uri) { Gem::URI("http://user:password@www.uri-to-fetch.com") }

        it "should raise a Bundler::Fetcher::BadAuthenticationError that doesn't contain the password" do
          expect { subject.fetch(uri, options, counter) }.
            to raise_error(Bundler::Fetcher::BadAuthenticationError, /Bad username or password for www.uri-to-fetch.com/)
        end
      end
    end

    context "when the request response is a Gem::Net::HTTPForbidden" do
      let(:http_response) { Gem::Net::HTTPForbidden.new("1.1", 403, "Forbidden") }
      let(:uri) { Gem::URI("http://user:password@www.uri-to-fetch.com") }

      it "should raise a Bundler::Fetcher::AuthenticationForbiddenError with the uri host" do
        expect { subject.fetch(uri, options, counter) }.to raise_error(Bundler::Fetcher::AuthenticationForbiddenError,
          /Access token could not be authenticated for www.uri-to-fetch.com/)
      end
    end

    context "when the request response is a Gem::Net::HTTPNotFound" do
      let(:http_response) { Gem::Net::HTTPNotFound.new("1.1", 404, "Not Found") }

      it "should raise a Bundler::Fetcher::FallbackError with Gem::Net::HTTPNotFound" do
        expect { subject.fetch(uri, options, counter) }.
          to raise_error(Bundler::Fetcher::FallbackError, "Gem::Net::HTTPNotFound: http://www.uri-to-fetch.com/api/v2/endpoint")
      end

      context "when there are credentials provided in the request" do
        let(:uri) { Gem::URI("http://username:password@www.uri-to-fetch.com/api/v2/endpoint") }

        it "should raise a Bundler::Fetcher::FallbackError that doesn't contain the password" do
          expect { subject.fetch(uri, options, counter) }.
            to raise_error(Bundler::Fetcher::FallbackError, "Gem::Net::HTTPNotFound: http://username@www.uri-to-fetch.com/api/v2/endpoint")
        end
      end
    end

    context "when the request response is a Gem::Net::HTTPRequestedRangeNotSatisfiable" do
      let(:http_response) { Gem::Net::HTTPRequestedRangeNotSatisfiable.new("1.1", 416, "Range Not Satisfiable") }
      let(:success_response) { Gem::Net::HTTPSuccess.new("1.1", 200, "Success") }
      let(:options) { { "Range" => "bytes=1000-", "If-None-Match" => "some-etag" } }

      before do
        # First request returns 416, retry request returns success
        allow(subject).to receive(:request).with(uri, options).and_return(http_response)
        allow(subject).to receive(:request).with(uri, { "If-None-Match" => "some-etag" }).and_return(success_response)
      end

      # The 416 handler removes the Range header and retries without incrementing the counter.
      # Importantly, it does NOT add Accept-Encoding header, which would break Ruby's
      # automatic gzip decompression (see issue #9271 for details on that bug).
      it "should retry the request without the Range header" do
        expect(subject).to receive(:request).with(uri, options).ordered
        expect(subject).to receive(:request).with(uri, hash_excluding("Range", "Accept-Encoding")).ordered
        subject.fetch(uri, options, counter)
      end

      it "should preserve other headers on retry" do
        expect(subject).to receive(:request).with(uri, options).ordered
        expect(subject).to receive(:request).with(uri, hash_including("If-None-Match" => "some-etag")).ordered
        subject.fetch(uri, options, counter)
      end

      it "should return the successful response" do
        result = subject.fetch(uri, options, counter)
        expect(result).to eq(success_response)
      end
    end

    context "when the request response is some other type" do
      let(:http_response) { Gem::Net::HTTPBadGateway.new("1.1", 500, "Fatal Error") }

      it "should raise a Bundler::HTTPError with the response class and body" do
        expect { subject.fetch(uri, options, counter) }.to raise_error(Bundler::HTTPError, "Gem::Net::HTTPBadGateway: Body with info")
      end
    end
  end

  describe "request" do
    let(:response) { double(:response) }

    before do
      allow(connections).to receive(:request).with(uri, options).and_return(response)
    end

    it "should log the HTTP GET request to debug" do
      expect(Bundler).to receive_message_chain(:ui, :debug).with("HTTP GET http://www.uri-to-fetch.com/api/v2/endpoint")
      subject.request(uri, options)
    end

    context "when there are credentials provided in the request" do
      let(:uri) { Gem::URI("http://username:password@www.uri-to-fetch.com/api/v2/endpoint") }

      it "should log the HTTP GET request to debug, without the password" do
        expect(Bundler).to receive_message_chain(:ui, :debug).with("HTTP GET http://username@www.uri-to-fetch.com/api/v2/endpoint")
        subject.request(uri, options)
      end
    end

    context "when the request response causes a OpenSSL::SSL::SSLError" do
      before { allow(connections).to receive(:request).with(uri, options) { raise OpenSSL::SSL::SSLError.new } }

      it "should raise a Bundler::Fetcher::CertificateFailureError" do
        expect { subject.request(uri, options) }.to raise_error(Bundler::Fetcher::CertificateFailureError,
          %r{Could not verify the SSL certificate for http://www.uri-to-fetch.com/api/v2/endpoint})
      end
    end

    context "when the request response causes a Gem::RemoteFetcher::FetchError" do
      let(:message) { "error about network" }
      let(:error) { Gem::RemoteFetcher::FetchError.new(message, uri) }

      before do
        allow(connections).to receive(:request).with(uri, options) { raise error }
      end

      it "should raise a Bundler::HTTPError" do
        expect { subject.request(uri, options) }.to raise_error(Bundler::HTTPError,
          %r{Network error while fetching http://www\.uri-to-fetch\.com/api/v2/endpoint \(error about network})
      end

      context "when the error is about a failed certificate verification" do
        let(:message) { "SSL_connect returned=1 errno=0 peeraddr=127.0.0.1:443 state=error: certificate verify failed" }

        it "should raise a Bundler::Fetcher::CertificateFailureError" do
          expect { subject.request(uri, options) }.to raise_error(Bundler::Fetcher::CertificateFailureError,
            %r{Could not verify the SSL certificate for http://www.uri-to-fetch.com/api/v2/endpoint})
        end
      end

      context "when the error is about the host being down" do
        let(:message) { "Host is down" }

        it "should raise a Bundler::Fetcher::NetworkDownError" do
          expect { subject.request(uri, options) }.to raise_error(Bundler::Fetcher::NetworkDownError,
            /Could not reach host www.uri-to-fetch.com/)
        end
      end

      context "when there are credentials provided in the request" do
        let(:uri) { Gem::URI("http://username:password@www.uri-to-fetch.com/api/v2/endpoint") }

        it "should raise a Bundler::HTTPError that doesn't contain the password" do
          expect { subject.request(uri, options) }.to raise_error(Bundler::HTTPError) do |error|
            expect(error.message).not_to include("password")
          end
        end
      end
    end

    context "when the request response causes an HTTP error" do
      let(:message) { "error about network" }
      let(:error) { error_class.new(message) }

      before do
        allow(connections).to receive(:request).with(uri, options) { raise error }
      end

      context "that it's retryable" do
        let(:error_class) { Gem::Timeout::Error }

        it "should trace log the error" do
          allow(Bundler).to receive_message_chain(:ui, :debug)
          expect(Bundler).to receive_message_chain(:ui, :trace).with(error)
          expect { subject.request(uri, options) }.to raise_error(Bundler::HTTPError)
        end

        it "should raise a Bundler::HTTPError" do
          expect { subject.request(uri, options) }.to raise_error(Bundler::HTTPError,
            "Network error while fetching http://www.uri-to-fetch.com/api/v2/endpoint (error about network)")
        end

        context "when there are credentials provided in the request" do
          let(:uri) { Gem::URI("http://username:password@www.uri-to-fetch.com/api/v2/endpoint") }

          it "should raise a Bundler::HTTPError that doesn't contain the password" do
            expect { subject.request(uri, options) }.to raise_error(Bundler::HTTPError,
              "Network error while fetching http://username@www.uri-to-fetch.com/api/v2/endpoint (error about network)")
          end
        end
      end

      context "when error is about connection refused" do
        let(:error_class) { Errno::ECONNREFUSED }

        it "should raise a Bundler::Fetcher::NetworkDownError" do
          expect { subject.request(uri, options) }.to raise_error(Bundler::Fetcher::NetworkDownError,
            /Could not reach host www.uri-to-fetch.com/)
        end
      end

      context "when error is about no route to host" do
        let(:error_class) { SocketError }
        let(:message) { "Failed to open TCP connection to www.uri-to-fetch.com:443 " }

        it "should raise a Bundler::Fetcher::NetworkDownError" do
          expect { subject.request(uri, options) }.to raise_error(Bundler::Fetcher::NetworkDownError,
            /Could not reach host www.uri-to-fetch.com/)
        end
      end
    end
  end
end
