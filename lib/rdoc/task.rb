#--
# Copyright (c) 2003, 2004 Jim Weirich, 2009 Eric Hodel
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#++

require 'rubygems'
begin
  gem 'rdoc'
rescue Gem::LoadError
end

begin
  gem 'rake'
rescue Gem::LoadError
end

require 'rdoc'
require 'rake'
require 'rake/tasklib'

##
# Create a documentation task that will generate the RDoc files for a project.
#
# The RDoc::Task will create the following targets:
#
# [rdoc]
#   Main task for this RDoc task.
#
# [clobber_rdoc]
#   Delete all the rdoc files.  This target is automatically added to the main
#   clobber target.
#
# [rerdoc]
#   Rebuild the rdoc files from scratch, even if they are not out of date.
#
# Simple Example:
#
#   gem 'rdoc'
#   require 'rdoc/task'
#
#   RDoc::Task.new do |rd|
#     rd.main = "README.rdoc"
#     rd.rdoc_files.include("README.rdoc", "lib/**/*.rb")
#   end
#
# The +rd+ object passed to the block is an RDoc::Task object. See the
# attributes list for the RDoc::Task class for available customization options.
#
# == Specifying different task names
#
# You may wish to give the task a different name, such as if you are
# generating two sets of documentation.  For instance, if you want to have a
# development set of documentation including private methods:
#
#   gem 'rdoc'
#   require 'rdoc/task'
#
#   RDoc::Task.new :rdoc_dev do |rd|
#     rd.main = "README.doc"
#     rd.rdoc_files.include("README.rdoc", "lib/**/*.rb")
#     rd.options << "--all"
#   end
#
# The tasks would then be named :<em>rdoc_dev</em>,
# :clobber_<em>rdoc_dev</em>, and :re<em>rdoc_dev</em>.
#
# If you wish to have completely different task names, then pass a Hash as
# first argument. With the <tt>:rdoc</tt>, <tt>:clobber_rdoc</tt> and
# <tt>:rerdoc</tt> options, you can customize the task names to your liking.
#
# For example:
#
#   gem 'rdoc'
#   require 'rdoc/task'
#
#   RDoc::Task.new(:rdoc => "rdoc", :clobber_rdoc => "rdoc:clean",
#                  :rerdoc => "rdoc:force")
#
# This will create the tasks <tt>:rdoc</tt>, <tt>:rdoc:clean</tt> and
# <tt>:rdoc:force</tt>.

class RDoc::Task < Rake::TaskLib

  ##
  # Name of the main, top level task.  (default is :rdoc)

  attr_accessor :name

  ##
  # Name of directory to receive the html output files. (default is "html")

  attr_accessor :rdoc_dir

  ##
  # Title of RDoc documentation. (defaults to rdoc's default)

  attr_accessor :title

  ##
  # Name of file to be used as the main, top level file of the RDoc. (default
  # is none)

  attr_accessor :main

  ##
  # Name of template to be used by rdoc. (defaults to rdoc's default)

  attr_accessor :template

  ##
  # Name of format generator (--fmt) used by rdoc. (defaults to rdoc's default)

  attr_accessor :generator

  ##
  # List of files to be included in the rdoc generation. (default is [])

  attr_accessor :rdoc_files

  ##
  # Additional list of options to be passed rdoc.  (default is [])

  attr_accessor :options

  ##
  # Whether to run the rdoc process as an external shell (default is false)

  attr_accessor :external

  ##
  # Create an RDoc task with the given name. See the RDoc::Task class overview
  # for documentation.

  def initialize(name = :rdoc)  # :yield: self
    if name.is_a? Hash then
      invalid_options = name.keys.map { |k| k.to_sym } -
        [:rdoc, :clobber_rdoc, :rerdoc]

      unless invalid_options.empty? then
        raise ArgumentError, "invalid options: #{invalid_options.join(", ")}"
      end
    end

    @name = name
    @rdoc_files = Rake::FileList.new
    @rdoc_dir = 'html'
    @main = nil
    @title = nil
    @template = nil
    @generator = nil
    @options = []
    yield self if block_given?
    define
  end

  ##
  # All source is inline now.  This method is deprecated

  def inline_source() # :nodoc:
    warn "RDoc::Task#inline_source is deprecated"
    true
  end

  ##
  # All source is inline now.  This method is deprecated

  def inline_source=(value) # :nodoc:
    warn "RDoc::Task#inline_source is deprecated"
  end

  ##
  # Create the tasks defined by this task lib.

  def define
    desc "Build RDoc HTML files"
    task rdoc_task_name

    desc "Rebuild RDoc HTML files"
    task rerdoc_task_name => [clobber_task_name, rdoc_task_name]

    desc "Remove RDoc HTML files"
    task clobber_task_name do
      rm_r @rdoc_dir rescue nil
    end

    task :clobber => [clobber_task_name]

    directory @rdoc_dir

    rdoc_target_deps = [
      @rdoc_files,
      Rake.application.rakefile
    ].flatten.compact

    task rdoc_task_name => [rdoc_target]
    file rdoc_target => rdoc_target_deps do
      @before_running_rdoc.call if @before_running_rdoc
      args = option_list + @rdoc_files

      if Rake.application.options.trace then
        $stderr.puts "rdoc #{args.join ' '}"
      end
      require 'rdoc/rdoc'
      RDoc::RDoc.new.document(args)
    end

    self
  end

  ##
  # List of options that will be supplied to RDoc

  def option_list
    result = @options.dup
    result << "-o"      << @rdoc_dir
    result << "--main"  << main      if main
    result << "--title" << title     if title
    result << "-T"      << template  if template
    result << '-f'      << generator if generator
    result
  end

  ##
  # The block passed to this method will be called just before running the
  # RDoc generator. It is allowed to modify RDoc::Task attributes inside the
  # block.

  def before_running_rdoc(&block)
    @before_running_rdoc = block
  end

  private

  def rdoc_target
    "#{rdoc_dir}/index.html"
  end

  def rdoc_task_name
    case name
    when Hash then (name[:rdoc] || "rdoc").to_s
    else           name.to_s
    end
  end

  def clobber_task_name
    case name
    when Hash then (name[:clobber_rdoc] || "clobber_rdoc").to_s
    else           "clobber_#{name}"
    end
  end

  def rerdoc_task_name
    case name
    when Hash then (name[:rerdoc] || "rerdoc").to_s
    else           "re#{name}"
    end
  end

end

# :stopdoc:
module Rake

  ##
  # For backwards compatibility

  RDocTask = RDoc::Task

end
# :startdoc:

