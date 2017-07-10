require 'bundler/vendor/postit/lib/postit/parser'

module BundlerVendoredPostIt::PostIt
  class Environment
    def initialize(argv)
      @argv = argv
    end

    def env_var_version
      ENV['BUNDLER_VERSION']
    end

    def cli_arg_version
      return unless str = @argv.first
      str = str.dup.force_encoding('BINARY') if str.respond_to?(:force_encoding)
      if Gem::Version.correct?(str)
        @argv.shift
        str
      end
    end

    def gemfile
      ENV['BUNDLE_GEMFILE'] || 'Gemfile'
    end

    def lockfile
      File.expand_path case File.basename(gemfile)
                       when 'gems.rb' then gemfile.sub(/\.rb$/, gemfile)
                       else "#{gemfile}.lock"
                       end
    end

    def lockfile_version
      BundlerVendoredPostIt::PostIt::Parser.new(lockfile).parse
    end

    def bundler_version
      @bundler_version ||= begin
        env_var_version || cli_arg_version ||
          lockfile_version || "#{Gem::Requirement.default}.a"
      end
    end
  end
end
