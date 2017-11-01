# frozen_string_literal: true

require "bundler/vendored_thor" unless defined?(Thor)
require "bundler"

module Bundler
  class GemHelper
    include Rake::DSL if defined? Rake::DSL

    class << self
      # set when install'd.
      attr_accessor :instance

      def install_tasks(opts = {})
        new(opts[:dir], opts[:name]).install
      end

      def gemspec(&block)
        gemspec = instance.gemspec
        block.call(gemspec) if block
        gemspec
      end
    end

    attr_reader :spec_path, :base, :gemspec

    def initialize(base = nil, name = nil)
      Bundler.ui = UI::Shell.new
      @base = (base ||= SharedHelpers.pwd)
      gemspecs = name ? [File.join(base, "#{name}.gemspec")] : Dir[File.join(base, "{,*}.gemspec")]
      raise "Unable to determine name from existing gemspec. Use :name => 'gemname' in #install_tasks to manually set it." unless gemspecs.size == 1
      @spec_path = gemspecs.first
      @gemspec = Bundler.load_gemspec(@spec_path)
    end

    def install
      built_gem_path = nil

      desc "Build #{name}-#{version}.gem into the pkg directory."
      task "build" do
        built_gem_path = build_gem
      end

      desc "Build and install #{name}-#{version}.gem into system gems."
      task "install" => "build" do
        install_gem(built_gem_path)
      end

      desc "Build and install #{name}-#{version}.gem into system gems without network access."
      task "install:local" => "build" do
        install_gem(built_gem_path, :local)
      end

      desc "Create tag #{version_tag} and build and push #{name}-#{version}.gem to #{gem_push_host}\n" \
           "To prevent publishing in RubyGems use `gem_push=no rake release`"
      task "release", [:remote] => ["build", "release:guard_clean",
                                    "release:source_control_push", "release:rubygem_push"] do
      end

      task "release:guard_clean" do
        guard_clean
      end

      task "release:source_control_push", [:remote] do |_, args|
        tag_version { git_push(args[:remote]) } unless already_tagged?
      end

      task "release:rubygem_push" do
        rubygem_push(built_gem_path) if gem_push?
      end

      GemHelper.instance = self
    end

    def build_gem
      file_name = nil
      sh("gem build -V '#{spec_path}'") do
        file_name = File.basename(built_gem_path)
        SharedHelpers.filesystem_access(File.join(base, "pkg")) {|p| FileUtils.mkdir_p(p) }
        FileUtils.mv(built_gem_path, "pkg")
        Bundler.ui.confirm "#{name} #{version} built to pkg/#{file_name}."
      end
      File.join(base, "pkg", file_name)
    end

    def install_gem(built_gem_path = nil, local = false)
      built_gem_path ||= build_gem
      out, _ = sh_with_code("gem install '#{built_gem_path}'#{" --local" if local}")
      raise "Couldn't install gem, run `gem install #{built_gem_path}' for more detailed output" unless out[/Successfully installed/]
      Bundler.ui.confirm "#{name} (#{version}) installed."
    end

  protected

    def rubygem_push(path)
      gem_command = "gem push '#{path}'"
      gem_command += " --key #{gem_key}" if gem_key
      gem_command += " --host #{allowed_push_host}" if allowed_push_host
      unless allowed_push_host || Bundler.user_home.join(".gem/credentials").file?
        raise "Your rubygems.org credentials aren't set. Run `gem push` to set them."
      end
      sh(gem_command)
      Bundler.ui.confirm "Pushed #{name} #{version} to #{gem_push_host}"
    end

    def built_gem_path
      Dir[File.join(base, "#{name}-*.gem")].sort_by {|f| File.mtime(f) }.last
    end

    def git_push(remote = "")
      perform_git_push remote
      perform_git_push "#{remote} --tags"
      Bundler.ui.confirm "Pushed git commits and tags."
    end

    def allowed_push_host
      @gemspec.metadata["allowed_push_host"] if @gemspec.respond_to?(:metadata)
    end

    def gem_push_host
      env_rubygems_host = ENV["RUBYGEMS_HOST"]
      env_rubygems_host = nil if
        env_rubygems_host && env_rubygems_host.empty?

      allowed_push_host || env_rubygems_host || "rubygems.org"
    end

    def perform_git_push(options = "")
      cmd = "git push #{options}"
      out, code = sh_with_code(cmd)
      raise "Couldn't git push. `#{cmd}' failed with the following output:\n\n#{out}\n" unless code == 0
    end

    def already_tagged?
      return false unless sh("git tag").split(/\n/).include?(version_tag)
      Bundler.ui.confirm "Tag #{version_tag} has already been created."
      true
    end

    def guard_clean
      clean? && committed? || raise("There are files that need to be committed first.")
    end

    def clean?
      sh_with_code("git diff --exit-code")[1] == 0
    end

    def committed?
      sh_with_code("git diff-index --quiet --cached HEAD")[1] == 0
    end

    def tag_version
      sh "git tag -m \"Version #{version}\" #{version_tag}"
      Bundler.ui.confirm "Tagged #{version_tag}."
      yield if block_given?
    rescue
      Bundler.ui.error "Untagging #{version_tag} due to error."
      sh_with_code "git tag -d #{version_tag}"
      raise
    end

    def version
      gemspec.version
    end

    def version_tag
      "v#{version}"
    end

    def name
      gemspec.name
    end

    def sh(cmd, &block)
      out, code = sh_with_code(cmd, &block)
      unless code.zero?
        raise(out.empty? ? "Running `#{cmd}` failed. Run this command directly for more detailed output." : out)
      end
      out
    end

    def sh_with_code(cmd, &block)
      cmd += " 2>&1"
      outbuf = String.new
      Bundler.ui.debug(cmd)
      SharedHelpers.chdir(base) do
        outbuf = `#{cmd}`
        status = $?.exitstatus
        block.call(outbuf) if status.zero? && block
        [outbuf, status]
      end
    end

    def gem_key
      Bundler.settings["gem.push_key"].to_s.downcase if Bundler.settings["gem.push_key"]
    end

    def gem_push?
      !%w[n no nil false off 0].include?(ENV["gem_push"].to_s.downcase)
    end
  end
end
