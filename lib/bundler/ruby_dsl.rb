# frozen_string_literal: true

module Bundler
  module RubyDsl
    def ruby(*ruby_version)
      options = ruby_version.last.is_a?(Hash) ? ruby_version.pop : {}
      ruby_version.flatten!

      raise GemfileError, "Please define :engine_version" if options[:engine] && options[:engine_version].nil?
      raise GemfileError, "Please define :engine" if options[:engine_version] && options[:engine].nil?

      if options[:file]
        raise GemfileError, "Do not pass version argument when using :file option" unless ruby_version.empty?
        ruby_version << normalize_ruby_file(options[:file])
      end

      if options[:engine] == "ruby" && options[:engine_version] &&
         ruby_version != Array(options[:engine_version])
        raise GemfileEvalError, "ruby_version must match the :engine_version for MRI"
      end
      @ruby_version = RubyVersion.new(ruby_version, options[:patchlevel], options[:engine], options[:engine_version])
    end

    # Support the various file formats found in .ruby-version files.
    #
    #     3.2.2
    #     ruby-3.2.2
    #
    # Also supports .tool-versions files for asdf. Lines not starting with "ruby" are ignored.
    #
    #     ruby 2.5.1 # comment is ignored
    #     ruby   2.5.1# close comment and extra spaces doesn't confuse
    #
    # Intentionally does not support `3.2.1@gemset` since rvm recommends using .ruby-gemset instead
    def normalize_ruby_file(filename)
      file_content = Bundler.read_file(Bundler.root.join(filename))
      # match "ruby-3.2.2" or "ruby   3.2.2" capturing version string up to the first space or comment
      if /^ruby(-|\s+)([^\s#]+)/.match(file_content)
        $2
      else
        file_content.strip
      end
    end
  end
end
