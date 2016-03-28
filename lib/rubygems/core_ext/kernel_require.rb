# frozen_string_literal: true
#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require 'monitor'

module Kernel

  RUBYGEMS_ACTIVATION_MONITOR = Monitor.new # :nodoc:

  if defined?(gem_original_require) then
    # Ruby ships with a custom_require, override its require
    remove_method :require
  else
    ##
    # The Kernel#require from before RubyGems was loaded.

    alias gem_original_require require
    private :gem_original_require
  end

  ##
  # When RubyGems is required, Kernel#require is replaced with our own which
  # is capable of loading gems on demand.
  #
  # When you call <tt>require 'x'</tt>, this is what happens:
  # * If the file can be loaded from the existing Ruby loadpath, it
  #   is.
  # * Otherwise, installed gems are searched for a file that matches.
  #   If it's found in gem 'y', that gem is activated (added to the
  #   loadpath).
  #
  # The normal <tt>require</tt> functionality of returning false if
  # that file has already been loaded is preserved.

  def require path
    RUBYGEMS_ACTIVATION_MONITOR.enter

    path = path.to_path if path.respond_to? :to_path

    spec = Gem.find_unresolved_default_spec(path)
    if spec
      Gem.remove_unresolved_default_spec(spec)
      gem(spec.name)
    end

    # If there are no unresolved deps, then we can use just try
    # normal require handle loading a gem from the rescue below.

    if Gem::Specification.unresolved_deps.empty? then
      RUBYGEMS_ACTIVATION_MONITOR.exit
      return gem_original_require(path)
    end

    # If +path+ is for a gem that has already been loaded, don't
    # bother trying to find it in an unresolved gem, just go straight
    # to normal require.
    #--
    # TODO request access to the C implementation of this to speed up RubyGems

    spec = Gem::Specification.find_active_stub_by_path path

    begin
      RUBYGEMS_ACTIVATION_MONITOR.exit
      return gem_original_require(path)
    end if spec

    # Attempt to find +path+ in any unresolved gems...

    found_specs = Gem::Specification.find_in_unresolved path

    # If there are no directly unresolved gems, then try and find +path+
    # in any gems that are available via the currently unresolved gems.
    # For example, given:
    #
    #   a => b => c => d
    #
    # If a and b are currently active with c being unresolved and d.rb is
    # requested, then find_in_unresolved_tree will find d.rb in d because
    # it's a dependency of c.
    #
    if found_specs.empty? then
      found_specs = Gem::Specification.find_in_unresolved_tree path

      found_specs.each do |found_spec|
        found_spec.activate
      end

    # We found +path+ directly in an unresolved gem. Now we figure out, of
    # the possible found specs, which one we should activate.
    else

      # Check that all the found specs are just different
      # versions of the same gem
      names = found_specs.map(&:name).uniq

      if names.size > 1 then
        RUBYGEMS_ACTIVATION_MONITOR.exit
        raise Gem::LoadError, "#{path} found in multiple gems: #{names.join ', '}"
      end

      # Ok, now find a gem that has no conflicts, starting
      # at the highest version.
      valid = found_specs.reject { |s| s.has_conflicts? }.last

      unless valid then
        le = Gem::LoadError.new "unable to find a version of '#{names.first}' to activate"
        le.name = names.first
        RUBYGEMS_ACTIVATION_MONITOR.exit
        raise le
      end

      valid.activate
    end

    RUBYGEMS_ACTIVATION_MONITOR.exit
    return gem_original_require(path)
  rescue LoadError => load_error
    RUBYGEMS_ACTIVATION_MONITOR.enter

    begin
      if load_error.message.start_with?("Could not find") or
          (load_error.message.end_with?(path) and Gem.try_activate(path)) then
        require_again = true
      end
    ensure
      RUBYGEMS_ACTIVATION_MONITOR.exit
    end

    return gem_original_require(path) if require_again

    raise load_error
  end

  private :require

end

