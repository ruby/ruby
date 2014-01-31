# :stopdoc:

#--
# This file contains all sorts of little compatibility hacks that we've
# had to introduce over the years. Quarantining them into one file helps
# us know when we can get rid of them.
#
# Ruby 1.9.x has introduced some things that are awkward, and we need to
# support them, so we define some constants to use later.
#++
module Gem
  # Only MRI 1.9.2 has the custom prelude.
  GEM_PRELUDE_SUCKAGE = RUBY_VERSION =~ /^1\.9\.2/ and RUBY_ENGINE == "ruby"
end

# Gem::QuickLoader exists in the gem prelude code in ruby 1.9.2 itself.
# We gotta get rid of it if it's there, before we do anything else.
if Gem::GEM_PRELUDE_SUCKAGE and defined?(Gem::QuickLoader) then
  Gem::QuickLoader.remove

  $LOADED_FEATURES.delete Gem::QuickLoader.path_to_full_rubygems_library

  if $LOADED_FEATURES.any? do |path| path.end_with? '/rubygems.rb' end then
    # TODO path does not exist here
    raise LoadError, "another rubygems is already loaded from #{path}"
  end

  class << Gem
    remove_method :try_activate if Gem.respond_to?(:try_activate, true)
  end
end

module Gem
  RubyGemsVersion = VERSION

  # TODO remove at RubyGems 3

  RbConfigPriorities = %w[
    MAJOR
    MINOR
    TEENY
    EXEEXT RUBY_SO_NAME arch bindir datadir libdir ruby_install_name
    ruby_version rubylibprefix sitedir sitelibdir vendordir vendorlibdir
    rubylibdir
  ]

  unless defined?(ConfigMap)
    ##
    # Configuration settings from ::RbConfig
    ConfigMap = Hash.new do |cm, key| # TODO remove at RubyGems 3
      cm[key] = RbConfig::CONFIG[key.to_s]
    end
  else
    RbConfigPriorities.each do |key|
      ConfigMap[key.to_sym] = RbConfig::CONFIG[key]
    end
  end

  RubyGemsPackageVersion = VERSION
end
