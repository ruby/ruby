######################################################################
# This file is imported from the rubygems project.
# DO NOT make modifications in this repo. They _will_ be reverted!
# File a patch instead and assign it to Ryan Davis or Eric Hodel.
######################################################################

require 'rubygems'
require 'rubygems/format'

begin
  gem 'builder'
  require 'builder/xchar'
rescue LoadError
end

##
# Top level class for building the gem repository index.

class Gem::Indexer

  include Gem::UserInteraction

  ##
  # Build indexes for RubyGems older than 1.2.0 when true

  attr_accessor :build_legacy

  ##
  # Build indexes for RubyGems 1.2.0 and newer when true

  attr_accessor :build_modern

  ##
  # Index install location

  attr_reader :dest_directory

  ##
  # Specs index install location

  attr_reader :dest_specs_index

  ##
  # Latest specs index install location

  attr_reader :dest_latest_specs_index

  ##
  # Prerelease specs index install location

  attr_reader :dest_prerelease_specs_index

  ##
  # Index build directory

  attr_reader :directory

  ##
  # Create an indexer that will index the gems in +directory+.

  def initialize(directory, options = {})
    require 'fileutils'
    require 'tmpdir'
    require 'zlib'

    unless defined?(Builder::XChar) then
      raise "Gem::Indexer requires that the XML Builder library be installed:" \
           "\n\tgem install builder"
    end

    options = { :build_legacy => true, :build_modern => true }.merge options

    @build_legacy = options[:build_legacy]
    @build_modern = options[:build_modern]

    @rss_title = options[:rss_title]
    @rss_host = options[:rss_host]
    @rss_gems_host = options[:rss_gems_host]

    @dest_directory = directory
    @directory = File.join Dir.tmpdir, "gem_generate_index_#{$$}"

    marshal_name = "Marshal.#{Gem.marshal_version}"

    @master_index = File.join @directory, 'yaml'
    @marshal_index = File.join @directory, marshal_name

    @quick_dir = File.join @directory, 'quick'

    @quick_marshal_dir = File.join @quick_dir, marshal_name

    @quick_index = File.join @quick_dir, 'index'
    @latest_index = File.join @quick_dir, 'latest_index'

    @specs_index = File.join @directory, "specs.#{Gem.marshal_version}"
    @latest_specs_index = File.join @directory,
                                    "latest_specs.#{Gem.marshal_version}"
    @prerelease_specs_index = File.join(@directory,
                                        "prerelease_specs.#{Gem.marshal_version}")

    @dest_specs_index = File.join @dest_directory,
                                  "specs.#{Gem.marshal_version}"
    @dest_latest_specs_index = File.join @dest_directory,
                                         "latest_specs.#{Gem.marshal_version}"
    @dest_prerelease_specs_index = File.join @dest_directory,
                                            "prerelease_specs.#{Gem.marshal_version}"

    @rss_index = File.join @directory, 'index.rss'

    @files = []
  end

  ##
  # Abbreviate the spec for downloading.  Abbreviated specs are only used for
  # searching, downloading and related activities and do not need deployment
  # specific information (e.g. list of files).  So we abbreviate the spec,
  # making it much smaller for quicker downloads.

  def abbreviate(spec)
    spec.files = []
    spec.test_files = []
    spec.rdoc_options = []
    spec.extra_rdoc_files = []
    spec.cert_chain = []
    spec
  end

  ##
  # Build various indicies

  def build_indicies(index)
    # Marshal gemspecs are used by both modern and legacy RubyGems
    build_marshal_gemspecs index
    build_legacy_indicies index if @build_legacy
    build_modern_indicies index if @build_modern
    build_rss index

    compress_indicies
  end

  ##
  # Builds indicies for RubyGems older than 1.2.x

  def build_legacy_indicies(index)
    say "Generating Marshal master index"

    Gem.time 'Generated Marshal master index' do
      open @marshal_index, 'wb' do |io|
        io.write index.dump
      end
    end

    @files << @marshal_index
    @files << "#{@marshal_index}.Z"
  end

  ##
  # Builds Marshal quick index gemspecs.

  def build_marshal_gemspecs(index)
    progress = ui.progress_reporter index.size,
                                    "Generating Marshal quick index gemspecs for #{index.size} gems",
                                    "Complete"

    files = []

    Gem.time 'Generated Marshal quick index gemspecs' do
      index.gems.each do |original_name, spec|
        spec_file_name = "#{original_name}.gemspec.rz"
        marshal_name = File.join @quick_marshal_dir, spec_file_name

        marshal_zipped = Gem.deflate Marshal.dump(spec)
        open marshal_name, 'wb' do |io| io.write marshal_zipped end

        files << marshal_name

        progress.updated original_name
      end

      progress.done
    end

    @files << @quick_marshal_dir

    files
  end

  ##
  # Build a single index for RubyGems 1.2 and newer

  def build_modern_index(index, file, name)
    say "Generating #{name} index"

    Gem.time "Generated #{name} index" do
      open(file, 'wb') do |io|
        specs = index.map do |*spec|
          # We have to splat here because latest_specs is an array,
          # while the others are hashes. See the TODO in source_index.rb
          spec = spec.flatten.last
          platform = spec.original_platform

          # win32-api-1.0.4-x86-mswin32-60
          unless String === platform then
            alert_warning "Skipping invalid platform in gem: #{spec.full_name}"
            next
          end

          platform = Gem::Platform::RUBY if platform.nil? or platform.empty?
          [spec.name, spec.version, platform]
        end

        specs = compact_specs(specs)
        Marshal.dump(specs, io)
      end
    end
  end

  ##
  # Builds indicies for RubyGems 1.2 and newer. Handles full, latest, prerelease

  def build_modern_indicies(index)
    build_modern_index(index.released_specs.sort, @specs_index, 'specs')
    build_modern_index(index.latest_specs.sort,
                       @latest_specs_index,
                       'latest specs')
    build_modern_index(index.prerelease_specs.sort,
                       @prerelease_specs_index,
                       'prerelease specs')

    @files += [@specs_index,
               "#{@specs_index}.gz",
               @latest_specs_index,
               "#{@latest_specs_index}.gz",
               @prerelease_specs_index,
               "#{@prerelease_specs_index}.gz"]
  end

  ##
  # Builds an RSS feed for past two days gem releases according to the gem's
  # date.

  def build_rss(index)
    if @rss_host.nil? or @rss_gems_host.nil? then
      if Gem.configuration.really_verbose then
        alert_warning "no --rss-host or --rss-gems-host, RSS generation disabled"
      end
      return
    end

    require 'cgi'
    require 'rubygems/text'

    extend Gem::Text

    Gem.time 'Generated rss' do
      open @rss_index, 'wb' do |io|
        rss_host = CGI.escapeHTML @rss_host
        rss_title = CGI.escapeHTML(@rss_title || 'gems')

        io.puts <<-HEADER
<?xml version="1.0"?>
<rss version="2.0">
  <channel>
    <title>#{rss_title}</title>
    <link>http://#{rss_host}</link>
    <description>Recently released gems from http://#{rss_host}</description>
    <generator>RubyGems v#{Gem::VERSION}</generator>
    <docs>http://cyber.law.harvard.edu/rss/rss.html</docs>
        HEADER

        today = Gem::Specification::TODAY
        yesterday = today - 86400

        index = index.select do |_, spec|
          spec_date = spec.date

          case spec_date
          when Date
            Time.parse(spec_date.to_s) >= yesterday
          when Time
            spec_date >= yesterday
          end
        end

        index = index.select do |_, spec|
          spec_date = spec.date

          case spec_date
          when Date
            Time.parse(spec_date.to_s) <= today
          when Time
            spec_date <= today
          end
        end

        index.sort_by { |_, spec| [-spec.date.to_i, spec] }.each do |_, spec|
          gem_path = CGI.escapeHTML "http://#{@rss_gems_host}/gems/#{spec.file_name}"
          size = File.stat(spec.loaded_from).size rescue next

          description = spec.description || spec.summary || ''
          authors = Array spec.authors
          emails = Array spec.email
          authors = emails.zip(authors).map do |email, author|
            email += " (#{author})" if author and not author.empty?
          end.join ', '

          description = description.split(/\n\n+/).map do |chunk|
            format_text chunk, 78
          end

          description = description.join "\n\n"

          item = ''

          item << <<-ITEM
    <item>
      <title>#{CGI.escapeHTML spec.full_name}</title>
      <description>
&lt;pre&gt;#{CGI.escapeHTML description.chomp}&lt;/pre&gt;
      </description>
      <author>#{CGI.escapeHTML authors}</author>
      <guid>#{CGI.escapeHTML spec.full_name}</guid>
      <enclosure url=\"#{gem_path}\"
                 length=\"#{size}\" type=\"application/octet-stream\" />
      <pubDate>#{spec.date.rfc2822}</pubDate>
          ITEM

          item << <<-ITEM if spec.homepage
      <link>#{CGI.escapeHTML spec.homepage}</link>
          ITEM

          item << <<-ITEM
    </item>
          ITEM

          io.puts item
        end

        io.puts <<-FOOTER
  </channel>
</rss>
        FOOTER
      end
    end

    @files << @rss_index
  end

  ##
  # Collect specifications from .gem files from the gem directory.

  def collect_specs(gems = gem_file_list)
    index = Gem::SourceIndex.new

    progress = ui.progress_reporter gems.size,
                                    "Loading #{gems.size} gems from #{@dest_directory}",
                                    "Loaded all gems"

    Gem.time 'loaded' do
      gems.each do |gemfile|
        if File.size(gemfile.to_s) == 0 then
          alert_warning "Skipping zero-length gem: #{gemfile}"
          next
        end

        begin
          spec = Gem::Format.from_file_by_path(gemfile).spec
          spec.loaded_from = gemfile

          unless gemfile =~ /\/#{Regexp.escape spec.original_name}.*\.gem\z/i then
            expected_name = spec.full_name
            expected_name << " (#{spec.original_name})" if
              spec.original_name != spec.full_name
            alert_warning "Skipping misnamed gem: #{gemfile} should be named #{expected_name}"
            next
          end

          abbreviate spec
          sanitize spec

          index.add_spec spec, spec.original_name

          progress.updated spec.original_name

        rescue SignalException => e
          alert_error "Received signal, exiting"
          raise
        rescue Exception => e
          alert_error "Unable to process #{gemfile}\n#{e.message} (#{e.class})\n\t#{e.backtrace.join "\n\t"}"
        end
      end

      progress.done
    end

    index
  end

  ##
  # Compresses indicies on disk
  #--
  # All future files should be compressed using gzip, not deflate

  def compress_indicies
    say "Compressing indicies"

    Gem.time 'Compressed indicies' do
      if @build_legacy then
        compress @marshal_index, 'Z'
        paranoid @marshal_index, 'Z'
      end

      if @build_modern then
        gzip @specs_index
        gzip @latest_specs_index
        gzip @prerelease_specs_index
      end
    end
  end

  ##
  # Compacts Marshal output for the specs index data source by using identical
  # objects as much as possible.

  def compact_specs(specs)
    names = {}
    versions = {}
    platforms = {}

    specs.map do |(name, version, platform)|
      names[name] = name unless names.include? name
      versions[version] = version unless versions.include? version
      platforms[platform] = platform unless platforms.include? platform

      [names[name], versions[version], platforms[platform]]
    end
  end

  ##
  # Compress +filename+ with +extension+.

  def compress(filename, extension)
    data = Gem.read_binary filename

    zipped = Gem.deflate data

    open "#{filename}.#{extension}", 'wb' do |io|
      io.write zipped
    end
  end

  ##
  # List of gem file names to index.

  def gem_file_list
    Dir.glob(File.join(@dest_directory, "gems", "*.gem"))
  end

  ##
  # Builds and installs indicies.

  def generate_index
    make_temp_directories
    index = collect_specs
    build_indicies index
    install_indicies
  rescue SignalException
  ensure
    FileUtils.rm_rf @directory
  end

  ##
  # Zlib::GzipWriter wrapper that gzips +filename+ on disk.

  def gzip(filename)
    Zlib::GzipWriter.open "#{filename}.gz" do |io|
      io.write Gem.read_binary(filename)
    end
  end

  ##
  # Install generated indicies into the destination directory.

  def install_indicies
    verbose = Gem.configuration.really_verbose

    say "Moving index into production dir #{@dest_directory}" if verbose

    files = @files.dup
    files.delete @quick_marshal_dir if files.include? @quick_dir

    if files.include? @quick_marshal_dir and
       not files.include? @quick_dir then
      files.delete @quick_marshal_dir
      quick_marshal_dir = @quick_marshal_dir.sub @directory, ''

      dst_name = File.join @dest_directory, quick_marshal_dir

      FileUtils.mkdir_p File.dirname(dst_name), :verbose => verbose
      FileUtils.rm_rf dst_name, :verbose => verbose
      FileUtils.mv @quick_marshal_dir, dst_name, :verbose => verbose,
                   :force => true
    end

    files = files.map do |path|
      path.sub @directory, ''
    end

    files.each do |file|
      src_name = File.join @directory, file
      dst_name = File.join @dest_directory, file

      FileUtils.rm_rf dst_name, :verbose => verbose
      FileUtils.mv src_name, @dest_directory, :verbose => verbose,
                   :force => true
    end
  end

  ##
  # Make directories for index generation

  def make_temp_directories
    FileUtils.rm_rf @directory
    FileUtils.mkdir_p @directory, :mode => 0700
    FileUtils.mkdir_p @quick_marshal_dir
  end

  ##
  # Ensure +path+ and path with +extension+ are identical.

  def paranoid(path, extension)
    data = Gem.read_binary path
    compressed_data = Gem.read_binary "#{path}.#{extension}"

    unless data == Gem.inflate(compressed_data) then
      raise "Compressed file #{compressed_path} does not match uncompressed file #{path}"
    end
  end

  ##
  # Sanitize the descriptive fields in the spec.  Sometimes non-ASCII
  # characters will garble the site index.  Non-ASCII characters will
  # be replaced by their XML entity equivalent.

  def sanitize(spec)
    spec.summary = sanitize_string(spec.summary)
    spec.description = sanitize_string(spec.description)
    spec.post_install_message = sanitize_string(spec.post_install_message)
    spec.authors = spec.authors.collect { |a| sanitize_string(a) }

    spec
  end

  ##
  # Sanitize a single string.

  def sanitize_string(string)
    return string unless string

    # HACK the #to_s is in here because RSpec has an Array of Arrays of
    # Strings for authors.  Need a way to disallow bad values on gemspec
    # generation.  (Probably won't happen.)
    string = string.to_s

    begin
      Builder::XChar.encode string
    rescue NameError, NoMethodError
      string.to_xs
    end
  end

  ##
  # Perform an in-place update of the repository from newly added gems.  Only
  # works for modern indicies, and sets #build_legacy to false when run.

  def update_index
    @build_legacy = false

    make_temp_directories

    specs_mtime = File.stat(@dest_specs_index).mtime
    newest_mtime = Time.at 0

    updated_gems = gem_file_list.select do |gem|
      gem_mtime = File.stat(gem).mtime
      newest_mtime = gem_mtime if gem_mtime > newest_mtime
      gem_mtime >= specs_mtime
    end

    if updated_gems.empty? then
      say 'No new gems'
      terminate_interaction 0
    end

    index = collect_specs updated_gems

    files = build_marshal_gemspecs index

    Gem.time 'Updated indexes' do
      update_specs_index index.released_gems, @dest_specs_index, @specs_index
      update_specs_index index.released_gems, @dest_latest_specs_index, @latest_specs_index
      update_specs_index(index.prerelease_gems, @dest_prerelease_specs_index,
                         @prerelease_specs_index)
    end

    compress_indicies

    verbose = Gem.configuration.really_verbose

    say "Updating production dir #{@dest_directory}" if verbose

    files << @specs_index
    files << "#{@specs_index}.gz"
    files << @latest_specs_index
    files << "#{@latest_specs_index}.gz"
    files << @prerelease_specs_index
    files << "#{@prerelease_specs_index}.gz"

    files = files.map do |path|
      path.sub @directory, ''
    end

    files.each do |file|
      src_name = File.join @directory, file
      dst_name = File.join @dest_directory, File.dirname(file)

      FileUtils.mv src_name, dst_name, :verbose => verbose,
                   :force => true

      File.utime newest_mtime, newest_mtime, dst_name
    end
  end

  ##
  # Combines specs in +index+ and +source+ then writes out a new copy to
  # +dest+.  For a latest index, does not ensure the new file is minimal.

  def update_specs_index(index, source, dest)
    specs_index = Marshal.load Gem.read_binary(source)

    index.each do |_, spec|
      platform = spec.original_platform
      platform = Gem::Platform::RUBY if platform.nil? or platform.empty?
      specs_index << [spec.name, spec.version, platform]
    end

    specs_index = compact_specs specs_index.uniq.sort

    open dest, 'wb' do |io|
      Marshal.dump specs_index, io
    end
  end

end

