require 'rubygems/command'
require 'rubygems/gem_path_searcher'

class Gem::Commands::WhichCommand < Gem::Command

  EXT = %w[.rb .rbw .so .dll] # HACK

  def initialize
    super 'which', 'Find the location of a library',
          :search_gems_first => false, :show_all => false

    add_option '-a', '--[no-]all', 'show all matching files' do |show_all, options|
      options[:show_all] = show_all
    end

    add_option '-g', '--[no-]gems-first',
               'search gems before non-gems' do |gems_first, options|
      options[:search_gems_first] = gems_first
    end
  end

  def arguments # :nodoc:
    "FILE          name of file to find"
  end

  def defaults_str # :nodoc:
    "--no-gems-first --no-all"
  end

  def usage # :nodoc:
    "#{program_name} FILE [FILE ...]"
  end

  def execute
    searcher = Gem::GemPathSearcher.new

    options[:args].each do |arg|
      dirs = $LOAD_PATH
      spec = searcher.find arg

      if spec then
        if options[:search_gems_first] then
          dirs = gem_paths(spec) + $LOAD_PATH
        else
          dirs = $LOAD_PATH + gem_paths(spec)
        end

        say "(checking gem #{spec.full_name} for #{arg})" if
          Gem.configuration.verbose
      end

      paths = find_paths arg, dirs

      if paths.empty? then
        say "Can't find #{arg}"
      else
        say paths
      end
    end
  end

  def find_paths(package_name, dirs)
    result = []

    dirs.each do |dir|
      EXT.each do |ext|
        full_path = File.join dir, "#{package_name}#{ext}"
        if File.exist? full_path then
          result << full_path
          return result unless options[:show_all]
        end
      end
    end

    result
  end

  def gem_paths(spec)
    spec.require_paths.collect { |d| File.join spec.full_gem_path, d }
  end

  def usage # :nodoc:
    "#{program_name} FILE [...]"
  end

end
