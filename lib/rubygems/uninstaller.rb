#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require 'fileutils'
require 'rubygems'
require 'rubygems/dependency_list'
require 'rubygems/doc_manager'
require 'rubygems/user_interaction'

##
# An Uninstaller.

class Gem::Uninstaller

  include Gem::UserInteraction

  ##
  # The directory a gem's executables will be installed into

  attr_reader :bin_dir

  ##
  # The gem repository the gem will be installed into

  attr_reader :gem_home

  ##
  # The Gem::Specification for the gem being uninstalled, only set during
  # #uninstall_gem

  attr_reader :spec

  ##
  # Constructs an uninstaller that will uninstall +gem+

  def initialize(gem, options = {})
    @gem = gem
    @version = options[:version] || Gem::Requirement.default
    gem_home = options[:install_dir] || Gem.dir
    @gem_home = File.expand_path gem_home
    @force_executables = options[:executables]
    @force_all = options[:all]
    @force_ignore = options[:ignore]
    @bin_dir = options[:bin_dir]

    spec_dir = File.join @gem_home, 'specifications'
    @source_index = Gem::SourceIndex.from_gems_in spec_dir
  end

  ##
  # Performs the uninstall of the gem.  This removes the spec, the Gem
  # directory, and the cached .gem file.

  def uninstall
    list = @source_index.find_name @gem, @version

    if list.empty? then
      raise Gem::InstallError, "Unknown gem #{@gem} #{@version}"

    elsif list.size > 1 and @force_all then
      remove_all list.dup

    elsif list.size > 1 then
      gem_names = list.collect {|gem| gem.full_name} + ["All versions"]

      say
      gem_name, index = choose_from_list "Select gem to uninstall:", gem_names

      if index == list.size then
        remove_all list.dup
      elsif index >= 0 && index < list.size then
        uninstall_gem list[index], list.dup
      else
        say "Error: must enter a number [1-#{list.size+1}]"
      end
    else
      uninstall_gem list.first, list.dup
    end
  end

  ##
  # Uninstalls gem +spec+

  def uninstall_gem(spec, specs)
    @spec = spec

    Gem.pre_uninstall_hooks.each do |hook|
      hook.call self
    end

    specs.each { |s| remove_executables s }
    remove spec, specs

    Gem.post_uninstall_hooks.each do |hook|
      hook.call self
    end

    @spec = nil
  end

  ##
  # Removes installed executables and batch files (windows only) for
  # +gemspec+.

  def remove_executables(gemspec)
    return if gemspec.nil?

    if gemspec.executables.size > 0 then
      bindir = @bin_dir ? @bin_dir : (Gem.bindir @gem_home)

      list = @source_index.find_name(gemspec.name).delete_if { |spec|
        spec.version == gemspec.version
      }

      executables = gemspec.executables.clone

      list.each do |spec|
        spec.executables.each do |exe_name|
          executables.delete(exe_name)
        end
      end

      return if executables.size == 0

      answer = if @force_executables.nil? then
                 ask_yes_no("Remove executables:\n" \
                            "\t#{gemspec.executables.join(", ")}\n\nin addition to the gem?",
                            true) # " # appease ruby-mode - don't ask
               else
                 @force_executables
               end

      unless answer then
        say "Executables and scripts will remain installed."
      else
        raise Gem::FilePermissionError, bindir unless File.writable? bindir

        gemspec.executables.each do |exe_name|
          say "Removing #{exe_name}"
          FileUtils.rm_f File.join(bindir, exe_name)
          FileUtils.rm_f File.join(bindir, "#{exe_name}.bat")
        end
      end
    end
  end

  ##
  # Removes all gems in +list+.
  #
  # NOTE: removes uninstalled gems from +list+.

  def remove_all(list)
    list.dup.each { |spec| uninstall_gem spec, list }
  end

  ##
  # spec:: the spec of the gem to be uninstalled
  # list:: the list of all such gems
  #
  # Warning: this method modifies the +list+ parameter.  Once it has
  # uninstalled a gem, it is removed from that list.

  def remove(spec, list)
    unless dependencies_ok? spec then
      raise Gem::DependencyRemovalException,
            "Uninstallation aborted due to dependent gem(s)"
    end

    unless path_ok? spec then
      e = Gem::GemNotInHomeException.new \
            "Gem is not installed in directory #{@gem_home}"
      e.spec = spec

      raise e
    end

    raise Gem::FilePermissionError, spec.installation_path unless
      File.writable?(spec.installation_path)

    FileUtils.rm_rf spec.full_gem_path

    original_platform_name = [
      spec.name, spec.version, spec.original_platform].join '-'

    spec_dir = File.join spec.installation_path, 'specifications'
    gemspec = File.join spec_dir, "#{spec.full_name}.gemspec"

    unless File.exist? gemspec then
      gemspec = File.join spec_dir, "#{original_platform_name}.gemspec"
    end

    FileUtils.rm_rf gemspec

    cache_dir = File.join spec.installation_path, 'cache'
    gem = File.join cache_dir, "#{spec.full_name}.gem"

    unless File.exist? gem then
      gem = File.join cache_dir, "#{original_platform_name}.gem"
    end

    FileUtils.rm_rf gem

    Gem::DocManager.new(spec).uninstall_doc

    say "Successfully uninstalled #{spec.full_name}"

    list.delete spec
  end

  def path_ok?(spec)
    full_path = File.join @gem_home, 'gems', spec.full_name
    original_path = File.join @gem_home, 'gems', spec.original_name

    full_path == spec.full_gem_path || original_path == spec.full_gem_path
  end

  def dependencies_ok?(spec)
    return true if @force_ignore

    deplist = Gem::DependencyList.from_source_index @source_index
    deplist.ok_to_remove?(spec.full_name) || ask_if_ok(spec)
  end

  def ask_if_ok(spec)
    msg = ['']
    msg << 'You have requested to uninstall the gem:'
    msg << "\t#{spec.full_name}"
    spec.dependent_gems.each do |gem,dep,satlist|
      msg <<
        ("#{gem.name}-#{gem.version} depends on " +
        "[#{dep.name} (#{dep.version_requirements})]")
    end
    msg << 'If you remove this gems, one or more dependencies will not be met.'
    msg << 'Continue with Uninstall?'
    return ask_yes_no(msg.join("\n"), true)
  end

end

