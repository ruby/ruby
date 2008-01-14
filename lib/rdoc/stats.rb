require 'rdoc'

##
# Simple stats collector

class RDoc::Stats

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


