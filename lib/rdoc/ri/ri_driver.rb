require 'optparse'
require 'yaml'

require 'rdoc/ri'
require 'rdoc/ri/ri_paths'
require 'rdoc/ri/ri_formatter'
require 'rdoc/ri/ri_display'
require 'fileutils'
require 'rdoc/markup/simple_markup'
require 'rdoc/markup/simple_markup/to_flow'

class RDoc::RI::RiDriver
  
  def self.process_args(argv)
    options = {}
    options[:use_stdout] = !$stdout.tty?
    options[:width] = 72
    options[:formatter] = RI::TextFormatter.for 'plain'
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
        RI::Paths::SYSDIR,
        RI::Paths::SITEDIR,
        RI::Paths::HOMEDIR
      ]

      if RI::Paths::GEMDIRS then
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

The form '.' method matches either class or instance methods, while 
#method matches only instance and ::method matches only class methods.

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
             RI::TextFormatter.list.split(', '), # HACK
             "Format to use when displaying output:",
             "   #{RI::TextFormatter.list}",
             "Use 'bs' (backspace) with most pager",
             "programs. To use ANSI, either disable the",
             "pager or tell the pager to allow control",
             "characters.") do |value|
        options[:formatter] = RI::TextFormatter.for value
      end

      opt.separator nil

      if RI::Paths::GEMDIRS then
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

    options[:path] = RI::Paths.path(use_system, use_site, use_home, use_gems,
                                    *doc_dirs)
    options[:raw_path] = RI::Paths.raw_path(use_system, use_site, use_home,
                                            use_gems, *doc_dirs)

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

  def initialize(options)
    @names = options[:names]

    @class_cache_name = 'classes'
    @all_dirs = RI::Paths.path(true, true, true, true)
    @homepath = RI::Paths.raw_path(false, false, true, false).first
    @homepath = @homepath.sub(/\.rdoc/, '.ri')
    @sys_dirs = RI::Paths.raw_path(true, false, false, false)

    FileUtils.mkdir_p cache_file_path unless File.directory? cache_file_path

    @class_cache = nil

    @display = DefaultDisplay.new(options[:formatter], options[:width],
                                  options[:use_stdout])
  end

  def class_cache
    return @class_cache if @class_cache

    newest = map_dirs('created.rid', :all) do |f|
      File.mtime f if test ?f, f 
    end.max

    up_to_date = (File.exist?(class_cache_file_path) and
                  newest < File.mtime(class_cache_file_path))

    @class_cache = if up_to_date then
                     load_cache_for @class_cache_name
                   else
                     class_cache = {}

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
    File.join cache_file_path, klassname
  end

  def cache_file_path
    File.join @homepath, 'cache'
  end

  def display_class(name)
    klass = class_cache[name]
    @display.display_class_info klass, class_cache
  end

  def load_cache_for(klassname)
    path = cache_file_for klassname

    if File.exist? path and
       File.mtime(path) >= File.mtime(class_cache_file_path) then
      File.open path, 'rb' do |fp|
        Marshal.load fp
      end
    else
      class_cache = nil

      File.open class_cache_file_path, 'rb' do |fp|
        class_cache = Marshal.load fp
      end

      klass = class_cache[klassname]
      return nil unless klass

      method_files = klass["sources"]
      cache = {}

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
          cache[name] = method
        end
      end

      write_cache cache, path
    end
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
    YAML.load File.read(path).gsub(/ \!ruby\/(object|struct):RI.*/, '')
  end

  def run
    if @names.empty? then
      @display.list_known_classes select_classes
    else
      @names.each do |name|
        case name
        when /::|\#|\./ then
          if class_cache.key? name then
            display_class name
          else
            klass, meth = name.split(/::|\#|\./)
            cache = load_cache_for klass
            # HACK Does not support F.n
            abort "Nothing known about #{name}" unless cache
            method = cache[name.gsub(/\./, '#')]
            abort "Nothing known about #{name}" unless method
            @display.display_method_info method
          end
        else
          if class_cache.key? name then
            display_class name
          else
            @display.list_known_classes select_classes(/^#{name}/)
          end
        end
      end
    end
  end
  
  def select_classes(pattern = nil)
    classes = class_cache.keys.sort
    classes = classes.grep pattern if pattern
    classes
  end

  def write_cache(cache, path)
    File.open path, "wb" do |cache_file|
      Marshal.dump cache, cache_file
    end

    cache
  end

  # Couldn't find documentation in +path+, so tell the user what to do

  def report_missing_documentation(path)
    STDERR.puts "No ri documentation found in:"
    path.each do |d|
      STDERR.puts "     #{d}"
    end
    STDERR.puts "\nWas rdoc run to create documentation?\n\n"
    RDoc::usage("Installing Documentation")
  end

end

class Hash
  def method_missing method, *args
    self[method.to_s]
  end

  def merge_enums(other)
    other.each do |k,v|
      if self[k] then
        case v
        when Array then
          self[k] += v
        when Hash then
          self[k].merge! v
        else
          # do nothing
        end
      else
        self[k] = v
      end
    end
  end
end

