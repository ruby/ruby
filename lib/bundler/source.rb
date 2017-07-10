# frozen_string_literal: true
module Bundler
  class Source
    autoload :Gemspec,  "bundler/source/gemspec"
    autoload :Git,      "bundler/source/git"
    autoload :Path,     "bundler/source/path"
    autoload :Rubygems, "bundler/source/rubygems"

    attr_accessor :dependency_names

    def unmet_deps
      specs.unmet_dependency_names
    end

    def version_message(spec)
      message = "#{spec.name} #{spec.version}"
      message += " (#{spec.platform})" if spec.platform != Gem::Platform::RUBY && !spec.platform.nil?

      if Bundler.locked_gems
        locked_spec = Bundler.locked_gems.specs.find {|s| s.name == spec.name }
        locked_spec_version = locked_spec.version if locked_spec
        if locked_spec_version && spec.version != locked_spec_version
          message += Bundler.ui.add_color(" (was #{locked_spec_version})", :green)
        end
      end

      message
    end

    def can_lock?(spec)
      spec.source == self
    end

    def include?(other)
      other == self
    end

    def inspect
      "#<#{self.class}:0x#{object_id} #{self}>"
    end
  end
end
