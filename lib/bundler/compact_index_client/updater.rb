# frozen_string_literal: true
require "fileutils"
require "stringio"
require "tmpdir"
require "zlib"

module Bundler
  class CompactIndexClient
    class Updater
      class MisMatchedChecksumError < Error
        def initialize(path, server_checksum, local_checksum)
          @path = path
          @server_checksum = server_checksum
          @local_checksum = local_checksum
        end

        def message
          "The checksum of /#{@path} does not match the checksum provided by the server! Something is wrong " \
            "(local checksum is #{@local_checksum.inspect}, was expecting #{@server_checksum.inspect})."
        end
      end

      def initialize(fetcher)
        @fetcher = fetcher
      end

      def update(local_path, remote_path, retrying = nil)
        headers = {}

        Dir.mktmpdir("bundler-compact-index-") do |local_temp_dir|
          local_temp_path = Pathname.new(local_temp_dir).join(local_path.basename)

          # first try to fetch any new bytes on the existing file
          if retrying.nil? && local_path.file?
            FileUtils.cp local_path, local_temp_path
            headers["If-None-Match"] = etag_for(local_temp_path)
            headers["Range"] = "bytes=#{local_temp_path.size}-"
          else
            # Fastly ignores Range when Accept-Encoding: gzip is set
            headers["Accept-Encoding"] = "gzip"
          end

          response = @fetcher.call(remote_path, headers)
          return nil if response.is_a?(Net::HTTPNotModified)

          content = response.body
          if response["Content-Encoding"] == "gzip"
            content = Zlib::GzipReader.new(StringIO.new(content)).read
          end

          mode = response.is_a?(Net::HTTPPartialContent) ? "a" : "w"
          SharedHelpers.filesystem_access(local_temp_path) do
            local_temp_path.open(mode) {|f| f << content }
          end

          response_etag = response["ETag"].gsub(%r{\AW/}, "")
          if etag_for(local_temp_path) == response_etag
            SharedHelpers.filesystem_access(local_path) do
              FileUtils.mv(local_temp_path, local_path)
            end
            return nil
          end

          if retrying
            raise MisMatchedChecksumError.new(remote_path, response_etag, etag_for(local_temp_path))
          end

          update(local_path, remote_path, :retrying)
        end
      end

      def etag_for(path)
        sum = checksum_for_file(path)
        sum ? %("#{sum}") : nil
      end

      def checksum_for_file(path)
        return nil unless path.file?
        # This must use IO.read instead of Digest.file().hexdigest
        # because we need to preserve \n line endings on windows when calculating
        # the checksum
        SharedHelpers.filesystem_access(path, :read) do
          Digest::MD5.hexdigest(IO.read(path))
        end
      end
    end
  end
end
