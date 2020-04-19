module Ruby
  module Signature
    class EnvironmentLoader
      class UnknownLibraryNameError < StandardError
        attr_reader :name

        def initialize(name:)
          @name = name
          super "Cannot find a library or gem: `#{name}`"
        end
      end

      LibraryPath = Struct.new(:name, :path, keyword_init: true)
      GemPath = Struct.new(:name, :version, :path, keyword_init: true)

      attr_reader :paths
      attr_reader :stdlib_root
      attr_reader :gem_vendor_path

      STDLIB_ROOT = Pathname(__dir__) + "../../../stdlib"

      def self.gem_sig_path(name, version)
        Pathname(Gem::Specification.find_by_name(name, version).gem_dir) + "sig"
      rescue Gem::MissingSpecError
        nil
      end

      def initialize(stdlib_root: STDLIB_ROOT, gem_vendor_path: nil)
        @stdlib_root = stdlib_root
        @gem_vendor_path = gem_vendor_path
        @paths = []
        @no_builtin = false
      end

      def add(path: nil, library: nil)
        case
        when path
          @paths << path
        when library
          name, version = self.class.parse_library(library)

          case
          when !version && path = stdlib?(name)
            @paths << LibraryPath.new(name: name, path: path)
          when (path = gem?(name, version))
            @paths << GemPath.new(name: name, version: version, path: path)
          else
            raise UnknownLibraryNameError.new(name: library)
          end
        end
      end

      def self.parse_library(lib)
        lib.split(/:/)
      end

      def stdlib?(name)
        if stdlib_root
          path = stdlib_root + name
          if path.directory?
            path
          end
        end
      end

      def gem?(name, version)
        if gem_vendor_path
          # Try vendored RBS first
          gem_dir = gem_vendor_path + name
          if gem_dir.directory?
            return gem_dir
          end
        end

        # Try ruby gem library
        self.class.gem_sig_path(name, version)
      end

      def each_signature(path = nil, immediate: true, &block)
        if block_given?
          if path
            case
            when path.file?
              if path.extname == ".rbs" || immediate
                yield path
              end
            when path.directory?
              path.children.each do |child|
                each_signature child, immediate: false, &block
              end
            end
          else
            paths.each do |path|
              case path
              when Pathname
                each_signature path, immediate: immediate, &block
              when LibraryPath
                each_signature path.path, immediate: immediate, &block
              when GemPath
                each_signature path.path, immediate: immediate, &block
              end
            end
          end
        else
          enum_for :each_signature, path, immediate: immediate
        end
      end

      def no_builtin!
        @no_builtin = true
      end

      def no_builtin?
        @no_builtin
      end

      def load(env:)
        signature_files = []

        unless no_builtin?
          signature_files.push(*each_signature(stdlib_root + "builtin"))
        end

        each_signature do |path|
          signature_files.push path
        end

        signature_files.each do |file|
          buffer = Buffer.new(name: file.to_s, content: file.read)
          env.buffers.push(buffer)
          Parser.parse_signature(buffer).each do |decl|
            env << decl
          end
        end
      end
    end
  end
end
