# frozen_string_literal: true

RSpec.describe Bundler::Fetcher::Downloader do
  let(:connection)     { double(:connection) }
  let(:redirect_limit) { 5 }
  let(:uri)            { URI("http://www.uri-to-fetch.com/api/v2/endpoint") }
  let(:options)        { double(:options) }

  subject { described_class.new(connection, redirect_limit) }

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
      let(:http_response) { Net::HTTPSuccess.new("1.1", 200, "Success") }

      it "should log the HTTP response code and message to debug" do
        expect(Bundler).to receive_message_chain(:ui, :debug).with("HTTP 200 Success #{uri}")
        subject.fetch(uri, options, counter)
      end
    end

    context "when the request response is a Net::HTTPRedirection" do
      let(:http_response) { Net::HTTPRedirection.new(httpv, 308, "Moved") }

      before { http_response["location"] = "http://www.redirect-uri.com/api/v2/endpoint" }

      it "should try to fetch the redirect uri and iterate the # requests counter" do
        expect(subject).to receive(:fetch).with(URI("http://www.uri-to-fetch.com/api/v2/endpoint"), options, 0).and_call_original
        expect(subject).to receive(:fetch).with(URI("http://www.redirect-uri.com/api/v2/endpoint"), options, 1)
        subject.fetch(uri, options, counter)
      end

      context "when the redirect uri and original uri are the same" do
        let(:uri) { URI("ssh://username:password@www.uri-to-fetch.com/api/v2/endpoint") }

        before { http_response["location"] = "ssh://www.uri-to-fetch.com/api/v1/endpoint" }

        it "should set the same user and password for the redirect uri" do
          expect(subject).to receive(:fetch).with(URI("ssh://username:password@www.uri-to-fetch.com/api/v2/endpoint"), options, 0).and_call_original
          expect(subject).to receive(:fetch).with(URI("ssh://username:password@www.uri-to-fetch.com/api/v1/endpoint"), options, 1)
          subject.fetch(uri, options, counter)
        end
      end
    end

    context "when the request response is a Net::HTTPSuccess" do
      let(:http_response) { Net::HTTPSuccess.new("1.1", 200, "Success") }

      it "should return the response body" do
        expect(subject.fetch(uri, options, counter)).to eq(http_response)
      end
    end

    context "when the request response is a Net::HTTPRequestEntityTooLarge" do
      let(:http_response) { Net::HTTPRequestEntityTooLarge.new("1.1", 413, "Too Big") }

      it "should raise a Bundler::Fetcher::FallbackError with the response body" do
        expect { subject.fetch(uri, options, counter) }.to raise_error(Bundler::Fetcher::FallbackError, "Body with info")
      end
    end

    context "when the request response is a Net::HTTPUnauthorized" do
      let(:http_response) { Net::HTTPUnauthorized.new("1.1", 401, "Unauthorized") }

      it "should raise a Bundler::Fetcher::AuthenticationRequiredError with the uri host" do
        expect { subject.fetch(uri, options, counter) }.to raise_error(Bundler::Fetcher::AuthenticationRequiredError,
          /Authentication is required for www.uri-to-fetch.com/)
      end

      context "when the there are credentials provided in the request" do
        let(:uri) { URI("http://user:password@www.uri-to-fetch.com") }

        it "should raise a Bundler::Fetcher::BadAuthenticationError that doesn't contain the password" do
          expect { subject.fetch(uri, options, counter) }.
            to raise_error(Bundler::Fetcher::BadAuthenticationError, /Bad username or password for www.uri-to-fetch.com/)
        end
      end
    end

    context "when the request response is a Net::HTTPNotFound" do
      let(:http_response) { Net::HTTPNotFound.new("1.1", 404, "Not Found") }

      it "should raise a Bundler::Fetcher::FallbackError with Net::HTTPNotFound" do
        expect { subject.fetch(uri, options, counter) }.
          to raise_error(Bundler::Fetcher::FallbackError, "Net::HTTPNotFound: http://www.uri-to-fetch.com/api/v2/endpoint")
      end

      context "when the there are credentials provided in the request" do
        let(:uri) { URI("http://username:password@www.uri-to-fetch.com/api/v2/endpoint") }

        it "should raise a Bundler::Fetcher::FallbackError that doesn't contain the password" do
          expect { subject.fetch(uri, options, counter) }.
            to raise_error(Bundler::Fetcher::FallbackError, "Net::HTTPNotFound: http://username@www.uri-to-fetch.com/api/v2/endpoint")
        end
      end
    end

    context "when the request response is some other type" do
      let(:http_response) { Net::HTTPBadGateway.new("1.1", 500, "Fatal Error") }

      it "should raise a Bundler::HTTPError with the response class and body" do
        expect { subject.fetch(uri, options, counter) }.to raise_error(Bundler::HTTPError, "Net::HTTPBadGateway: Body with info")
      end
    end
  end

  describe "request" do
    let(:net_http_get) { double(:net_http_get) }
    let(:response)     { double(:response) }

    before do
      allow(Net::HTTP::Get).to receive(:new).with("/api/v2/endpoint", options).and_return(net_http_get)
      allow(connection).to receive(:request).with(uri, net_http_get).and_return(response)
    end

    it "should log the HTTP GET request to debug" do
      expect(Bundler).to receive_message_chain(:ui, :debug).with("HTTP GET http://www.uri-to-fetch.com/api/v2/endpoint")
      subject.request(uri, options)
    end

    context "when there is a user provided in the request" do
      context "and there is also a password provided" do
        context "that contains cgi escaped characters" do
          let(:uri) { URI("http://username:password%24@www.uri-to-fetch.com/api/v2/endpoint") }

          it "should request basic authentication with the username and password" do
            expect(net_http_get).to receive(:basic_auth).with("username", "password$")
            subject.request(uri, options)
          end
        end

        context "that is all unescaped characters" do
          let(:uri) { URI("http://username:password@www.uri-to-fetch.com/api/v2/endpoint") }
          it "should request basic authentication with the username and proper cgi compliant password" do
            expect(net_http_get).to receive(:basic_auth).with("username", "password")
            subject.request(uri, options)
          end
        end
      end

      context "and there is no password provided" do
        let(:uri) { URI("http://username@www.uri-to-fetch.com/api/v2/endpoint") }

        it "should request basic authentication with just the user" do
          expect(net_http_get).to receive(:basic_auth).with("username", nil)
          subject.request(uri, options)
        end
      end

      context "that contains cgi escaped characters" do
        let(:uri) { URI("http://username%24@www.uri-to-fetch.com/api/v2/endpoint") }

        it "should request basic authentication with the proper cgi compliant password user" do
          expect(net_http_get).to receive(:basic_auth).with("username$", nil)
          subject.request(uri, options)
        end
      end
    end

    context "when the request response causes a NoMethodError" do
      before { allow(connection).to receive(:request).with(uri, net_http_get) { raise NoMethodError.new(message) } }

      context "and the error message is about use_ssl=" do
        let(:message) { "undefined method 'use_ssl='" }

        it "should raise a LoadError about openssl" do
          expect { subject.request(uri, options) }.to raise_error(LoadError, "cannot load such file -- openssl")
        end
      end

      context "and the error message is not about use_ssl=" do
        let(:message) { "undefined method 'undefined_method_call'" }

        it "should raise the original NoMethodError" do
          expect { subject.request(uri, options) }.to raise_error(NoMethodError, "undefined method 'undefined_method_call'")
        end
      end
    end

    context "when the request response causes a OpenSSL::SSL::SSLError" do
      before { allow(connection).to receive(:request).with(uri, net_http_get) { raise OpenSSL::SSL::SSLError.new } }

      it "should raise a LoadError about openssl" do
        expect { subject.request(uri, options) }.to raise_error(Bundler::Fetcher::CertificateFailureError,
          %r{Could not verify the SSL certificate for http://www.uri-to-fetch.com/api/v2/endpoint})
      end
    end

    context "when the request response causes an error included in HTTP_ERRORS" do
      let(:message) { nil }
      let(:error)   { RuntimeError.new(message) }

      before do
        stub_const("Bundler::Fetcher::HTTP_ERRORS", [RuntimeError])
        allow(connection).to receive(:request).with(uri, net_http_get) { raise error }
      end

      it "should trace log the error" do
        allow(Bundler).to receive_message_chain(:ui, :debug)
        expect(Bundler).to receive_message_chain(:ui, :trace).with(error)
        expect { subject.request(uri, options) }.to raise_error(Bundler::HTTPError)
      end

      context "when error message is about the host being down" do
        let(:message) { "host down: http://www.uri-to-fetch.com" }

        it "should raise a Bundler::Fetcher::NetworkDownError" do
          expect { subject.request(uri, options) }.to raise_error(Bundler::Fetcher::NetworkDownError,
            /Could not reach host www.uri-to-fetch.com/)
        end
      end

      context "when error message is about getaddrinfo issues" do
        let(:message) { "getaddrinfo: nodename nor servname provided for http://www.uri-to-fetch.com" }

        it "should raise a Bundler::Fetcher::NetworkDownError" do
          expect { subject.request(uri, options) }.to raise_error(Bundler::Fetcher::NetworkDownError,
            /Could not reach host www.uri-to-fetch.com/)
        end
      end

      context "when error message is about neither host down or getaddrinfo" do
        let(:message) { "other error about network" }

        it "should raise a Bundler::HTTPError" do
          expect { subject.request(uri, options) }.to raise_error(Bundler::HTTPError,
            "Network error while fetching http://www.uri-to-fetch.com/api/v2/endpoint (other error about network)")
        end

        context "when the there are credentials provided in the request" do
          let(:uri) { URI("http://username:password@www.uri-to-fetch.com/api/v2/endpoint") }
          before do
            allow(net_http_get).to receive(:basic_auth).with("username", "password")
          end

          it "should raise a Bundler::HTTPError that doesn't contain the password" do
            expect { subject.request(uri, options) }.to raise_error(Bundler::HTTPError,
              "Network error while fetching http://username@www.uri-to-fetch.com/api/v2/endpoint (other error about network)")
          end
        end
      end

      context "when error message is about no route to host" do
        let(:message) { "Failed to open TCP connection to www.uri-to-fetch.com:443 " }

        it "should raise a Bundler::Fetcher::HTTPError" do
          expect { subject.request(uri, options) }.to raise_error(Bundler::HTTPError,
            "Network error while fetching http://www.uri-to-fetch.com/api/v2/endpoint (#{message})")
        end
      end
    end
  end
end
