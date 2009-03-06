require 'optparse'
require 'yaml'

require 'rdoc/ri'
require 'rdoc/ri/paths'
require 'rdoc/ri/formatter'
require 'rdoc/ri/display'
require 'fileutils'
require 'rdoc/markup'
require 'rdoc/markup/to_flow'

class RDoc::RI::Driver

  #
  # This class offers both Hash and OpenStruct functionality.
  # We convert from the Core Hash to this before calling any of
  # the display methods, in order to give the display methods
  # a cleaner API for accessing the data.
  #
  class OpenStructHash < Hash
    #
    # This method converts from a Hash to an OpenStructHash.
    #
    def self.convert(object)
      case object
      when Hash then
        new_hash = new # Convert Hash -> OpenStructHash

        object.each do |key, value|
          new_hash[key] = convert(value)
        end

        new_hash
      when Array then
        object.map do |element|
          convert(element)
        end
      else
        object
      end
    end

    def merge_enums(other)
      other.each do |k, v|
        if self[k] then
          case v
          when Array then
            # HACK dunno
            if String === self[k] and self[k].empty? then
              self[k] = v
            else
              self[k] += v
            end
          when Hash then
            self[k].update v
          else
            # do nothing
          end
        else
          self[k] = v
        end
      end
    end

    def method_missing method, *args
      self[method.to_s]
    end
  end

  class Error < RDoc::RI::Error; end

  class NotFoundError < Error
    def message
      "Nothing known about #{super}"
    end
  end

  attr_accessor :homepath # :nodoc:

  def self.default_options
    options = {}
    options[:use_stdout] = !$stdout.tty?
    options[:width] = 72
    options[:formatter] = RDoc::RI::Formatter.for 'plain'
    options[:interactive] = false
    options[:use_cache] = true

    # By default all standard paths are used.
    options[:use_system] = true
    options[:use_site] = true
    options[:use_home] = true
    options[:use_gems] = true
    options[:extra_doc_dirs] = []

    return options
  end

  def self.process_args(argv)
    options = default_options

    opts = OptionParser.new do |opt|
      opt.program_name = File.basename $0
      opt.version = RDoc::VERSION
      opt.release = nil
      opt.summary_indent = ' ' * 4

      directories = [
        RDoc::RI::Paths::SYSDIR,
        RDoc::RI::Paths::SITEDIR,
        RDoc::RI::Paths::HOMEDIR
      ]

      if RDoc::RI::Paths::GEMDIRS then
        Gem.path.each do |dir|
          directories << "#{dir}/doc/*/ri"
        end
      end

      opt.banner = <<-EOT
Usage: #{opt.program_name} [options] [names...]

Where name can be:

  Class | Class::method | Class#method | Class.method | method

All class names may be abbreviated to their minimum unambiguous form. If a name
is ambiguous, all valid options will be listed.

The form '.' method matches either class or instance methods, while #method
matches only instance and ::method matches only class methods.

For example:

    #{opt.program_name} Fil
    #{opt.program_name} File
    #{opt.program_name} File.new
    #{opt.program_name} zip

Note that shell quoting may be required for method names containing
punctuation:

    #{opt.program_name} 'Array.[]'
    #{opt.program_name} compact\\!

By default ri searches for documentation in the following directories:

    #{directories.join "\n    "}

Specifying the --system, --site, --home, --gems or --doc-dir options will
limit ri to searching only the specified directories.

Options may also be set in the 'RI' environment variable.
      EOT

      opt.separator nil
      opt.separator "Options:"
      opt.separator nil

      opt.on("--fmt=FORMAT", "--format=FORMAT", "-f",
             RDoc::RI::Formatter::FORMATTERS.keys,
             "Format to use when displaying output:",
             "   #{RDoc::RI::Formatter.list}",
             "Use 'bs' (backspace) with most pager",
             "programs. To use ANSI, either disable the",
             "pager or tell the pager to allow control",
             "characters.") do |value|
        options[:formatter] = RDoc::RI::Formatter.for value
      end

      opt.separator nil

      opt.on("--doc-dir=DIRNAME", "-d", Array,
             "List of directories from which to source",
             "documentation in addition to the standard",
             "directories.  May be repeated.") do |value|
        value.each do |dir|
          unless File.directory? dir then
            raise OptionParser::InvalidArgument, "#{dir} is not a directory"
          end

          options[:extra_doc_dirs] << File.expand_path(dir)
        end
      end

      opt.separator nil

      opt.on("--[no-]use-cache",
             "Whether or not to use ri's cache.",
             "True by default.") do |value|
        options[:use_cache] = value
      end

      opt.separator nil

      opt.on("--no-standard-docs",
             "Do not include documentation from",
             "the Ruby standard library, site_lib,",
             "installed gems, or ~/.rdoc.",
             "Equivalent to specifying",
             "the options --no-system, --no-site, --no-gems,",
             "and --no-home") do
        options[:use_system] = false
        options[:use_site] = false
        options[:use_gems] = false
        options[:use_home] = false
      end

      opt.separator nil

      opt.on("--[no-]system",
             "Include documentation from Ruby's standard",
             "library.  Defaults to true.") do |value|
        options[:use_system] = value
      end

      opt.separator nil

      opt.on("--[no-]site",
             "Include documentation from libraries",
             "installed in site_lib.",
             "Defaults to true.") do |value|
        options[:use_site] = value
      end

      opt.separator nil

      opt.on("--[no-]gems",
             "Include documentation from RubyGems.",
             "Defaults to true.") do |value|
        options[:use_gems] = value
      end

      opt.separator nil

      opt.on("--[no-]home",
             "Include documentation stored in ~/.rdoc.",
             "Defaults to true.") do |value|
        options[:use_home] = value
      end

      opt.separator nil

      opt.on("--list-doc-dirs",
             "List the directories from which ri will",
             "source documentation on stdout and exit.") do
        options[:list_doc_dirs] = true
      end

      opt.separator nil

      opt.on("--no-pager", "-T",
             "Send output directly to stdout,",
             "rather than to a pager.") do
        options[:use_stdout] = true
      end

      opt.on("--interactive", "-i",
             "This makes ri go into interactive mode.",
             "When ri is in interactive mode it will",
             "allow the user to disambiguate lists of",
             "methods in case multiple methods match",
             "against a method search string.  It also",
             "will allow the user to enter in a method",
             "name (with auto-completion, if readline",
             "is supported) when viewing a class.") do
        options[:interactive] = true
      end

      opt.separator nil

      opt.on("--width=WIDTH", "-w", OptionParser::DecimalInteger,
             "Set the width of the output.") do |value|
        options[:width] = value
      end
    end

    argv = ENV['RI'].to_s.split.concat argv

    opts.parse! argv

    options[:names] = argv

    options[:formatter] ||= RDoc::RI::Formatter.for('plain')
    options[:use_stdout] ||= !$stdout.tty?
    options[:use_stdout] ||= options[:interactive]
    options[:width] ||= 72

    options

  rescue OptionParser::InvalidArgument, OptionParser::InvalidOption => e
    puts opts
    puts
    puts e
    exit 1
  end

  def self.run(argv = ARGV)
    options = process_args argv
    ri = new options
    ri.run
  end

  def initialize(initial_options={})
    options = self.class.default_options.update(initial_options)

    @names = options[:names]
    @class_cache_name = 'classes'

    @doc_dirs = RDoc::RI::Paths.path(options[:use_system],
                                     options[:use_site],
                                     options[:use_home],
                                     options[:use_gems],
                                     options[:extra_doc_dirs])

    @homepath = RDoc::RI::Paths.raw_path(false, false, true, false).first
    @homepath = @homepath.sub(/\.rdoc/, '.ri')
    @sys_dir = RDoc::RI::Paths.raw_path(true, false, false, false).first
    @list_doc_dirs = options[:list_doc_dirs]

    FileUtils.mkdir_p cache_file_path unless File.directory? cache_file_path
    @cache_doc_dirs_path = File.join cache_file_path, ".doc_dirs"

    @use_cache = options[:use_cache]
    @class_cache = nil

    @interactive = options[:interactive]
    @display = RDoc::RI::DefaultDisplay.new(options[:formatter],
                                            options[:width],
                                            options[:use_stdout])
  end

  def class_cache
    return @class_cache if @class_cache

    # Get the documentation directories used to make the cache in order to see
    # whether the cache is valid for the current ri instantiation.
    if(File.readable?(@cache_doc_dirs_path))
      cache_doc_dirs = IO.read(@cache_doc_dirs_path).split("\n")
    else
      cache_doc_dirs = []
    end

    newest = map_dirs('created.rid') do |f|
      File.mtime f if test ?f, f
    end.max

    # An up to date cache file must have been created more recently than
    # the last modification of any of the documentation directories.  It also
    # must have been created with the same documentation directories
    # as those from which ri currently is sourcing documentation.
    up_to_date = (File.exist?(class_cache_file_path) and
                  newest and newest < File.mtime(class_cache_file_path) and
                  (cache_doc_dirs == @doc_dirs))

    if up_to_date and @use_cache then
      open class_cache_file_path, 'rb' do |fp|
        begin
          @class_cache = Marshal.load fp.read
        rescue
          #
          # This shouldn't be necessary, since the up_to_date logic above
          # should force the cache to be recreated when a new version of
          # rdoc is installed.  This seems like a worthwhile enhancement
          # to ri's robustness, however.
          #
          $stderr.puts "Error reading the class cache; recreating the class cache!"
          @class_cache = create_class_cache
        end
      end
    else
      @class_cache = create_class_cache
    end

    @class_cache
  end

  def create_class_cache
    class_cache = OpenStructHash.new

    if(@use_cache)
      # Dump the documentation directories to a file in the cache, so that
      # we only will use the cache for future instantiations with identical
      # documentation directories.
      File.open @cache_doc_dirs_path, "wb" do |fp|
        fp << @doc_dirs.join("\n")
      end
    end

    classes = map_dirs('**/cdesc*.yaml') { |f| Dir[f] }
    warn "Updating class cache with #{classes.size} classes..."
    populate_class_cache class_cache, classes

    write_cache class_cache, class_cache_file_path

    class_cache
  end

  def populate_class_cache(class_cache, classes, extension = false)
    classes.each do |cdesc|
      desc = read_yaml cdesc
      klassname = desc["full_name"]

      unless class_cache.has_key? klassname then
        desc["display_name"] = "Class"
        desc["sources"] = [cdesc]
        desc["instance_method_extensions"] = []
        desc["class_method_extensions"] = []
        class_cache[klassname] = desc
      else
        klass = class_cache[klassname]

        if extension then
          desc["instance_method_extensions"] = desc.delete "instance_methods"
          desc["class_method_extensions"] = desc.delete "class_methods"
        end

        klass.merge_enums desc
        klass["sources"] << cdesc
      end
    end
  end

  def class_cache_file_path
    File.join cache_file_path, @class_cache_name
  end

  def cache_file_for(klassname)
    File.join cache_file_path, klassname.gsub(/:+/, "-")
  end

  def cache_file_path
    File.join @homepath, 'cache'
  end

  def display_class(name)
    klass = class_cache[name]
    @display.display_class_info klass
  end

  def display_method(method)
    @display.display_method_info method
  end

  def get_info_for(arg)
    @names = [arg]
    run
  end

  def load_cache_for(klassname)
    path = cache_file_for klassname

    cache = nil

    if File.exist? path and
       File.mtime(path) >= File.mtime(class_cache_file_path) and
       @use_cache then
      open path, 'rb' do |fp|
        begin
          cache = Marshal.load fp.read
        rescue
          #
          # The cache somehow is bad.  Recreate the cache.
          #
          $stderr.puts "Error reading the cache for #{klassname}; recreating the cache!"
          cache = create_cache_for klassname, path
        end
      end
    else
      cache = create_cache_for klassname, path
    end

    cache
  end

  def create_cache_for(klassname, path)
    klass = class_cache[klassname]
    return nil unless klass

    method_files = klass["sources"]
    cache = OpenStructHash.new

    method_files.each do |f|
      system_file = f.index(@sys_dir) == 0
      Dir[File.join(File.dirname(f), "*")].each do |yaml|
        next unless yaml =~ /yaml$/
        next if yaml =~ /cdesc-[^\/]+yaml$/

        method = read_yaml yaml

        if system_file then
          method["source_path"] = "Ruby #{RDoc::RI::Paths::VERSION}"
        else
          if(f =~ %r%gems/[\d.]+/doc/([^/]+)%) then
            ext_path = "gem #{$1}"
          else
            ext_path = f
          end

          method["source_path"] = ext_path
        end

        name = method["full_name"]
        cache[name] = method
      end
    end

    write_cache cache, path
  end

  ##
  # Finds the next ancestor of +orig_klass+ after +klass+.

  def lookup_ancestor(klass, orig_klass)
    # This is a bit hacky, but ri will go into an infinite
    # loop otherwise, since Object has an Object ancestor
    # for some reason.  Depending on the documentation state, I've seen
    # Kernel as an ancestor of Object and not as an ancestor of Object.
    if ((orig_klass == "Object") &&
        ((klass == "Kernel") || (klass == "Object")))
      return nil
    end

    cache = class_cache[orig_klass]

    return nil unless cache

    ancestors = [orig_klass]
    ancestors.push(*cache.includes.map { |inc| inc['name'] })
    ancestors << cache.superclass

    ancestor_index = ancestors.index(klass)

    if ancestor_index
      ancestor = ancestors[ancestors.index(klass) + 1]
      return ancestor if ancestor
    end

    lookup_ancestor klass, cache.superclass
  end

  ##
  # Finds the method

  def lookup_method(name, klass)
    cache = load_cache_for klass
    return nil unless cache

    method = cache[name.gsub('.', '#')]
    method = cache[name.gsub('.', '::')] unless method
    method
  end

  def map_dirs(file_name)
    @doc_dirs.map { |dir| yield File.join(dir, file_name) }.flatten.compact
  end

  ##
  # Extract the class and method name parts from +name+ like Foo::Bar#baz

  def parse_name(name)
    parts = name.split(/(::|\#|\.)/)

    if parts[-2] != '::' or parts.last !~ /^[A-Z]/ then
      meth = parts.pop
      parts.pop
    end

    klass = parts.join

    [klass, meth]
  end

  def read_yaml(path)
    data = File.read path

    # Necessary to be backward-compatible with documentation generated
    # by earliar RDoc versions.
    data = data.gsub(/ \!ruby\/(object|struct):(RDoc::RI|RI).*/, '')
    data = data.gsub(/ \!ruby\/(object|struct):SM::(\S+)/,
                     ' !ruby/\1:RDoc::Markup::\2')
    OpenStructHash.convert(YAML.load(data))
  end

  def run
    if(@list_doc_dirs)
      puts @doc_dirs.join("\n")
    elsif @names.empty? then
      @display.list_known_classes class_cache.keys.sort
    else
      @names.each do |name|
        if class_cache.key? name then
          method_map = display_class name
          if(@interactive)
            method_name = @display.get_class_method_choice(method_map)

            if(method_name != nil)
              method = lookup_method "#{name}#{method_name}", name
              display_method method
            end
          end
        elsif name =~ /::|\#|\./ then
          klass, = parse_name name

          orig_klass = klass
          orig_name = name

          loop do
            method = lookup_method name, klass

            break method if method

            ancestor = lookup_ancestor klass, orig_klass

            break unless ancestor

            name = name.sub klass, ancestor
            klass = ancestor
          end

          raise NotFoundError, orig_name unless method

          display_method method
        else
          methods = select_methods(/#{name}/)

          if methods.size == 0
            raise NotFoundError, name
          elsif methods.size == 1
            display_method methods[0]
          else
            if(@interactive)
              @display.display_method_list_choice methods
            else
              @display.display_method_list methods
            end
          end
        end
      end
    end
  rescue NotFoundError => e
    abort e.message
  end

  def select_methods(pattern)
    methods = []
    class_cache.keys.sort.each do |klass|
      class_cache[klass]["instance_methods"].map{|h|h["name"]}.grep(pattern) do |name|
        method = load_cache_for(klass)[klass+'#'+name]
        methods << method if method
      end
      class_cache[klass]["class_methods"].map{|h|h["name"]}.grep(pattern) do |name|
        method = load_cache_for(klass)[klass+'::'+name]
        methods << method if method
      end
    end
    methods
  end

  def write_cache(cache, path)
    if(@use_cache)
      File.open path, "wb" do |cache_file|
        Marshal.dump cache, cache_file
      end
    end

    cache
  end

end
