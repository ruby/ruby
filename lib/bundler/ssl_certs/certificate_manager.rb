# frozen_string_literal: true

require "bundler/vendored_fileutils"
require "net/https"
require "openssl"

module Bundler
  module SSLCerts
    class CertificateManager
      attr_reader :bundler_cert_path, :bundler_certs, :rubygems_certs

      def self.update_from!(rubygems_path)
        new(rubygems_path).update!
      end

      def initialize(rubygems_path = nil)
        if rubygems_path
          rubygems_cert_path = File.join(rubygems_path, "lib/rubygems/ssl_certs")
          @rubygems_certs = certificates_in(rubygems_cert_path)
        end

        @bundler_cert_path = File.expand_path("..", __FILE__)
        @bundler_certs = certificates_in(bundler_cert_path)
      end

      def up_to_date?
        rubygems_certs.all? do |rc|
          bundler_certs.find do |bc|
            File.basename(bc) == File.basename(rc) && FileUtils.compare_file(bc, rc)
          end
        end
      end

      def update!
        return if up_to_date?

        FileUtils.rm bundler_certs
        FileUtils.cp rubygems_certs, bundler_cert_path
      end

      def connect_to(host)
        http = Net::HTTP.new(host, 443)
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        http.cert_store = store
        http.head("/")
      end

    private

      def certificates_in(path)
        Dir[File.join(path, "**/*.pem")].sort
      end

      def store
        @store ||= begin
          store = OpenSSL::X509::Store.new
          bundler_certs.each do |cert|
            store.add_file cert
          end
          store
        end
      end
    end
  end
end
