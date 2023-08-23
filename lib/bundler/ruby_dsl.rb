# frozen_string_literal: true

module Bundler
  module RubyDsl
    def ruby(*ruby_version)
      options = ruby_version.last.is_a?(Hash) ? ruby_version.pop : {}
      ruby_version.flatten!

      raise GemfileError, "Please define :engine_version" if options[:engine] && options[:engine_version].nil?
      raise GemfileError, "Please define :engine" if options[:engine_version] && options[:engine].nil?

      if options[:file]
        raise GemfileError, "Cannot specify version when using the file option" if ruby_version.any?
        file_content = Bundler.read_file(Bundler.root.join(options[:file]))
        if /^ruby\s+(.*)$/.match(file_content) # match .tool-versions files
          ruby_version << $1.split("#", 2).first.strip # remove trailing comment
        else
          ruby_version << file_content.strip
        end
      end

      if options[:engine] == "ruby" && options[:engine_version] &&
         ruby_version != Array(options[:engine_version])
        raise GemfileEvalError, "ruby_version must match the :engine_version for MRI"
      end
      @ruby_version = RubyVersion.new(ruby_version, options[:patchlevel], options[:engine], options[:engine_version])
    end
  end
end
