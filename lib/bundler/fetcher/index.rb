# frozen_string_literal: true

require_relative "base"
require "rubygems/remote_fetcher"

module Bundler
  class Fetcher
    class Index < Base
      def specs(_gem_names)
        Bundler.rubygems.fetch_all_remote_specs(remote)
      rescue Gem::RemoteFetcher::FetchError => e
        case e.message
        when /certificate verify failed/
          raise CertificateFailureError.new(display_uri)
        when /401/
          raise BadAuthenticationError, remote_uri if remote_uri.userinfo
          raise AuthenticationRequiredError, remote_uri
        when /403/
          raise BadAuthenticationError, remote_uri if remote_uri.userinfo
          raise AuthenticationRequiredError, remote_uri
        else
          raise HTTPError, "Could not fetch specs from #{display_uri} due to underlying error <#{e.message}>"
        end
      end

      def fetch_spec(spec)
        spec -= [nil, "ruby", ""]
        spec_file_name = "#{spec.join "-"}.gemspec"

        uri = Bundler::URI.parse("#{remote_uri}#{Gem::MARSHAL_SPEC_DIR}#{spec_file_name}.rz")
        if uri.scheme == "file"
          path = Bundler.rubygems.correct_for_windows_path(uri.path)
          Bundler.load_marshal Bundler.rubygems.inflate(Gem.read_binary(path))
        elsif cached_spec_path = gemspec_cached_path(spec_file_name)
          Bundler.load_gemspec(cached_spec_path)
        else
          Bundler.load_marshal Bundler.rubygems.inflate(downloader.fetch(uri).body)
        end
      rescue MarshalError
        raise HTTPError, "Gemspec #{spec} contained invalid data.\n" \
          "Your network or your gem server is probably having issues right now."
      end

      private

      # cached gem specification path, if one exists
      def gemspec_cached_path(spec_file_name)
        paths = Bundler.rubygems.spec_cache_dirs.map {|dir| File.join(dir, spec_file_name) }
        paths.find {|path| File.file? path }
      end
    end
  end
end
