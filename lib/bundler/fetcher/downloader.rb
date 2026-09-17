# frozen_string_literal: true

module Bundler
  class Fetcher
    class Downloader
      HTTP_NON_RETRYABLE_ERRORS = [
        SocketError,
        Errno::EADDRNOTAVAIL,
        Errno::ECONNREFUSED,
        Errno::EHOSTDOWN,
        Errno::EHOSTUNREACH,
        Errno::ENETDOWN,
        Errno::ENETUNREACH,
      ].freeze

      # The vendored net-http raises Gem::Timeout::Error, but when Gem::Net is
      # the real Net (hosts without a vendored net-http), timeouts are plain
      # Timeout::Error subclasses instead.
      HTTP_RETRYABLE_ERRORS = [
        Gem::Timeout::Error,
        *(::Timeout::Error if defined?(::Timeout::Error)),
        EOFError,
        Errno::EINVAL,
        Errno::ECONNRESET,
        Errno::ETIMEDOUT,
        Errno::EAGAIN,
        Gem::Net::HTTPBadResponse,
        Gem::Net::HTTPHeaderSyntaxError,
        Gem::Net::ProtocolError,
        Zlib::BufError,
      ].freeze

      attr_reader :connections
      attr_reader :redirect_limit

      def initialize(connections, redirect_limit)
        @connections = connections
        @redirect_limit = redirect_limit
      end

      def fetch(uri, headers = {}, counter = 0)
        raise HTTPError, "Too many redirects" if counter >= redirect_limit

        filtered_uri = URICredentialsFilter.credential_filtered_uri(uri)

        response = request(uri, headers)
        Bundler.ui.debug("HTTP #{response.code} #{response.message} #{filtered_uri}")

        case response
        when Gem::Net::HTTPSuccess, Gem::Net::HTTPNotModified
          response
        when Gem::Net::HTTPRedirection
          new_uri = Gem::URI.parse(response["location"])
          # Following a downgrade would put the credentials this request carries
          # on a plaintext connection, so refuse it like Gem::RemoteFetcher does.
          if https?(uri) && !https?(new_uri)
            raise HTTPError, "Redirecting to a non-https URI is not allowed: #{URICredentialsFilter.credential_filtered_uri(new_uri)}"
          end
          if new_uri.host == uri.host
            new_uri.user = uri.user
            new_uri.password = uri.password
          end
          fetch(new_uri, headers, counter + 1)
        when Gem::Net::HTTPRequestedRangeNotSatisfiable
          new_headers = headers.dup
          new_headers.delete("Range")
          fetch(uri, new_headers)
        when Gem::Net::HTTPRequestEntityTooLarge
          raise FallbackError, response.body
        when Gem::Net::HTTPTooManyRequests
          raise TooManyRequestsError, response.body
        when Gem::Net::HTTPUnauthorized
          raise BadAuthenticationError, uri.host if uri.userinfo
          raise AuthenticationRequiredError, uri.host
        when Gem::Net::HTTPForbidden
          raise AuthenticationForbiddenError, uri.host
        when Gem::Net::HTTPNotFound
          raise FallbackError, "Gem::Net::HTTPNotFound: #{filtered_uri}"
        else
          message = "Gem::#{response.class.name.gsub(/\AGem::/, "")}"
          message += ": #{response.body}" unless response.body.empty?
          raise HTTPError, message
        end
      end

      def request(uri, headers)
        validate_uri_scheme!(uri)

        filtered_uri = URICredentialsFilter.credential_filtered_uri(uri)

        Bundler.ui.debug "HTTP GET #{filtered_uri}"
        connections.request(uri, headers)
      rescue Gem::RemoteFetcher::FetchError => e
        Bundler.ui.trace e

        case e.message
        when /certificate verify failed/
          raise CertificateFailureError.new(uri)
        when /host is down|host down/i
          raise network_down_error(uri, filtered_uri)
        else
          raise HTTPError, "Network error while fetching #{filtered_uri}" \
              " (#{e})"
        end
      rescue OpenSSL::SSL::SSLError
        raise CertificateFailureError.new(uri)
      rescue *HTTP_NON_RETRYABLE_ERRORS => e
        Bundler.ui.trace e

        raise network_down_error(uri, filtered_uri)
      rescue *HTTP_RETRYABLE_ERRORS => e
        Bundler.ui.trace e

        raise HTTPError, "Network error while fetching #{filtered_uri}" \
            " (#{e})"
      end

      private

      def network_down_error(uri, filtered_uri)
        host = uri.host
        host_port = "#{host}:#{uri.port}"
        host = host_port if filtered_uri.to_s.include?(host_port)
        NetworkDownError.new("Could not reach host #{host}. Check your network " \
          "connection and try again.")
      end

      def https?(uri)
        uri.scheme&.casecmp("https")&.zero?
      end

      def validate_uri_scheme!(uri)
        return if /\Ahttps?\z/.match?(uri.scheme)
        raise InvalidOption,
          "The request uri `#{uri}` has an invalid scheme (`#{uri.scheme}`). " \
          "Did you mean `http` or `https`?"
      end
    end
  end
end
