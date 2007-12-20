require 'fileutils'
require 'tmpdir'

require 'rubygems'
require 'rubygems/format'

begin
  require 'builder/xchar'
rescue LoadError
end

##
# Top level class for building the gem repository index.
class Gem::Indexer

  include Gem::UserInteraction

  ##
  # Index install location

  attr_reader :dest_directory

  ##
  # Index build directory

  attr_reader :directory

  # Create an indexer that will index the gems in +directory+.
  def initialize(directory)
    unless ''.respond_to? :to_xs then
      fail "Gem::Indexer requires that the XML Builder library be installed:" \
           "\n\tgem install builder"
    end

    @dest_directory = directory
    @directory = File.join Dir.tmpdir, "gem_generate_index_#{$$}"

    marshal_name = "Marshal.#{Gem.marshal_version}"

    @master_index = Gem::Indexer::MasterIndexBuilder.new "yaml", @directory
    @marshal_index = Gem::Indexer::MarshalIndexBuilder.new marshal_name, @directory
    @quick_index = Gem::Indexer::QuickIndexBuilder.new "index", @directory
  end

  # Build the index.
  def build_index
    @master_index.build do
      @quick_index.build do
        @marshal_index.build do
          progress = ui.progress_reporter gem_file_list.size,
                                          "Generating index for #{gem_file_list.size} gems in #{@dest_directory}",
                                          "Loaded all gems"

          gem_file_list.each do |gemfile|
            if File.size(gemfile.to_s) == 0 then
              alert_warning "Skipping zero-length gem: #{gemfile}"
              next
            end

            begin
              spec = Gem::Format.from_file_by_path(gemfile).spec

              unless gemfile =~ /\/#{Regexp.escape spec.original_name}.*\.gem\z/i then
                alert_warning "Skipping misnamed gem: #{gemfile} => #{spec.full_name} (#{spec.original_name})"
                next
              end

              abbreviate spec
              sanitize spec

              @master_index.add spec
              @quick_index.add spec
              @marshal_index.add spec

              progress.updated spec.original_name

            rescue SignalException => e
              alert_error "Recieved signal, exiting"
              raise
            rescue Exception => e
              alert_error "Unable to process #{gemfile}\n#{e.message} (#{e.class})\n\t#{e.backtrace.join "\n\t"}"
            end
          end

          progress.done

          say "Generating master indexes (this may take a while)"
        end
      end
    end
  end

  def install_index
    verbose = Gem.configuration.really_verbose

    say "Moving index into production dir #{@dest_directory}" if verbose

    files = @master_index.files + @quick_index.files + @marshal_index.files

    files.each do |file|
      relative_name = file[/\A#{Regexp.escape @directory}.(.*)/, 1]
      dest_name = File.join @dest_directory, relative_name

      FileUtils.rm_rf dest_name, :verbose => verbose
      FileUtils.mv file, @dest_directory, :verbose => verbose
    end
  end

  def generate_index
    FileUtils.rm_rf @directory
    FileUtils.mkdir_p @directory, :mode => 0700

    build_index
    install_index
  rescue SignalException
  ensure
    FileUtils.rm_rf @directory
  end

  # List of gem file names to index.
  def gem_file_list
    Dir.glob(File.join(@dest_directory, "gems", "*.gem"))
  end

  # Abbreviate the spec for downloading.  Abbreviated specs are only
  # used for searching, downloading and related activities and do not
  # need deployment specific information (e.g. list of files).  So we
  # abbreviate the spec, making it much smaller for quicker downloads.
  def abbreviate(spec)
    spec.files = []
    spec.test_files = []
    spec.rdoc_options = []
    spec.extra_rdoc_files = []
    spec.cert_chain = []
    spec
  end

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

  # Sanitize a single string.
  def sanitize_string(string)
    # HACK the #to_s is in here because RSpec has an Array of Arrays of
    # Strings for authors.  Need a way to disallow bad values on gempsec
    # generation.  (Probably won't happen.)
    string ? string.to_s.to_xs : string
  end

end

require 'rubygems/indexer/abstract_index_builder'
require 'rubygems/indexer/master_index_builder'
require 'rubygems/indexer/quick_index_builder'
require 'rubygems/indexer/marshal_index_builder'

