# frozen_string_literal: true

module Bundler
  class CLI::Open
    attr_reader :options, :name, :path
    def initialize(options, name)
      @options = options
      @name = name
      @path = options[:path] unless options[:path].nil?
    end

    def run
      raise InvalidOption, "Cannot specify `--path` option without a value" if !@path.nil? && @path.empty?
      editor = [ENV["BUNDLER_EDITOR"], ENV["VISUAL"], ENV["EDITOR"]].find {|e| !e.nil? && !e.empty? }
      return Bundler.ui.info("To open a bundled gem, set $EDITOR or $BUNDLER_EDITOR") unless editor
      return unless spec = Bundler::CLI::Common.select_spec(name, :regex_match)
      if spec.default_gem?
        Bundler.ui.info "Unable to open #{name} because it's a default gem, so the directory it would normally be installed to does not exist."
      else
        root_path = spec.full_gem_path
        command = editor_command(editor) << File.join([root_path, path].compact)
        Bundler.with_original_env do
          system(*command, { chdir: root_path })
        end || Bundler.ui.info("Could not run '#{command.join(" ")}'")
      end
    end

    def editor_command(editor)
      # On Windows an editor is often configured with a full path such as
      # C:\Program Files\Microsoft VS Code\Code.exe, which shell splitting
      # would corrupt. Take a value that names an existing file as a
      # single word.
      return [editor] if Gem.win_platform? && File.file?(editor)

      require "shellwords"
      Shellwords.split(editor)
    end
  end
end
