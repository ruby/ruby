# frozen_string_literal: true

module Bundler
  module Plugin
    module Events
      def self.define(const, event)
        const = const.to_sym.freeze
        if const_defined?(const) && const_get(const) != event
          raise ArgumentError, "Attempting to reassign #{const} to a different value"
        end
        const_set(const, event) unless const_defined?(const)
        @events ||= {}
        @events[event] = const
      end
      private_class_method :define

      def self.reset
        @events.each_value do |const|
          remove_const(const)
        end
        @events = nil
      end
      private_class_method :reset

      # Check if an event has been defined
      # @param event [String] An event to check
      # @return [Boolean] A boolean indicating if the event has been defined
      def self.defined_event?(event)
        @events ||= {}
        @events.key?(event)
      end

      # @!parse
      #   A hook called before the Gemfile is evaluated
      #   Includes the Gemfile path and the Lockfile path
      #   GEM_BEFORE_EVAL = "before-eval"
      define :GEM_BEFORE_EVAL, "before-eval"

      # @!parse
      #   A hook called after the Gemfile is evaluated
      #   Includes a Bundler::Definition
      #   GEM_AFTER_EVAL = "after-eval"
      define :GEM_AFTER_EVAL, "after-eval"

      # @!parse
      #   A hook called before any gems install
      #   Includes an Array of Bundler::Dependency objects
      #   GEM_BEFORE_INSTALL_ALL = "before-install-all"
      define :GEM_BEFORE_INSTALL_ALL, "before-install-all"

      # @!parse
      #   A hook called before each individual gem is downloaded from a remote source.
      #   Includes a Gem::Specification. Does not fire on cache hits.
      #   GEM_BEFORE_FETCH = "before-fetch"
      define :GEM_BEFORE_FETCH, "before-fetch"

      # @!parse
      #   A hook called after each individual gem is downloaded from a remote source.
      #   Includes a Gem::Specification. Does not fire on cache hits.
      #   GEM_AFTER_FETCH = "after-fetch"
      define :GEM_AFTER_FETCH, "after-fetch"

      # @!parse
      #   A hook called before a git source is fetched or checked out.
      #   Includes a Bundler::Source::Git reference.
      #   GIT_BEFORE_FETCH = "before-git-fetch"
      define :GIT_BEFORE_FETCH, "before-git-fetch"

      # @!parse
      #   A hook called after a git source is fetched or checked out.
      #   Includes a Bundler::Source::Git reference.
      #   GIT_AFTER_FETCH = "after-git-fetch"
      define :GIT_AFTER_FETCH, "after-git-fetch"

      # @!parse
      #   A hook called before each individual gem is installed
      #   Includes a Bundler::ParallelInstaller::SpecInstallation.
      #   No state, error, post_install_message will be present as nothing has installed yet
      #   GEM_BEFORE_INSTALL = "before-install"
      define :GEM_BEFORE_INSTALL, "before-install"

      # @!parse
      #   A hook called after each individual gem is installed
      #   Includes a Bundler::ParallelInstaller::SpecInstallation.
      #     - If state is failed, an error will be present.
      #     - If state is success, a post_install_message may be present.
      #   GEM_AFTER_INSTALL = "after-install"
      define :GEM_AFTER_INSTALL,  "after-install"

      # @!parse
      #   A hook called after any gems install
      #   Includes an Array of Bundler::Dependency objects
      #   GEM_AFTER_INSTALL_ALL = "after-install-all"
      define :GEM_AFTER_INSTALL_ALL,  "after-install-all"

      # @!parse
      #   A hook called before any gems require
      #   Includes an Array of Bundler::Dependency objects.
      #   GEM_BEFORE_REQUIRE_ALL = "before-require-all"
      define :GEM_BEFORE_REQUIRE_ALL, "before-require-all"

      # @!parse
      #   A hook called before each individual gem is required
      #   Includes a Bundler::Dependency.
      #   GEM_BEFORE_REQUIRE = "before-require"
      define :GEM_BEFORE_REQUIRE, "before-require"

      # @!parse
      #   A hook called after each individual gem is required
      #   Includes a Bundler::Dependency.
      #   GEM_AFTER_REQUIRE = "after-require"
      define :GEM_AFTER_REQUIRE,  "after-require"

      # @!parse
      #   A hook called after all gems required
      #   Includes an Array of Bundler::Dependency objects.
      #   GEM_AFTER_REQUIRE_ALL = "after-require-all"
      define :GEM_AFTER_REQUIRE_ALL, "after-require-all"
    end
  end
end
