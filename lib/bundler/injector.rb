# frozen_string_literal: true
module Bundler
  class Injector
    def self.inject(new_deps, options = {})
      injector = new(new_deps, options)
      injector.inject(Bundler.default_gemfile, Bundler.default_lockfile)
    end

    def initialize(new_deps, options = {})
      @new_deps = new_deps
      @options = options
    end

    def inject(gemfile_path, lockfile_path)
      if Bundler.settings[:frozen]
        # ensure the lock and Gemfile are synced
        Bundler.definition.ensure_equivalent_gemfile_and_lockfile(true)
        # temporarily remove frozen while we inject
        frozen = Bundler.settings.delete(:frozen)
      end

      # evaluate the Gemfile we have now
      builder = Dsl.new
      builder.eval_gemfile(gemfile_path)

      # don't inject any gems that are already in the Gemfile
      @new_deps -= builder.dependencies

      # add new deps to the end of the in-memory Gemfile
      # Set conservative versioining to false because we want to let the resolver resolve the version first
      builder.eval_gemfile("injected gems", build_gem_lines(false)) if @new_deps.any?

      # resolve to see if the new deps broke anything
      @definition = builder.to_definition(lockfile_path, {})
      @definition.resolve_remotely!

      # since nothing broke, we can add those gems to the gemfile
      append_to(gemfile_path, build_gem_lines(@options[:conservative_versioning])) if @new_deps.any?

      # since we resolved successfully, write out the lockfile
      @definition.lock(Bundler.default_lockfile)

      # return an array of the deps that we added
      return @new_deps
    ensure
      Bundler.settings[:frozen] = "1" if frozen
    end

  private

    def conservative_version(spec)
      version = spec.version
      return ">= 0" if version.nil?
      segments = version.segments
      seg_end_index = version >= Gem::Version.new("1.0") ? 1 : 2

      prerelease_suffix = version.to_s.gsub(version.release.to_s, "") if version.prerelease?
      "~> #{segments[0..seg_end_index].join(".")}#{prerelease_suffix}"
    end

    def build_gem_lines(conservative_versioning)
      @new_deps.map do |d|
        name = d.name.dump

        requirement = if conservative_versioning
          ", \"#{conservative_version(@definition.specs[d.name][0])}\""
        else
          ", #{d.requirement.as_list.map(&:dump).join(", ")}"
        end

        if d.groups != Array(:default)
          group = d.groups.size == 1 ? ", :group => #{d.groups.inspect}" : ", :groups => #{d.groups.inspect}"
        end

        source = ", :source => \"#{d.source}\"" unless d.source.nil?

        %(gem #{name}#{requirement}#{group}#{source})
      end.join("\n")
    end

    def append_to(gemfile_path, new_gem_lines)
      gemfile_path.open("a") do |f|
        f.puts
        if @options["timestamp"] || @options["timestamp"].nil?
          f.puts "# Added at #{Time.now} by #{`whoami`.chomp}:"
        end
        f.puts new_gem_lines
      end
    end
  end
end
