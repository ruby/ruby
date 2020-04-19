module Ruby
  module Signature
    class Vendorer
      attr_reader :vendor_dir

      def initialize(vendor_dir:)
        @vendor_dir = vendor_dir
      end

      def ensure_dir
        unless vendor_dir.directory?
          vendor_dir.mkpath
        end

        yield
      end

      def clean!
        ensure_dir do
          Signature.logger.info "Cleaning vendor root: #{vendor_dir}..."
          vendor_dir.rmtree
        end
      end

      def stdlib!()
        ensure_dir do
          Signature.logger.info "Vendoring stdlib: #{EnvironmentLoader::STDLIB_ROOT} => #{vendor_dir + "stdlib"}..."
          FileUtils.copy_entry EnvironmentLoader::STDLIB_ROOT, vendor_dir + "stdlib"
        end
      end

      def gem!(name, version)
        ensure_dir do
          sig_path = EnvironmentLoader.gem_sig_path(name, version)
          Signature.logger.debug "Checking gem signature path: name=#{name}, version=#{version}, path=#{sig_path}"

          if sig_path&.directory?
            gems_dir = vendor_dir + "gems"
            gems_dir.mkpath unless gems_dir.directory?

            gem_dir = gems_dir + name
            Signature.logger.info "Vendoring gem(#{name}:#{version}): #{sig_path} => #{gem_dir}..."
            FileUtils.copy_entry sig_path, gem_dir
          end
        end
      end
    end
  end
end
