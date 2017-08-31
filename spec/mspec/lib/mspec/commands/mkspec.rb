#!/usr/bin/env ruby

require 'rbconfig'
require 'mspec/version'
require 'mspec/utils/options'
require 'mspec/utils/name_map'
require 'mspec/helpers/fs'

class MkSpec
  attr_reader :config

  def initialize
    @config = {
      :constants => [],
      :requires  => [],
      :base      => "core",
      :version   => nil
    }
    @map = NameMap.new true
  end

  def options(argv=ARGV)
    options = MSpecOptions.new "mkspec [options]", 32

    options.on("-c", "--constant", "CONSTANT",
               "Class or Module to generate spec stubs for") do |name|
      config[:constants] << name
    end
    options.on("-b", "--base", "DIR",
               "Directory to generate specs into") do |directory|
      config[:base] = File.expand_path directory
    end
    options.on("-r", "--require", "LIBRARY",
               "A library to require") do |file|
      config[:requires] << file
    end
    options.on("-V", "--version-guard", "VERSION",
               "Specify version for ruby_version_is guards") do |version|
      config[:version] = version
    end
    options.version MSpec::VERSION
    options.help

    options.doc "\n How might this work in the real world?\n"
    options.doc "   1. To create spec stubs for every class or module in Object\n"
    options.doc "     $ mkspec\n"
    options.doc "   2. To create spec stubs for Fixnum\n"
    options.doc "     $ mkspec -c Fixnum\n"
    options.doc "   3. To create spec stubs for Complex in 'superspec/complex'\n"
    options.doc "     $ mkspec -c Complex -r complex -b superspec"
    options.doc ""

    options.parse argv
  end

  def create_directory(mod)
    subdir = @map.dir_name mod, config[:base]

    if File.exist? subdir
      unless File.directory? subdir
        puts "#{subdir} already exists and is not a directory."
        return nil
      end
    else
      mkdir_p subdir
    end

    subdir
  end

  def write_requires(dir, file)
    prefix = config[:base] + '/'
    raise dir unless dir.start_with? prefix
    sub = dir[prefix.size..-1]
    parents = '../' * (sub.split('/').length + 1)

    File.open(file, 'w') do |f|
      f.puts "require File.expand_path('../#{parents}spec_helper', __FILE__)"
      config[:requires].each do |lib|
        f.puts "require '#{lib}'"
      end
    end
  end

  def write_version(f)
    f.puts ""
    if version = config[:version]
      f.puts "ruby_version_is #{version} do"
      yield "  "
      f.puts "end"
    else
      yield ""
    end
  end

  def write_spec(file, meth, exists)
    if exists
      out = `#{ruby} #{MSPEC_HOME}/bin/mspec-run --dry-run --unguarded -fs -e '#{meth}' #{file}`
      return if out.include?(meth)
    end

    File.open file, 'a' do |f|
      write_version(f) do |indent|
        f.puts <<-EOS
#{indent}describe "#{meth}" do
#{indent}  it "needs to be reviewed for spec completeness"
#{indent}end
EOS
      end
    end

    puts file
  end

  def create_file(dir, mod, meth, name)
    file = File.join dir, @map.file_name(meth, mod)
    exists = File.exist? file

    write_requires dir, file unless exists
    write_spec file, name, exists
  end

  def run
    config[:requires].each { |lib| require lib }
    constants = config[:constants]
    constants = Object.constants if constants.empty?

    @map.map({}, constants).each do |mod, methods|
      name = mod.chop
      next unless dir = create_directory(name)

      methods.each { |method| create_file dir, name, method, mod + method }
    end
  end

  ##
  # Determine and return the path of the ruby executable.

  def ruby
    ruby = File.join(RbConfig::CONFIG['bindir'],
                     RbConfig::CONFIG['ruby_install_name'])

    ruby.gsub! File::SEPARATOR, File::ALT_SEPARATOR if File::ALT_SEPARATOR

    return ruby
  end

  def self.main
    ENV['MSPEC_RUNNER'] = '1'

    script = new
    script.options
    script.run
  end
end
