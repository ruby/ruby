##
# RubyGems adds the #gem method to allow activation of specific gem versions
# and overrides the #require method on Kernel to make gems appear as if they
# live on the <code>$LOAD_PATH</code>.  See the documentation of these methods
# for further detail.

module Kernel

  # REFACTOR: This should be pulled out into some kind of hacks file.
  remove_method :gem if 'method' == defined? gem # from gem_prelude.rb on 1.9

  ##
  # Use Kernel#gem to activate a specific version of +gem_name+.
  #
  # +requirements+ is a list of version requirements that the
  # specified gem must match, most commonly "= example.version.number".  See
  # Gem::Requirement for how to specify a version requirement.
  #
  # If you will be activating the latest version of a gem, there is no need to
  # call Kernel#gem, Kernel#require will do the right thing for you.
  #
  # Kernel#gem returns true if the gem was activated, otherwise false.  If the
  # gem could not be found, didn't match the version requirements, or a
  # different version was already activated, an exception will be raised.
  #
  # Kernel#gem should be called *before* any require statements (otherwise
  # RubyGems may load a conflicting library version).
  #
  # Kernel#gem only loads prerelease versions when prerelease +requirements+
  # are given:
  #
  #   gem 'rake', '>= 1.1.a', '< 2'
  #
  # In older RubyGems versions, the environment variable GEM_SKIP could be
  # used to skip activation of specified gems, for example to test out changes
  # that haven't been installed yet.  Now RubyGems defers to -I and the
  # RUBYLIB environment variable to skip activation of a gem.
  #
  # Example:
  #
  #   GEM_SKIP=libA:libB ruby -I../libA -I../libB ./mycode.rb

  def gem(gem_name, *requirements) # :doc:
    skip_list = (ENV['GEM_SKIP'] || "").split(/:/)
    raise Gem::LoadError, "skipping #{gem_name}" if skip_list.include? gem_name

    if gem_name.kind_of? Gem::Dependency
      unless Gem::Deprecate.skip
        warn "#{Gem.location_of_caller.join ':'}:Warning: Kernel.gem no longer "\
          "accepts a Gem::Dependency object, please pass the name "\
          "and requirements directly"
      end

      requirements = gem_name.requirement
      gem_name = gem_name.name
    end

    dep = Gem::Dependency.new(gem_name, *requirements)

    loaded = Gem.loaded_specs[gem_name]

    return false if loaded && dep.matches_spec?(loaded)

    spec = dep.to_spec

    Gem::LOADED_SPECS_MUTEX.synchronize {
      spec.activate
    } if spec
  end

  private :gem

end
