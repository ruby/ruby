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

  class Hash < ::Hash
    def self.convert(hash)
      hash = new.update hash

      hash.each do |key, value|
        hash[key] = case value
                    when ::Hash then
                      convert value
                    when Array then
                      value = value.map do |v|
                        ::Hash === v ? convert(v) : v
                      end
                      value
                    else
                      value
                    end
      end

      hash
    end

    def method_missing method, *args
      self[method.to_s]
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
  end

  class Error < RDoc::RI::Error; end

  class NotFoundError < Error
    def message
      "Nothing known about #{super}"
    end
  end

  attr_accessor :homepath # :nodoc:

  def self.process_args(argv)
    options = {}
    options[:use_stdout] = !$stdout.tty?
    options[:width] = 72
    options[:formatter] = RDoc::RI::Formatter.for 'plain'
    options[:list_classes] = false
    options[:list_names] = false

    # By default all paths are used.  If any of these are true, only those
    # directories are used.
    use_system = false
    use_site = false
    use_home = false
    use_gems = false
    doc_dirs = []

    opts = OptionParser.new do |opt|
      opt.program_name = File.basename $0
      opt.version = RDoc::VERSION
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

      opt.on("--classes", "-c",
             "Display the names of classes and modules we",
             "know about.") do |value|
        options[:list_classes] = value
      end

      opt.separator nil

      opt.on("--doc-dir=DIRNAME", "-d", Array,
             "List of directories to search for",
             "documentation. If not specified, we search",
             "the standard rdoc/ri directories. May be",
             "repeated.") do |value|
        value.each do |dir|
          unless File.directory? dir then
            raise OptionParser::InvalidArgument, "#{dir} is not a directory"
          end
        end

        doc_dirs.concat value
      end

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

      unless RDoc::RI::Paths::GEMDIRS.empty? then
        opt.on("--[no-]gems",
               "Include documentation from RubyGems.") do |value|
          use_gems = value
        end
      end

      opt.separator nil

      opt.on("--[no-]home",
             "Include documentation stored in ~/.rdoc.") do |value|
        use_home = value
      end

      opt.separator nil

      opt.on("--[no-]list-names", "-l",
             "List all the names known to RDoc, one per",
             "line.") do |value|
        options[:list_names] = value
      end

      opt.separator nil

      opt.on("--no-pager", "-T",
             "Send output directly to stdout.") do |value|
        options[:use_stdout] = !value
      end

      opt.separator nil

      opt.on("--[no-]site",
             "Include documentation from libraries",
             "installed in site_lib.") do |value|
        use_site = value
      end

      opt.separator nil

      opt.on("--[no-]system",
             "Include documentation from Ruby's standard",
             "library.") do |value|
        use_system = value
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

    options[:path] = RDoc::RI::Paths.path(use_system, use_site, use_home,
                                          use_gems, *doc_dirs)
    options[:raw_path] = RDoc::RI::Paths.raw_path(use_system, use_site,
                                                  use_home, use_gems, *doc_dirs)

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

  def initialize(options={})
    options[:formatter] ||= RDoc::RI::Formatter.for('plain')
    options[:use_stdout] ||= !$stdout.tty?
    options[:width] ||= 72
    @names = options[:names]

    @class_cache_name = 'classes'
    @all_dirs = RDoc::RI::Paths.path(true, true, true, true)
    @homepath = RDoc::RI::Paths.raw_path(false, false, true, false).first
    @homepath = @homepath.sub(/\.rdoc/, '.ri')
    @sys_dirs = RDoc::RI::Paths.raw_path(true, false, false, false)

    FileUtils.mkdir_p cache_file_path unless File.directory? cache_file_path

    @class_cache = nil

    @display = RDoc::RI::DefaultDisplay.new(options[:formatter],
                                            options[:width],
                                            options[:use_stdout])
  end

  def class_cache
    return @class_cache if @class_cache

    newest = map_dirs('created.rid', :all) do |f|
      File.mtime f if test ?f, f
    end.max

    up_to_date = (File.exist?(class_cache_file_path) and
                  newest and newest < File.mtime(class_cache_file_path))

    @class_cache = if up_to_date then
                     load_cache_for @class_cache_name
                   else
                     class_cache = RDoc::RI::Driver::Hash.new

                     classes = map_dirs('**/cdesc*.yaml', :sys) { |f| Dir[f] }
                     populate_class_cache class_cache, classes

                     classes = map_dirs('**/cdesc*.yaml') { |f| Dir[f] }
                     warn "Updating class cache with #{classes.size} classes..."

                     populate_class_cache class_cache, classes, true
                     write_cache class_cache, class_cache_file_path
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
    klass = RDoc::RI::Driver::Hash.convert klass
    @display.display_class_info klass, class_cache
  end

  def get_info_for(arg)
    @names = [arg]
    run
  end

  def load_cache_for(klassname)
    path = cache_file_for klassname

    cache = nil

    if File.exist? path and
       File.mtime(path) >= File.mtime(class_cache_file_path) then
      File.open path, 'rb' do |fp|
        cache = Marshal.load fp.read
      end
    else
      class_cache = nil

      File.open class_cache_file_path, 'rb' do |fp|
        class_cache = Marshal.load fp.read
      end

      klass = class_cache[klassname]
      return nil unless klass

      method_files = klass["sources"]
      cache = RDoc::RI::Driver::Hash.new

      sys_dir = @sys_dirs.first
      method_files.each do |f|
        system_file = f.index(sys_dir) == 0
        Dir[File.join(File.dirname(f), "*")].each do |yaml|
          next unless yaml =~ /yaml$/
          next if yaml =~ /cdesc-[^\/]+yaml$/
          method = read_yaml yaml
          name = method["full_name"]
          ext_path = f
          ext_path = "gem #{$1}" if f =~ %r%gems/[\d.]+/doc/([^/]+)%
          method["source_path"] = ext_path unless system_file
          cache[name] = RDoc::RI::Driver::Hash.convert method
        end
      end

      write_cache cache, path
    end

    RDoc::RI::Driver::Hash.convert cache
  end

  ##
  # Finds the method

  def lookup_method(name, klass)
    cache = load_cache_for klass
    raise NotFoundError, name unless cache

    method = cache[name.gsub('.', '#')]
    method = cache[name.gsub('.', '::')] unless method
    raise NotFoundError, name unless method

    method
  end

  def map_dirs(file_name, system=false)
    dirs = if system == :all then
             @all_dirs
           else
             if system then
               @sys_dirs
             else
               @all_dirs - @sys_dirs
             end
           end

    dirs.map { |dir| yield File.join(dir, file_name) }.flatten.compact
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

  def read_yaml(path)
    data = File.read path
    data = data.gsub(/ \!ruby\/(object|struct):(RDoc::RI|RI).*/, '')
    data = data.gsub(/ \!ruby\/(object|struct):SM::(\S+)/,
                     ' !ruby/\1:RDoc::Markup::\2')
    YAML.load data
  end

  def run
    if @names.empty? then
      @display.list_known_classes class_cache.keys.sort
    else
      @names.each do |name|
        case name
        when /::|\#|\./ then
          if class_cache.key? name then
            display_class name
          else
            meth = nil

            klass, meth = parse_name name

            method = lookup_method name, klass

            @display.display_method_info method
          end
        else
          if class_cache.key? name then
            display_class name
          else
            methods = select_methods(/^#{name}/)
            if methods.size == 0
              raise NotFoundError, name
            elsif methods.size == 1
              @display.display_method_info methods.first
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
    File.open path, "wb" do |cache_file|
      Marshal.dump cache, cache_file
    end

    cache
  end

end

