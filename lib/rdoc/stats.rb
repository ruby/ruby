require 'rdoc'

##
# RDoc stats collector

class RDoc::Stats

  attr_reader :nodoc_constants
  attr_reader :nodoc_methods

  attr_reader :num_constants
  attr_reader :num_files
  attr_reader :num_methods

  attr_reader :total_files

  def initialize(total_files, verbosity = 1)
    @nodoc_constants = 0
    @nodoc_methods   = 0

    @num_constants = 0
    @num_files     = 0
    @num_methods   = 0

    @total_files = total_files

    @start = Time.now

    @display = case verbosity
               when 0 then Quiet.new   total_files
               when 1 then Normal.new  total_files
               else        Verbose.new total_files
               end
  end

  def begin_adding
    @display.begin_adding
  end

  def add_alias(as)
    @display.print_alias as
    @num_methods += 1
    @nodoc_methods += 1 if as.document_self and as.comment.empty?
  end

  def add_class(klass)
    @display.print_class klass
  end

  def add_constant(constant)
    @display.print_constant constant
    @num_constants += 1
    @nodoc_constants += 1 if constant.document_self and constant.comment.empty?
  end

  def add_file(file)
    @display.print_file @num_files, file
    @num_files += 1
  end

  def add_method(method)
    @display.print_method method
    @num_methods += 1
    @nodoc_methods += 1 if method.document_self and method.comment.empty?
  end

  def add_module(mod)
    @display.print_module mod
  end

  def done_adding
    @display.done_adding
  end

  def print
    classes = RDoc::TopLevel.classes
    num_classes   = classes.length
    nodoc_classes = classes.select do |klass|
      klass.document_self and klass.comment.empty?
    end.length

    modules = RDoc::TopLevel.modules
    num_modules = modules.length
    nodoc_modules = modules.select do |mod|
      mod.document_self and mod.comment.empty?
    end.length

    items = num_classes + @num_constants + num_modules + @num_methods
    doc_items = items -
      nodoc_classes - @nodoc_constants - nodoc_modules - @nodoc_methods

    percent_doc = doc_items.to_f / items * 100

    puts "Files:     %5d" % @num_files
    puts "Classes:   %5d (%5d undocumented)" % [num_classes, nodoc_classes]
    puts "Constants: %5d (%5d undocumented)" %
      [@num_constants, @nodoc_constants]
    puts "Modules:   %5d (%5d undocumented)" % [num_modules, nodoc_modules]
    puts "Methods:   %5d (%5d undocumented)" % [@num_methods, @nodoc_methods]
    puts "%6.2f%% documented" % percent_doc
    puts
    puts "Elapsed: %0.1fs" % (Time.now - @start)
  end

  ##
  # Stats printer that prints nothing

  class Quiet

    def initialize total_files
      @total_files = total_files
    end

    ##
    # Prints a message at the beginning of parsing

    def begin_adding(*) end

    ##
    # Prints when an alias is added

    def print_alias(*) end

    ##
    # Prints when a class is added

    def print_class(*) end

    ##
    # Prints when a constant is added

    def print_constant(*) end

    ##
    # Prints when a file is added

    def print_file(*) end

    ##
    # Prints when a method is added

    def print_method(*) end

    ##
    # Prints when a module is added

    def print_module(*) end

    ##
    # Prints when RDoc is done

    def done_adding(*) end

  end

  ##
  # Stats printer that prints just the files being documented with a progress
  # bar

  class Normal < Quiet

    def begin_adding # :nodoc:
      puts "Parsing sources..."
    end

    ##
    # Prints a file with a progress bar

    def print_file(files_so_far, filename)
      progress_bar = sprintf("%3d%% [%2d/%2d]  ",
                             100 * (files_so_far + 1) / @total_files,
                             files_so_far + 1,
                             @total_files)

      if $stdout.tty?
        # Print a progress bar, but make sure it fits on a single line. Filename
        # will be truncated if necessary.
        terminal_width = (ENV['COLUMNS'] || 80).to_i
        max_filename_size = terminal_width - progress_bar.size
        if filename.size > max_filename_size
          # Turn "some_long_filename.rb" to "...ong_filename.rb"
          filename = filename[(filename.size - max_filename_size) .. -1]
          filename[0..2] = "..."
        end

        # Pad the line with whitespaces so that leftover output from the
        # previous line doesn't show up.
        line = "#{progress_bar}#{filename}"
        padding = terminal_width - line.size
        line << (" " * padding) if padding > 0

        $stdout.print("#{line}\r")
      else
        $stdout.puts "#{progress_bar} #{filename}"
      end
      $stdout.flush
    end

    def done_adding # :nodoc:
      puts
    end

  end

  ##
  # Stats printer that prints everything documented, including the documented
  # status

  class Verbose < Normal

    ##
    # Returns a marker for RDoc::CodeObject +co+ being undocumented

    def nodoc co
      " (undocumented)" unless co.documented?
    end

    def print_alias as # :nodoc:
      puts "\t\talias #{as.new_name} #{as.old_name}#{nodoc as}"
    end

    def print_class(klass) # :nodoc:
      puts "\tclass #{klass.full_name}#{nodoc klass}"
    end

    def print_constant(constant) # :nodoc:
      puts "\t\t#{constant.name}#{nodoc constant}"
    end

    def print_file(files_so_far, file) # :nodoc:
      super
      puts
    end

    def print_method(method) # :nodoc:
      puts "\t\t#{method.singleton ? '::' : '#'}#{method.name}#{nodoc method}"
    end

    def print_module(mod) # :nodoc:
      puts "\tmodule #{mod.full_name}#{nodoc mod}"
    end

  end

end


