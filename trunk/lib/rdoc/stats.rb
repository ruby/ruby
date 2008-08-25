require 'rdoc'

##
# Simple stats collector

class RDoc::Stats

  attr_reader :num_classes
  attr_reader :num_files
  attr_reader :num_methods
  attr_reader :num_modules

  def initialize(verbosity = 1)
    @num_classes = 0
    @num_files   = 0
    @num_methods = 0
    @num_modules = 0

    @start = Time.now

    @display = case verbosity
               when 0 then Quiet.new
               when 1 then Normal.new
               else        Verbose.new
               end
  end

  def add_alias(as)
    @display.print_alias as
    @num_methods += 1
  end

  def add_class(klass)
    @display.print_class klass
    @num_classes += 1
  end

  def add_file(file)
    @display.print_file file
    @num_files += 1
  end

  def add_method(method)
    @display.print_method method
    @num_methods += 1
  end

  def add_module(mod)
    @display.print_module mod
    @num_modules += 1
  end

  def print
    puts "Files:   #@num_files"
    puts "Classes: #@num_classes"
    puts "Modules: #@num_modules"
    puts "Methods: #@num_methods"
    puts "Elapsed: " + sprintf("%0.1fs", Time.now - @start)
  end

  class Quiet
    def print_alias(*) end
    def print_class(*) end
    def print_file(*) end
    def print_method(*) end
    def print_module(*) end
  end

  class Normal
    def print_alias(as)
      print 'a'
    end

    def print_class(klass)
      print 'C'
    end

    def print_file(file)
      print "\n#{file}: "
    end

    def print_method(method)
      print 'm'
    end

    def print_module(mod)
      print 'M'
    end
  end

  class Verbose
    def print_alias(as)
      puts "\t\talias #{as.new_name} #{as.old_name}"
    end

    def print_class(klass)
      puts "\tclass #{klass.full_name}"
    end

    def print_file(file)
      puts file
    end

    def print_method(method)
      puts "\t\t#{method.singleton ? '::' : '#'}#{method.name}"
    end

    def print_module(mod)
      puts "\tmodule #{mod.full_name}"
    end
  end

end


