# See README.
#
 

VERSION_STRING = %{RDoc V1.0.1 - 20041108}


require 'rdoc/parsers/parse_rb.rb'
require 'rdoc/parsers/parse_c.rb'
require 'rdoc/parsers/parse_f95.rb'

require 'rdoc/parsers/parse_simple.rb'
require 'rdoc/options'

require 'rdoc/diagram'

require 'find'
require 'ftools'
require 'time'

# We put rdoc stuff in the RDoc module to avoid namespace
# clutter.
#
# ToDo: This isn't universally true.
#
# :include: README

module RDoc

  # Name of the dotfile that contains the description of files to be
  # processed in the current directory
  DOT_DOC_FILENAME = ".document"

  # Simple stats collector
  class Stats
    attr_accessor :num_files, :num_classes, :num_modules, :num_methods
    def initialize
      @num_files = @num_classes = @num_modules = @num_methods = 0
      @start = Time.now
    end
    def print
      puts "Files:   #@num_files"
      puts "Classes: #@num_classes"
      puts "Modules: #@num_modules"
      puts "Methods: #@num_methods"
      puts "Elapsed: " + sprintf("%0.3fs", Time.now - @start)
    end
  end


  # Exception thrown by any rdoc error. Only the #message part is
  # of use externally.

  class RDocError < Exception
  end

  # Encapsulate the production of rdoc documentation. Basically
  # you can use this as you would invoke rdoc from the command
  # line:
  #
  #    rdoc = RDoc::RDoc.new
  #    rdoc.document(args)
  #
  # where _args_ is an array of strings, each corresponding to
  # an argument you'd give rdoc on the command line. See rdoc/rdoc.rb 
  # for details.
  
  class RDoc

    ##
    # This is the list of output generators that we
    # support
    
    Generator = Struct.new(:file_name, :class_name, :key)
    
    GENERATORS = {}
    $:.collect {|d|
      File::expand_path(d)
    }.find_all {|d|
      File::directory?("#{d}/rdoc/generators")
    }.each {|dir|
      Dir::entries("#{dir}/rdoc/generators").each {|gen|
        next unless /(\w+)_generator.rb$/ =~ gen
        type = $1
        unless GENERATORS.has_key? type
          GENERATORS[type] = Generator.new("rdoc/generators/#{gen}",
                                           "#{type.upcase}Generator".intern,
                                           type)
        end
      }
    }                                                    

    #######
    private
    #######

    ##
    # Report an error message and exit
    
    def error(msg)
      raise RDocError.new(msg)
    end
    
    ##
    # Create an output dir if it doesn't exist. If it does
    # exist, but doesn't contain the flag file <tt>created.rid</tt>
    # then we refuse to use it, as we may clobber some
    # manually generated documentation
    
    def setup_output_dir(op_dir, force)
      flag_file = output_flag_file(op_dir)
      if File.exist?(op_dir)
        unless File.directory?(op_dir)
          error "'#{op_dir}' exists, and is not a directory" 
        end
        begin
          created = File.read(flag_file)
        rescue SystemCallError
          error "\nDirectory #{op_dir} already exists, but it looks like it\n" +
            "isn't an RDoc directory. Because RDoc doesn't want to risk\n" +
            "destroying any of your existing files, you'll need to\n" +
            "specify a different output directory name (using the\n" +
            "--op <dir> option).\n\n"
        else
          last = (Time.parse(created) unless force rescue nil)
        end
      else
        File.makedirs(op_dir)
      end
      last
    end

    # Update the flag file in an output directory.
    def update_output_dir(op_dir, time)
      File.open(output_flag_file(op_dir), "w") {|f| f.puts time.rfc2822 }
    end

    # Return the path name of the flag file in an output directory.
    def output_flag_file(op_dir)
      File.join(op_dir, "created.rid")
    end

    # The .document file contains a list of file and directory name
    # patterns, representing candidates for documentation. It may
    # also contain comments (starting with '#')
    def parse_dot_doc_file(in_dir, filename, options)
      # read and strip comments
      patterns = File.read(filename).gsub(/#.*/, '')

      result = []

      patterns.split.each do |patt|
        candidates = Dir.glob(File.join(in_dir, patt))
        result.concat(normalized_file_list(options,  candidates))
      end
      result
    end


    # Given a list of files and directories, create a list
    # of all the Ruby files they contain. 
    #
    # If +force_doc+ is true, we always add the given files.
    # If false, only add files that we guarantee we can parse
    # It is true when looking at files given on the command line,
    # false when recursing through subdirectories. 
    #
    # The effect of this is that if you want a file with a non-
    # standard extension parsed, you must name it explicity.
    #

    def normalized_file_list(options, relative_files, force_doc = false, exclude_pattern=nil)
      file_list = []

      relative_files.each do |rel_file_name|
        next if exclude_pattern && exclude_pattern =~ rel_file_name
        stat = File.stat(rel_file_name)
        case type = stat.ftype
        when "file"
          next if @last_created and stat.mtime < @last_created
          file_list << rel_file_name.sub(/^\.\//, '') if force_doc || ParserFactory.can_parse(rel_file_name)
        when "directory"
          next if rel_file_name == "CVS" || rel_file_name == ".svn"
          dot_doc = File.join(rel_file_name, DOT_DOC_FILENAME)
          if File.file?(dot_doc)
            file_list.concat(parse_dot_doc_file(rel_file_name, dot_doc, options))
          else
            file_list.concat(list_files_in_directory(rel_file_name, options))
          end
        else
          raise RDocError.new("I can't deal with a #{type} #{rel_file_name}")
        end
      end
      file_list
    end

    # Return a list of the files to be processed in
    # a directory. We know that this directory doesn't have
    # a .document file, so we're looking for real files. However
    # we may well contain subdirectories which must
    # be tested for .document files
    def list_files_in_directory(dir, options)
      normalized_file_list(options, Dir.glob(File.join(dir, "*")), false, options.exclude)
    end


    # Parse each file on the command line, recursively entering
    # directories

    def parse_files(options)
 
      file_info = []

      files = options.files
      files = ["."] if files.empty?

      file_list = normalized_file_list(options, files, true)

      file_list.each do |fn|
        $stderr.printf("\n%35s: ", File.basename(fn)) unless options.quiet
        
        content = File.open(fn, "r") {|f| f.read}

        top_level = TopLevel.new(fn)
        parser = ParserFactory.parser_for(top_level, fn, content, options, @stats)
        file_info << parser.scan
        @stats.num_files += 1
      end

      file_info
    end


    public

    ###################################################################
    #
    # Format up one or more files according to the given arguments.
    # For simplicity, _argv_ is an array of strings, equivalent to the
    # strings that would be passed on the command line. (This isn't a
    # coincidence, as we _do_ pass in ARGV when running
    # interactively). For a list of options, see rdoc/rdoc.rb. By
    # default, output will be stored in a directory called +doc+ below
    # the current directory, so make sure you're somewhere writable
    # before invoking.
    #
    # Throws: RDocError on error

    def document(argv)

      TopLevel::reset

      @stats = Stats.new

      options = Options.instance
      options.parse(argv, GENERATORS)

      @last_created = nil
      unless options.all_one_file
        @last_created = setup_output_dir(options.op_dir, options.force_update)
      end
      start_time = Time.now

      file_info = parse_files(options)

      if file_info.empty?
        $stderr.puts "\nNo newer files." unless options.quiet
      else
        gen = options.generator

        $stderr.puts "\nGenerating #{gen.key.upcase}..." unless options.quiet

        require gen.file_name

        gen_class = Generators.const_get(gen.class_name)
        gen = gen_class.for(options)

        pwd = Dir.pwd

        Dir.chdir(options.op_dir)  unless options.all_one_file

        begin
          Diagram.new(file_info, options).draw if options.diagram
          gen.generate(file_info)
          update_output_dir(".", start_time)
        ensure
          Dir.chdir(pwd)
        end
      end

      unless options.quiet
        puts
        @stats.print
      end
    end
  end
end

