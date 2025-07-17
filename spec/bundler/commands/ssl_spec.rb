# frozen_string_literal: true

require "bundler/cli"
require "bundler/cli/doctor"
require "bundler/cli/doctor/ssl"
require_relative "../support/artifice/helpers/artifice"
require "bundler/vendored_persistent.rb"

RSpec.describe "bundle doctor ssl" do
  before(:each) do
    require_rack_test
    require_relative "../support/artifice/helpers/endpoint"

    @dummy_endpoint = Class.new(Endpoint) do
      get "/" do
      end
    end

    @previous_level = Bundler.ui.level
    Bundler.ui.instance_variable_get(:@warning_history).clear
    @previous_client = Gem::Request::ConnectionPools.client
    Bundler.ui.level = "info"
    Artifice.activate_with(@dummy_endpoint)
    Gem::Request::ConnectionPools.client = Gem::Net::HTTP
  end

  after(:each) do
    Bundler.ui.level = @previous_level
    Artifice.deactivate
    Gem::Request::ConnectionPools.client = @previous_client
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

    it "fails due to certificate verification", :ruby_repo do
      net_http = Class.new(Artifice::Net::HTTP) do
        def connect
          raise OpenSSL::SSL::SSLError, "certificate verify failed"
        end
      end

      Artifice.replace_net_http(net_http)
      Gem::Request::ConnectionPools.client = net_http
      Gem::RemoteFetcher.fetcher.close_all

      expected_out = <<~MSG
        Here's your OpenSSL environment:

        OpenSSL:       #{OpenSSL::VERSION}
        Compiled with: #{OpenSSL::OPENSSL_VERSION}
        Loaded with:   #{OpenSSL::OPENSSL_LIBRARY_VERSION}

        Trying connections to https://rubygems.org:
      MSG

      expected_err = <<~MSG
        Bundler:       failed     (certificate verification)
        RubyGems:      failed     (certificate verification)
        Ruby net/http: failed

        Unfortunately, this Ruby can't connect to rubygems.org.

        Below affect only Ruby net/http connections:
        SSL_CERT_FILE: exists     #{OpenSSL::X509::DEFAULT_CERT_FILE}
        SSL_CERT_DIR:  exists     #{OpenSSL::X509::DEFAULT_CERT_DIR}

        Your Ruby can't connect to rubygems.org because you are missing the certificate files OpenSSL needs to verify you are connecting to the genuine rubygems.org servers.

      MSG

      subject = Bundler::CLI::Doctor::SSL.new({})
      expect { subject.run }.to output(expected_out).to_stdout.and output(expected_err).to_stderr
    end

    it "fails due to a too old tls version" do
      subject = Bundler::CLI::Doctor::SSL.new({})

      net_http = Class.new(Artifice::Net::HTTP) do
        def connect
          raise OpenSSL::SSL::SSLError, "read server hello A"
        end
      end

      Artifice.replace_net_http(net_http)
      Gem::Request::ConnectionPools.client = Gem::Net::HTTP
      Gem::RemoteFetcher.fetcher.close_all

      expected_out = <<~MSG
        Here's your OpenSSL environment:

        OpenSSL:       #{OpenSSL::VERSION}
        Compiled with: #{OpenSSL::OPENSSL_VERSION}
        Loaded with:   #{OpenSSL::OPENSSL_LIBRARY_VERSION}

        Trying connections to https://rubygems.org:
      MSG

      expected_err = <<~MSG
        Bundler:       failed     (SSL/TLS protocol version mismatch)
        RubyGems:      failed     (SSL/TLS protocol version mismatch)
        Ruby net/http: failed

        Unfortunately, this Ruby can't connect to rubygems.org.

        Your Ruby can't connect to rubygems.org because your version of OpenSSL is too old.
        You'll need to upgrade your OpenSSL install and/or recompile Ruby to use a newer OpenSSL.

      MSG

      expect { subject.run }.to output(expected_out).to_stdout.and output(expected_err).to_stderr
    end

    it "fails due to unsupported tls 1.3 version" do
      net_http = Class.new(Artifice::Net::HTTP) do
        def connect
          raise OpenSSL::SSL::SSLError, "read server hello A"
        end
      end

      Artifice.replace_net_http(net_http)
      Gem::Request::ConnectionPools.client = net_http
      Gem::RemoteFetcher.fetcher.close_all

      expected_out = <<~MSG
        Here's your OpenSSL environment:

        OpenSSL:       #{OpenSSL::VERSION}
        Compiled with: #{OpenSSL::OPENSSL_VERSION}
        Loaded with:   #{OpenSSL::OPENSSL_LIBRARY_VERSION}

        Trying connections to https://rubygems.org:
      MSG

      expected_err = <<~MSG
        Bundler:       failed     (SSL/TLS protocol version mismatch)
        RubyGems:      failed     (SSL/TLS protocol version mismatch)
        Ruby net/http: failed

        Unfortunately, this Ruby can't connect to rubygems.org.

        Your Ruby can't connect to rubygems.org because TLS1_3 isn't supported yet.

      MSG

      subject = Bundler::CLI::Doctor::SSL.new("tls-version": "1.3")
      expect { subject.run }.to output(expected_out).to_stdout.and output(expected_err).to_stderr
    end

    it "fails due to a bundler and rubygems connection error" do
      endpoint = Class.new(Endpoint) do
        get "/" do
          raise OpenSSL::SSL::SSLError, "read server hello A"
        end
      end

      Artifice.activate_with(endpoint)
      Gem::Request::ConnectionPools.client = Gem::Net::HTTP

      expected_out = <<~MSG
        Here's your OpenSSL environment:

        OpenSSL:       #{OpenSSL::VERSION}
        Compiled with: #{OpenSSL::OPENSSL_VERSION}
        Loaded with:   #{OpenSSL::OPENSSL_LIBRARY_VERSION}

        Trying connections to https://rubygems.org:
        Ruby net/http: success

        For some reason, your Ruby installation can connect to rubygems.org, but neither RubyGems nor Bundler can.
        The most likely fix is to manually upgrade RubyGems by following the instructions at http://ruby.to/ssl-check-failed.
        After you've done that, run `gem install bundler` to upgrade Bundler, and then run this script again to make sure everything worked. ❣

      MSG

      expected_err = <<~MSG
        Bundler:       failed     (SSL/TLS protocol version mismatch)
        RubyGems:      failed     (SSL/TLS protocol version mismatch)
      MSG

      subject = Bundler::CLI::Doctor::SSL.new({})
      expect { subject.run }.to output(expected_out).to_stdout.and output(expected_err).to_stderr
    end

    it "fails due to a bundler connection error" do
      endpoint = Class.new(Endpoint) do
        get "/" do
          if request.user_agent.include?("bundler")
            raise OpenSSL::SSL::SSLError, "read server hello A"
          end
        end
      end

      Artifice.activate_with(endpoint)
      Gem::Request::ConnectionPools.client = Gem::Net::HTTP

      expected_out = <<~MSG
        Here's your OpenSSL environment:

        OpenSSL:       #{OpenSSL::VERSION}
        Compiled with: #{OpenSSL::OPENSSL_VERSION}
        Loaded with:   #{OpenSSL::OPENSSL_LIBRARY_VERSION}

        Trying connections to https://rubygems.org:
        RubyGems:      success
        Ruby net/http: success

        Although your Ruby installation and RubyGems can both connect to rubygems.org, Bundler is having trouble.
        The most likely way to fix this is to upgrade Bundler by running `gem install bundler`.
        Run this script again after doing that to make sure everything is all set.
        If you're still having trouble, check out the troubleshooting guide at http://ruby.to/ssl-check-failed.

      MSG

      expected_err = <<~MSG
        Bundler:       failed     (SSL/TLS protocol version mismatch)
      MSG

      subject = Bundler::CLI::Doctor::SSL.new({})
      expect { subject.run }.to output(expected_out).to_stdout.and output(expected_err).to_stderr
    end

    it "fails due to a RubyGems connection error" do
      endpoint = Class.new(Endpoint) do
        get "/" do
          if request.user_agent.include?("Ruby, RubyGems")
            raise OpenSSL::SSL::SSLError, "read server hello A"
          end
        end
      end

      Artifice.activate_with(endpoint)
      Gem::Request::ConnectionPools.client = Gem::Net::HTTP

      expected_out = <<~MSG
        Here's your OpenSSL environment:

        OpenSSL:       #{OpenSSL::VERSION}
        Compiled with: #{OpenSSL::OPENSSL_VERSION}
        Loaded with:   #{OpenSSL::OPENSSL_LIBRARY_VERSION}

        Trying connections to https://rubygems.org:
        Bundler:       success
        Ruby net/http: success

        It looks like Ruby and Bundler can connect to rubygems.org, but RubyGems itself cannot.
        You can likely solve this by manually downloading and installing a RubyGems update.
        Visit http://ruby.to/ssl-check-failed for instructions on how to manually upgrade RubyGems.

      MSG

      expected_err = <<~MSG
        RubyGems:      failed     (SSL/TLS protocol version mismatch)
      MSG

      subject = Bundler::CLI::Doctor::SSL.new({})
      expect { subject.run }.to output(expected_out).to_stdout.and output(expected_err).to_stderr
    end
  end

  context "when no diagnostic fails" do
    it "prints the SSL environment" do
      expected_out = <<~MSG
        Here's your OpenSSL environment:

        OpenSSL:       #{OpenSSL::VERSION}
        Compiled with: #{OpenSSL::OPENSSL_VERSION}
        Loaded with:   #{OpenSSL::OPENSSL_LIBRARY_VERSION}

        Trying connections to https://rubygems.org:
        Bundler:       success
        RubyGems:      success
        Ruby net/http: success

        Hooray! This Ruby can connect to rubygems.org.
        You are all set to use Bundler and RubyGems.

      MSG

      subject = Bundler::CLI::Doctor::SSL.new({})
      expect { subject.run }.to output(expected_out).to_stdout.and output("").to_stderr
    end

    it "uses the tls_version verify mode and host when given as option" do
      net_http = Class.new(Artifice::Net::HTTP) do
        class << self
          attr_accessor :verify_mode, :min_version, :max_version
        end

        def connect
          self.class.verify_mode = verify_mode
          self.class.min_version = min_version
          self.class.max_version = max_version

          super
        end
      end

      net_http.endpoint = @dummy_endpoint
      Artifice.replace_net_http(net_http)
      Gem::Request::ConnectionPools.client = net_http
      Gem::RemoteFetcher.fetcher.close_all

      expected_out = <<~MSG
        Here's your OpenSSL environment:

        OpenSSL:       #{OpenSSL::VERSION}
        Compiled with: #{OpenSSL::OPENSSL_VERSION}
        Loaded with:   #{OpenSSL::OPENSSL_LIBRARY_VERSION}

        Trying connections to https://example.org:
        Bundler:       success
        RubyGems:      success
        Ruby net/http: success

        Hooray! This Ruby can connect to example.org.
        You are all set to use Bundler and RubyGems.

      MSG

      subject = Bundler::CLI::Doctor::SSL.new("tls-version": "1.3", "verify-mode": :none, host: "example.org")
      expect { subject.run }.to output(expected_out).to_stdout.and output("").to_stderr
      expect(net_http.verify_mode).to eq(0)
      expect(net_http.min_version.to_s).to eq("TLS1_3")
      expect(net_http.max_version.to_s).to eq("TLS1_3")
    end

    it "warns when TLS1.2 is not supported" do
      expected_out = <<~MSG
        Here's your OpenSSL environment:

        OpenSSL:       #{OpenSSL::VERSION}
        Compiled with: #{OpenSSL::OPENSSL_VERSION}
        Loaded with:   #{OpenSSL::OPENSSL_LIBRARY_VERSION}

        Trying connections to https://rubygems.org:
        Bundler:       success
        RubyGems:      success
        Ruby net/http: success

        Hooray! This Ruby can connect to rubygems.org.
        You are all set to use Bundler and RubyGems.

      MSG

      expected_err = <<~MSG

        WARNING: Although your Ruby can connect to rubygems.org today, your OpenSSL is very old!
        WARNING: You will need to upgrade OpenSSL to use rubygems.org.

      MSG

      previous_version = OpenSSL::SSL::TLS1_2_VERSION
      OpenSSL::SSL.send(:remove_const, :TLS1_2_VERSION)

      subject = Bundler::CLI::Doctor::SSL.new({})
      expect { subject.run }.to output(expected_out).to_stdout.and output(expected_err).to_stderr
    ensure
      OpenSSL::SSL.const_set(:TLS1_2_VERSION, previous_version)
    end
  end
end
