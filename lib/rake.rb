#--

# Copyright 2003, 2004, 2005, 2006, 2007, 2008 by Jim Weirich (jim@weirichhouse.org)
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to
# deal in the Software without restriction, including without limitation the
# rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
# sell copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
# IN THE SOFTWARE.
#++
#
# = Rake -- Ruby Make
#
# This is the main file for the Rake application.  Normally it is referenced
# as a library via a require statement, but it can be distributed
# independently as an application.

RAKEVERSION = '0.8.7'

require 'rbconfig'
require 'fileutils'
require 'singleton'
require 'monitor'
require 'optparse'
require 'ostruct'

require 'rake/win32'

$trace = false

######################################################################
# Rake extensions to Module.
#
class Module
  # Check for an existing method in the current class before extending.  IF
  # the method already exists, then a warning is printed and the extension is
  # not added.  Otherwise the block is yielded and any definitions in the
  # block will take effect.
  #
  # Usage:
  #
  #   class String
  #     rake_extension("xyz") do
  #       def xyz
  #         ...
  #       end
  #     end
  #   end
  #
  def rake_extension(method)
    if method_defined?(method)
      $stderr.puts "WARNING: Possible conflict with Rake extension: #{self}##{method} already exists"
    else
      yield
    end
  end
end # module Module


######################################################################
# User defined methods to be added to String.
#
class String
  rake_extension("ext") do
    # Replace the file extension with +newext+.  If there is no extension on
    # the string, append the new extension to the end.  If the new extension
    # is not given, or is the empty string, remove any existing extension.
    #
    # +ext+ is a user added method for the String class.
    def ext(newext='')
      return self.dup if ['.', '..'].include? self
      if newext != ''
        newext = (newext =~ /^\./) ? newext : ("." + newext)
      end
      self.chomp(File.extname(self)) << newext
    end
  end

  rake_extension("pathmap") do
    # Explode a path into individual components.  Used by +pathmap+.
    def pathmap_explode
      head, tail = File.split(self)
      return [self] if head == self
      return [tail] if head == '.' || tail == '/'
      return [head, tail] if head == '/'
      return head.pathmap_explode + [tail]
    end
    protected :pathmap_explode

    # Extract a partial path from the path.  Include +n+ directories from the
    # front end (left hand side) if +n+ is positive.  Include |+n+|
    # directories from the back end (right hand side) if +n+ is negative.
    def pathmap_partial(n)
      dirs = File.dirname(self).pathmap_explode
      partial_dirs =
        if n > 0
          dirs[0...n]
        elsif n < 0
          dirs.reverse[0...-n].reverse
        else
          "."
        end
      File.join(partial_dirs)
    end
    protected :pathmap_partial

    # Preform the pathmap replacement operations on the given path. The
    # patterns take the form 'pat1,rep1;pat2,rep2...'.
    def pathmap_replace(patterns, &block)
      result = self
      patterns.split(';').each do |pair|
        pattern, replacement = pair.split(',')
        pattern = Regexp.new(pattern)
        if replacement == '*' && block_given?
          result = result.sub(pattern, &block)
        elsif replacement
          result = result.sub(pattern, replacement)
        else
          result = result.sub(pattern, '')
        end
      end
      result
    end
    protected :pathmap_replace

    # Map the path according to the given specification.  The specification
    # controls the details of the mapping.  The following special patterns are
    # recognized:
    #
    # * <b>%p</b> -- The complete path.
    # * <b>%f</b> -- The base file name of the path, with its file extension,
    #   but without any directories.
    # * <b>%n</b> -- The file name of the path without its file extension.
    # * <b>%d</b> -- The directory list of the path.
    # * <b>%x</b> -- The file extension of the path.  An empty string if there
    #   is no extension.
    # * <b>%X</b> -- Everything *but* the file extension.
    # * <b>%s</b> -- The alternate file separater if defined, otherwise use
    #   the standard file separator.
    # * <b>%%</b> -- A percent sign.
    #
    # The %d specifier can also have a numeric prefix (e.g. '%2d'). If the
    # number is positive, only return (up to) +n+ directories in the path,
    # starting from the left hand side.  If +n+ is negative, return (up to)
    # |+n+| directories from the right hand side of the path.
    #
    # Examples:
    #
    #   'a/b/c/d/file.txt'.pathmap("%2d")   => 'a/b'
    #   'a/b/c/d/file.txt'.pathmap("%-2d")  => 'c/d'
    #
    # Also the %d, %p, %f, %n, %x, and %X operators can take a
    # pattern/replacement argument to perform simple string substititions on a
    # particular part of the path.  The pattern and replacement are speparated
    # by a comma and are enclosed by curly braces.  The replacement spec comes
    # after the % character but before the operator letter.  (e.g.
    # "%{old,new}d").  Muliple replacement specs should be separated by
    # semi-colons (e.g. "%{old,new;src,bin}d").
    #
    # Regular expressions may be used for the pattern, and back refs may be
    # used in the replacement text.  Curly braces, commas and semi-colons are
    # excluded from both the pattern and replacement text (let's keep parsing
    # reasonable).
    #
    # For example:
    #
    #    "src/org/onestepback/proj/A.java".pathmap("%{^src,bin}X.class")
    #
    # returns:
    #
    #    "bin/org/onestepback/proj/A.class"
    #
    # If the replacement text is '*', then a block may be provided to perform
    # some arbitrary calculation for the replacement.
    #
    # For example:
    #
    #   "/path/to/file.TXT".pathmap("%X%{.*,*}x") { |ext|
    #      ext.downcase
    #   }
    #
    # Returns:
    #
    #  "/path/to/file.txt"
    #
    def pathmap(spec=nil, &block)
      return self if spec.nil?
      result = ''
      spec.scan(/%\{[^}]*\}-?\d*[sdpfnxX%]|%-?\d+d|%.|[^%]+/) do |frag|
        case frag
        when '%f'
          result << File.basename(self)
        when '%n'
          result << File.basename(self).ext
        when '%d'
          result << File.dirname(self)
        when '%x'
          result << File.extname(self)
        when '%X'
          result << self.ext
        when '%p'
          result << self
        when '%s'
          result << (File::ALT_SEPARATOR || File::SEPARATOR)
        when '%-'
          # do nothing
        when '%%'
          result << "%"
        when /%(-?\d+)d/
          result << pathmap_partial($1.to_i)
        when /^%\{([^}]*)\}(\d*[dpfnxX])/
          patterns, operator = $1, $2
          result << pathmap('%' + operator).pathmap_replace(patterns, &block)
        when /^%/
          fail ArgumentError, "Unknown pathmap specifier #{frag} in '#{spec}'"
        else
          result << frag
        end
      end
      result
    end
  end
end # class String

##############################################################################
module Rake

  # Errors -----------------------------------------------------------

  # Error indicating an ill-formed task declaration.
  class TaskArgumentError < ArgumentError
  end

  # Error indicating a recursion overflow error in task selection.
  class RuleRecursionOverflowError < StandardError
    def initialize(*args)
      super
      @targets = []
    end

    def add_target(target)
      @targets << target
    end

    def message
      super + ": [" + @targets.reverse.join(' => ') + "]"
    end
  end

  # --------------------------------------------------------------------------
  # Rake module singleton methods.
  #
  class << self
    # Current Rake Application
    def application
      @application ||= Rake::Application.new
    end

    # Set the current Rake application object.
    def application=(app)
      @application = app
    end

    # Return the original directory where the Rake application was started.
    def original_dir
      application.original_dir
    end

  end

  ####################################################################
  # Mixin for creating easily cloned objects.
  #
  module Cloneable
    # Clone an object by making a new object and setting all the instance
    # variables to the same values.
    def dup
      sibling = self.class.new
      instance_variables.each do |ivar|
        value = self.instance_variable_get(ivar)
        new_value = value.clone rescue value
        sibling.instance_variable_set(ivar, new_value)
      end
      sibling.taint if tainted?
      sibling
    end

    def clone
      sibling = dup
      sibling.freeze if frozen?
      sibling
    end
  end

  ####################################################################
  # Exit status class for times the system just gives us a nil.
  class PseudoStatus
    attr_reader :exitstatus
    def initialize(code=0)
      @exitstatus = code
    end
    def to_i
      @exitstatus << 8
    end
    def >>(n)
      to_i >> n
    end
    def stopped?
      false
    end
    def exited?
      true
    end
  end

  ####################################################################
  # TaskAguments manage the arguments passed to a task.
  #
  class TaskArguments
    include Enumerable

    attr_reader :names

    # Create a TaskArgument object with a list of named arguments
    # (given by :names) and a set of associated values (given by
    # :values).  :parent is the parent argument object.
    def initialize(names, values, parent=nil)
      @names = names
      @parent = parent
      @hash = {}
      names.each_with_index { |name, i|
        @hash[name.to_sym] = values[i] unless values[i].nil?
      }
    end

    # Create a new argument scope using the prerequisite argument
    # names.
    def new_scope(names)
      values = names.collect { |n| self[n] }
      self.class.new(names, values, self)
    end

    # Find an argument value by name or index.
    def [](index)
      lookup(index.to_sym)
    end

    # Specify a hash of default values for task arguments. Use the
    # defaults only if there is no specific value for the given
    # argument.
    def with_defaults(defaults)
      @hash = defaults.merge(@hash)
    end

    def each(&block)
      @hash.each(&block)
    end

    def method_missing(sym, *args, &block)
      lookup(sym.to_sym)
    end

    def to_hash
      @hash
    end

    def to_s
      @hash.inspect
    end

    def inspect
      to_s
    end

    protected

    def lookup(name)
      if @hash.has_key?(name)
        @hash[name]
      elsif ENV.has_key?(name.to_s)
        ENV[name.to_s]
      elsif ENV.has_key?(name.to_s.upcase)
        ENV[name.to_s.upcase]
      elsif @parent
        @parent.lookup(name)
      end
    end
  end

  EMPTY_TASK_ARGS = TaskArguments.new([], [])

  ####################################################################
  # InvocationChain tracks the chain of task invocations to detect
  # circular dependencies.
  class InvocationChain
    def initialize(value, tail)
      @value = value
      @tail = tail
    end

    def member?(obj)
      @value == obj || @tail.member?(obj)
    end

    def append(value)
      if member?(value)
        fail RuntimeError, "Circular dependency detected: #{to_s} => #{value}"
      end
      self.class.new(value, self)
    end

    def to_s
      "#{prefix}#{@value}"
    end

    def self.append(value, chain)
      chain.append(value)
    end

    private

    def prefix
      "#{@tail.to_s} => "
    end

    class EmptyInvocationChain
      def member?(obj)
        false
      end
      def append(value)
        InvocationChain.new(value, self)
      end
      def to_s
        "TOP"
      end
    end

    EMPTY = EmptyInvocationChain.new

  end # class InvocationChain

end # module Rake

module Rake

  ###########################################################################
  # A Task is the basic unit of work in a Rakefile.  Tasks have associated
  # actions (possibly more than one) and a list of prerequisites.  When
  # invoked, a task will first ensure that all of its prerequisites have an
  # opportunity to run and then it will execute its own actions.
  #
  # Tasks are not usually created directly using the new method, but rather
  # use the +file+ and +task+ convenience methods.
  #
  class Task
    # List of prerequisites for a task.
    attr_reader :prerequisites

    # List of actions attached to a task.
    attr_reader :actions

    # Application owning this task.
    attr_accessor :application

    # Comment for this task.  Restricted to a single line of no more than 50
    # characters.
    attr_reader :comment

    # Full text of the (possibly multi-line) comment.
    attr_reader :full_comment

    # Array of nested namespaces names used for task lookup by this task.
    attr_reader :scope

    # Return task name
    def to_s
      name
    end

    def inspect
      "<#{self.class} #{name} => [#{prerequisites.join(', ')}]>"
    end

    # List of sources for task.
    attr_writer :sources
    def sources
      @sources ||= []
    end

    # First source from a rule (nil if no sources)
    def source
      @sources.first if defined?(@sources)
    end

    # Create a task named +task_name+ with no actions or prerequisites. Use
    # +enhance+ to add actions and prerequisites.
    def initialize(task_name, app)
      @name = task_name.to_s
      @prerequisites = []
      @actions = []
      @already_invoked = false
      @full_comment = nil
      @comment = nil
      @lock = Monitor.new
      @application = app
      @scope = app.current_scope
      @arg_names = nil
    end

    # Enhance a task with prerequisites or actions.  Returns self.
    def enhance(deps=nil, &block)
      @prerequisites |= deps if deps
      @actions << block if block_given?
      self
    end

    # Name of the task, including any namespace qualifiers.
    def name
      @name.to_s
    end

    # Name of task with argument list description.
    def name_with_args # :nodoc:
      if arg_description
        "#{name}#{arg_description}"
      else
        name
      end
    end

    # Argument description (nil if none).
    def arg_description # :nodoc:
      @arg_names ? "[#{(arg_names || []).join(',')}]" : nil
    end

    # Name of arguments for this task.
    def arg_names
      @arg_names || []
    end

    # Reenable the task, allowing its tasks to be executed if the task
    # is invoked again.
    def reenable
      @already_invoked = false
    end

    # Clear the existing prerequisites and actions of a rake task.
    def clear
      clear_prerequisites
      clear_actions
      self
    end

    # Clear the existing prerequisites of a rake task.
    def clear_prerequisites
      prerequisites.clear
      self
    end

    # Clear the existing actions on a rake task.
    def clear_actions
      actions.clear
      self
    end

    # Invoke the task if it is needed.  Prerequites are invoked first.
    def invoke(*args)
      task_args = TaskArguments.new(arg_names, args)
      invoke_with_call_chain(task_args, InvocationChain::EMPTY)
    end

    # Same as invoke, but explicitly pass a call chain to detect
    # circular dependencies.
    def invoke_with_call_chain(task_args, invocation_chain) # :nodoc:
      new_chain = InvocationChain.append(self, invocation_chain)
      @lock.synchronize do
        if application.options.trace
          puts "** Invoke #{name} #{format_trace_flags}"
        end
        return if @already_invoked
        @already_invoked = true
        invoke_prerequisites(task_args, new_chain)
        execute(task_args) if needed?
      end
    end
    protected :invoke_with_call_chain

    # Invoke all the prerequisites of a task.
    def invoke_prerequisites(task_args, invocation_chain) # :nodoc:
      @prerequisites.each { |n|
        prereq = application[n, @scope]
        prereq_args = task_args.new_scope(prereq.arg_names)
        prereq.invoke_with_call_chain(prereq_args, invocation_chain)
      }
    end

    # Format the trace flags for display.
    def format_trace_flags
      flags = []
      flags << "first_time" unless @already_invoked
      flags << "not_needed" unless needed?
      flags.empty? ? "" : "(" + flags.join(", ") + ")"
    end
    private :format_trace_flags

    # Execute the actions associated with this task.
    def execute(args=nil)
      args ||= EMPTY_TASK_ARGS
      if application.options.dryrun
        puts "** Execute (dry run) #{name}"
        return
      end
      if application.options.trace
        puts "** Execute #{name}"
      end
      application.enhance_with_matching_rule(name) if @actions.empty?
      @actions.each do |act|
        case act.arity
        when 1
          act.call(self)
        else
          act.call(self, args)
        end
      end
    end

    # Is this task needed?
    def needed?
      true
    end

    # Timestamp for this task.  Basic tasks return the current time for their
    # time stamp.  Other tasks can be more sophisticated.
    def timestamp
      @prerequisites.collect { |p| application[p].timestamp }.max || Time.now
    end

    # Add a description to the task.  The description can consist of an option
    # argument list (enclosed brackets) and an optional comment.
    def add_description(description)
      return if ! description
      comment = description.strip
      add_comment(comment) if comment && ! comment.empty?
    end

    # Writing to the comment attribute is the same as adding a description.
    def comment=(description)
      add_description(description)
    end

    # Add a comment to the task.  If a comment alread exists, separate
    # the new comment with " / ".
    def add_comment(comment)
      if @full_comment
        @full_comment << " / "
      else
        @full_comment = ''
      end
      @full_comment << comment
      if @full_comment =~ /\A([^.]+?\.)( |$)/
        @comment = $1
      else
        @comment = @full_comment
      end
    end
    private :add_comment

    # Set the names of the arguments for this task. +args+ should be
    # an array of symbols, one for each argument name.
    def set_arg_names(args)
      @arg_names = args.map { |a| a.to_sym }
    end

    # Return a string describing the internal state of a task.  Useful for
    # debugging.
    def investigation
      result = "------------------------------\n"
      result << "Investigating #{name}\n"
      result << "class: #{self.class}\n"
      result <<  "task needed: #{needed?}\n"
      result <<  "timestamp: #{timestamp}\n"
      result << "pre-requisites: \n"
      prereqs = @prerequisites.collect {|name| application[name]}
      prereqs.sort! {|a,b| a.timestamp <=> b.timestamp}
      prereqs.each do |p|
        result << "--#{p.name} (#{p.timestamp})\n"
      end
      latest_prereq = @prerequisites.collect{|n| application[n].timestamp}.max
      result <<  "latest-prerequisite time: #{latest_prereq}\n"
      result << "................................\n\n"
      return result
    end

    # ----------------------------------------------------------------
    # Rake Module Methods
    #
    class << self

      # Clear the task list.  This cause rake to immediately forget all the
      # tasks that have been assigned.  (Normally used in the unit tests.)
      def clear
        Rake.application.clear
      end

      # List of all defined tasks.
      def tasks
        Rake.application.tasks
      end

      # Return a task with the given name.  If the task is not currently
      # known, try to synthesize one from the defined rules.  If no rules are
      # found, but an existing file matches the task name, assume it is a file
      # task with no dependencies or actions.
      def [](task_name)
        Rake.application[task_name]
      end

      # TRUE if the task name is already defined.
      def task_defined?(task_name)
        Rake.application.lookup(task_name) != nil
      end

      # Define a task given +args+ and an option block.  If a rule with the
      # given name already exists, the prerequisites and actions are added to
      # the existing task.  Returns the defined task.
      def define_task(*args, &block)
        Rake.application.define_task(self, *args, &block)
      end

      # Define a rule for synthesizing tasks.
      def create_rule(*args, &block)
        Rake.application.create_rule(*args, &block)
      end

      # Apply the scope to the task name according to the rules for
      # this kind of task.  Generic tasks will accept the scope as
      # part of the name.
      def scope_name(scope, task_name)
        (scope + [task_name]).join(':')
      end

    end # class << Rake::Task
  end # class Rake::Task


  ###########################################################################
  # A FileTask is a task that includes time based dependencies.  If any of a
  # FileTask's prerequisites have a timestamp that is later than the file
  # represented by this task, then the file must be rebuilt (using the
  # supplied actions).
  #
  class FileTask < Task

    # Is this file task needed?  Yes if it doesn't exist, or if its time stamp
    # is out of date.
    def needed?
      ! File.exist?(name) || out_of_date?(timestamp)
    end

    # Time stamp for file task.
    def timestamp
      if File.exist?(name)
        File.mtime(name.to_s)
      else
        Rake::EARLY
      end
    end

    private

    # Are there any prerequisites with a later time than the given time stamp?
    def out_of_date?(stamp)
      @prerequisites.any? { |n| application[n].timestamp > stamp}
    end

    # ----------------------------------------------------------------
    # Task class methods.
    #
    class << self
      # Apply the scope to the task name according to the rules for this kind
      # of task.  File based tasks ignore the scope when creating the name.
      def scope_name(scope, task_name)
        task_name
      end
    end
  end # class Rake::FileTask

  ###########################################################################
  # A FileCreationTask is a file task that when used as a dependency will be
  # needed if and only if the file has not been created.  Once created, it is
  # not re-triggered if any of its dependencies are newer, nor does trigger
  # any rebuilds of tasks that depend on it whenever it is updated.
  #
  class FileCreationTask < FileTask
    # Is this file task needed?  Yes if it doesn't exist.
    def needed?
      ! File.exist?(name)
    end

    # Time stamp for file creation task.  This time stamp is earlier
    # than any other time stamp.
    def timestamp
      Rake::EARLY
    end
  end

  ###########################################################################
  # Same as a regular task, but the immediate prerequisites are done in
  # parallel using Ruby threads.
  #
  class MultiTask < Task
    private
    def invoke_prerequisites(args, invocation_chain)
      threads = @prerequisites.collect { |p|
        Thread.new(p) { |r| application[r].invoke_with_call_chain(args, invocation_chain) }
      }
      threads.each { |t| t.join }
    end
  end
end # module Rake

## ###########################################################################
# Task Definition Functions ...

# Declare a basic task.
#
# Example:
#   task :clobber => [:clean] do
#     rm_rf "html"
#   end
#
def task(*args, &block)
  Rake::Task.define_task(*args, &block)
end


# Declare a file task.
#
# Example:
#   file "config.cfg" => ["config.template"] do
#     open("config.cfg", "w") do |outfile|
#       open("config.template") do |infile|
#         while line = infile.gets
#           outfile.puts line
#         end
#       end
#     end
#  end
#
def file(*args, &block)
  Rake::FileTask.define_task(*args, &block)
end

# Declare a file creation task.
# (Mainly used for the directory command).
def file_create(args, &block)
  Rake::FileCreationTask.define_task(args, &block)
end

# Declare a set of files tasks to create the given directories on demand.
#
# Example:
#   directory "testdata/doc"
#
def directory(dir)
  Rake.each_dir_parent(dir) do |d|
    file_create d do |t|
      mkdir_p t.name if ! File.exist?(t.name)
    end
  end
end

# Declare a task that performs its prerequisites in parallel. Multitasks does
# *not* guarantee that its prerequisites will execute in any given order
# (which is obvious when you think about it)
#
# Example:
#   multitask :deploy => [:deploy_gem, :deploy_rdoc]
#
def multitask(args, &block)
  Rake::MultiTask.define_task(args, &block)
end

# Create a new rake namespace and use it for evaluating the given block.
# Returns a NameSpace object that can be used to lookup tasks defined in the
# namespace.
#
# E.g.
#
#   ns = namespace "nested" do
#     task :run
#   end
#   task_run = ns[:run] # find :run in the given namespace.
#
def namespace(name=nil, &block)
  Rake.application.in_namespace(name, &block)
end

# Declare a rule for auto-tasks.
#
# Example:
#  rule '.o' => '.c' do |t|
#    sh %{cc -o #{t.name} #{t.source}}
#  end
#
def rule(*args, &block)
  Rake::Task.create_rule(*args, &block)
end

# Describe the next rake task.
#
# Example:
#   desc "Run the Unit Tests"
#   task :test => [:build]
#     runtests
#   end
#
def desc(description)
  Rake.application.last_description = description
end

# Import the partial Rakefiles +fn+.  Imported files are loaded _after_ the
# current file is completely loaded.  This allows the import statement to
# appear anywhere in the importing file, and yet allowing the imported files
# to depend on objects defined in the importing file.
#
# A common use of the import statement is to include files containing
# dependency declarations.
#
# See also the --rakelibdir command line option.
#
# Example:
#   import ".depend", "my_rules"
#
def import(*fns)
  fns.each do |fn|
    Rake.application.add_import(fn)
  end
end

#############################################################################
# This a FileUtils extension that defines several additional commands to be
# added to the FileUtils utility functions.
#
module FileUtils
  RUBY_EXT = ((RbConfig::CONFIG['ruby_install_name'] =~ /\.(com|cmd|exe|bat|rb|sh)$/) ?
    "" :
    RbConfig::CONFIG['EXEEXT'])

  RUBY = File.join(
    RbConfig::CONFIG['bindir'],
    RbConfig::CONFIG['ruby_install_name'] + RUBY_EXT).
    sub(/.*\s.*/m, '"\&"')

  OPT_TABLE['sh']  = %w(noop verbose)
  OPT_TABLE['ruby'] = %w(noop verbose)

  # Run the system command +cmd+. If multiple arguments are given the command
  # is not run with the shell (same semantics as Kernel::exec and
  # Kernel::system).
  #
  # Example:
  #   sh %{ls -ltr}
  #
  #   sh 'ls', 'file with spaces'
  #
  #   # check exit status after command runs
  #   sh %{grep pattern file} do |ok, res|
  #     if ! ok
  #       puts "pattern not found (status = #{res.exitstatus})"
  #     end
  #   end
  #
  def sh(*cmd, &block)
    options = (Hash === cmd.last) ? cmd.pop : {}
    unless block_given?
      show_command = cmd.join(" ")
      show_command = show_command[0,42] + "..." unless $trace
      # TODO code application logic heref show_command.length > 45
      block = lambda { |ok, status|
        ok or fail "Command failed with status (#{status.exitstatus}): [#{show_command}]"
      }
    end
    if RakeFileUtils.verbose_flag == :default
      options[:verbose] = true
    else
      options[:verbose] ||= RakeFileUtils.verbose_flag
    end
    options[:noop]    ||= RakeFileUtils.nowrite_flag
    rake_check_options options, :noop, :verbose
    rake_output_message cmd.join(" ") if options[:verbose]
    unless options[:noop]
      res = rake_system(*cmd)
      status = $?
      status = PseudoStatus.new(1) if !res && status.nil?
      block.call(res, status)
    end
  end

  def rake_system(*cmd)
    system(*cmd)
  end
  private :rake_system

  # Run a Ruby interpreter with the given arguments.
  #
  # Example:
  #   ruby %{-pe '$_.upcase!' <README}
  #
  def ruby(*args,&block)
    options = (Hash === args.last) ? args.pop : {}
    if args.length > 1 then
      sh(*([RUBY] + args + [options]), &block)
    else
      sh("#{RUBY} #{args.first}", options, &block)
    end
  end

  LN_SUPPORTED = [true]

  #  Attempt to do a normal file link, but fall back to a copy if the link
  #  fails.
  def safe_ln(*args)
    unless LN_SUPPORTED[0]
      cp(*args)
    else
      begin
        ln(*args)
      rescue StandardError, NotImplementedError => ex
        LN_SUPPORTED[0] = false
        cp(*args)
      end
    end
  end

  # Split a file path into individual directory names.
  #
  # Example:
  #   split_all("a/b/c") =>  ['a', 'b', 'c']
  #
  def split_all(path)
    head, tail = File.split(path)
    return [tail] if head == '.' || tail == '/'
    return [head, tail] if head == '/'
    return split_all(head) + [tail]
  end
end

#############################################################################
# RakeFileUtils provides a custom version of the FileUtils methods that
# respond to the <tt>verbose</tt> and <tt>nowrite</tt> commands.
#
module RakeFileUtils
  include FileUtils

  class << self
    attr_accessor :verbose_flag, :nowrite_flag
  end
  RakeFileUtils.verbose_flag = :default
  RakeFileUtils.nowrite_flag = false

  $fileutils_verbose = true
  $fileutils_nowrite = false

  FileUtils::OPT_TABLE.each do |name, opts|
    default_options = []
    if opts.include?(:verbose) || opts.include?("verbose")
      default_options << ':verbose => RakeFileUtils.verbose_flag'
    end
    if opts.include?(:noop) || opts.include?("noop")
      default_options << ':noop => RakeFileUtils.nowrite_flag'
    end

    next if default_options.empty?
    module_eval(<<-EOS, __FILE__, __LINE__ + 1)
    def #{name}( *args, &block )
      super(
        *rake_merge_option(args,
          #{default_options.join(', ')}
          ), &block)
    end
    EOS
  end

  # Get/set the verbose flag controlling output from the FileUtils utilities.
  # If verbose is true, then the utility method is echoed to standard output.
  #
  # Examples:
  #    verbose              # return the current value of the verbose flag
  #    verbose(v)           # set the verbose flag to _v_.
  #    verbose(v) { code }  # Execute code with the verbose flag set temporarily to _v_.
  #                         # Return to the original value when code is done.
  def verbose(value=nil)
    oldvalue = RakeFileUtils.verbose_flag
    RakeFileUtils.verbose_flag = value unless value.nil?
    if block_given?
      begin
        yield
      ensure
        RakeFileUtils.verbose_flag = oldvalue
      end
    end
    RakeFileUtils.verbose_flag
  end

  # Get/set the nowrite flag controlling output from the FileUtils utilities.
  # If verbose is true, then the utility method is echoed to standard output.
  #
  # Examples:
  #    nowrite              # return the current value of the nowrite flag
  #    nowrite(v)           # set the nowrite flag to _v_.
  #    nowrite(v) { code }  # Execute code with the nowrite flag set temporarily to _v_.
  #                         # Return to the original value when code is done.
  def nowrite(value=nil)
    oldvalue = RakeFileUtils.nowrite_flag
    RakeFileUtils.nowrite_flag = value unless value.nil?
    if block_given?
      begin
        yield
      ensure
        RakeFileUtils.nowrite_flag = oldvalue
      end
    end
    oldvalue
  end

  # Use this function to prevent protentially destructive ruby code from
  # running when the :nowrite flag is set.
  #
  # Example:
  #
  #   when_writing("Building Project") do
  #     project.build
  #   end
  #
  # The following code will build the project under normal conditions. If the
  # nowrite(true) flag is set, then the example will print:
  #      DRYRUN: Building Project
  # instead of actually building the project.
  #
  def when_writing(msg=nil)
    if RakeFileUtils.nowrite_flag
      puts "DRYRUN: #{msg}" if msg
    else
      yield
    end
  end

  # Merge the given options with the default values.
  def rake_merge_option(args, defaults)
    if Hash === args.last
      defaults.update(args.last)
      args.pop
    end
    args.push defaults
    args
  end
  private :rake_merge_option

  # Send the message to the default rake output (which is $stderr).
  def rake_output_message(message)
    $stderr.puts(message)
  end
  private :rake_output_message

  # Check that the options do not contain options not listed in +optdecl+.  An
  # ArgumentError exception is thrown if non-declared options are found.
  def rake_check_options(options, *optdecl)
    h = options.dup
    optdecl.each do |name|
      h.delete name
    end
    raise ArgumentError, "no such option: #{h.keys.join(' ')}" unless h.empty?
  end
  private :rake_check_options

  extend self
end

#############################################################################
# Include the FileUtils file manipulation functions in the top level module,
# but mark them private so that they don't unintentionally define methods on
# other objects.

include RakeFileUtils
private(*FileUtils.instance_methods(false))
private(*RakeFileUtils.instance_methods(false))

######################################################################
module Rake

  ###########################################################################
  # A FileList is essentially an array with a few helper methods defined to
  # make file manipulation a bit easier.
  #
  # FileLists are lazy.  When given a list of glob patterns for possible files
  # to be included in the file list, instead of searching the file structures
  # to find the files, a FileList holds the pattern for latter use.
  #
  # This allows us to define a number of FileList to match any number of
  # files, but only search out the actual files when then FileList itself is
  # actually used.  The key is that the first time an element of the
  # FileList/Array is requested, the pending patterns are resolved into a real
  # list of file names.
  #
  class FileList

    include Cloneable

    # == Method Delegation
    #
    # The lazy evaluation magic of FileLists happens by implementing all the
    # array specific methods to call +resolve+ before delegating the heavy
    # lifting to an embedded array object (@items).
    #
    # In addition, there are two kinds of delegation calls.  The regular kind
    # delegates to the @items array and returns the result directly.  Well,
    # almost directly.  It checks if the returned value is the @items object
    # itself, and if so will return the FileList object instead.
    #
    # The second kind of delegation call is used in methods that normally
    # return a new Array object.  We want to capture the return value of these
    # methods and wrap them in a new FileList object.  We enumerate these
    # methods in the +SPECIAL_RETURN+ list below.

    # List of array methods (that are not in +Object+) that need to be
    # delegated.
    ARRAY_METHODS = (Array.instance_methods - (Object.instance_methods - [:<=>])).map { |n| n.to_s }

    # List of additional methods that must be delegated.
    MUST_DEFINE = %w[to_a inspect]

    # List of methods that should not be delegated here (we define special
    # versions of them explicitly below).
    MUST_NOT_DEFINE = %w[to_a to_ary partition *]

    # List of delegated methods that return new array values which need
    # wrapping.
    SPECIAL_RETURN = %w[
      map collect sort sort_by select find_all reject grep
      compact flatten uniq values_at
      + - & |
    ]

    DELEGATING_METHODS = (ARRAY_METHODS + MUST_DEFINE - MUST_NOT_DEFINE).collect{ |s| s.to_s }.sort.uniq

    # Now do the delegation.
    DELEGATING_METHODS.each_with_index do |sym, i|
      if SPECIAL_RETURN.include?(sym)
        define_method(sym) do |*args, &block|
          resolve
          result = @items.send(sym, *args, &block)
          FileList.new.import(result)
        end
      else
        define_method(sym) do |*args, &block|
          resolve
          result = @items.send(sym, *args, &block)
          result.object_id == @items.object_id ? self : result
        end
      end
    end

    # Create a file list from the globbable patterns given.  If you wish to
    # perform multiple includes or excludes at object build time, use the
    # "yield self" pattern.
    #
    # Example:
    #   file_list = FileList.new('lib/**/*.rb', 'test/test*.rb')
    #
    #   pkg_files = FileList.new('lib/**/*') do |fl|
    #     fl.exclude(/\bCVS\b/)
    #   end
    #
    def initialize(*patterns)
      @pending_add = []
      @pending = false
      @exclude_patterns = DEFAULT_IGNORE_PATTERNS.dup
      @exclude_procs = DEFAULT_IGNORE_PROCS.dup
      @exclude_re = nil
      @items = []
      patterns.each { |pattern| include(pattern) }
      yield self if block_given?
    end

    # Add file names defined by glob patterns to the file list.  If an array
    # is given, add each element of the array.
    #
    # Example:
    #   file_list.include("*.java", "*.cfg")
    #   file_list.include %w( math.c lib.h *.o )
    #
    def include(*filenames)
      # TODO: check for pending
      filenames.each do |fn|
        if fn.respond_to? :to_ary
          include(*fn.to_ary)
        else
          @pending_add << fn
        end
      end
      @pending = true
      self
    end
    alias :add :include

    # Register a list of file name patterns that should be excluded from the
    # list.  Patterns may be regular expressions, glob patterns or regular
    # strings.  In addition, a block given to exclude will remove entries that
    # return true when given to the block.
    #
    # Note that glob patterns are expanded against the file system. If a file
    # is explicitly added to a file list, but does not exist in the file
    # system, then an glob pattern in the exclude list will not exclude the
    # file.
    #
    # Examples:
    #   FileList['a.c', 'b.c'].exclude("a.c") => ['b.c']
    #   FileList['a.c', 'b.c'].exclude(/^a/)  => ['b.c']
    #
    # If "a.c" is a file, then ...
    #   FileList['a.c', 'b.c'].exclude("a.*") => ['b.c']
    #
    # If "a.c" is not a file, then ...
    #   FileList['a.c', 'b.c'].exclude("a.*") => ['a.c', 'b.c']
    #
    def exclude(*patterns, &block)
      patterns.each do |pat|
        @exclude_patterns << pat
      end
      if block_given?
        @exclude_procs << block
      end
      resolve_exclude if ! @pending
      self
    end


    # Clear all the exclude patterns so that we exclude nothing.
    def clear_exclude
      @exclude_patterns = []
      @exclude_procs = []
      calculate_exclude_regexp if ! @pending
      self
    end

    # Define equality.
    def ==(array)
      to_ary == array
    end

    # Return the internal array object.
    def to_a
      resolve
      @items
    end

    # Return the internal array object.
    def to_ary
      to_a
    end

    # Lie about our class.
    def is_a?(klass)
      klass == Array || super(klass)
    end
    alias kind_of? is_a?

    # Redefine * to return either a string or a new file list.
    def *(other)
      result = @items * other
      case result
      when Array
        FileList.new.import(result)
      else
        result
      end
    end

    # Resolve all the pending adds now.
    def resolve
      if @pending
        @pending = false
        @pending_add.each do |fn| resolve_add(fn) end
        @pending_add = []
        resolve_exclude
      end
      self
    end

    def calculate_exclude_regexp
      ignores = []
      @exclude_patterns.each do |pat|
        case pat
        when Regexp
          ignores << pat
        when /[*?]/
          Dir[pat].each do |p| ignores << p end
        else
          ignores << Regexp.quote(pat)
        end
      end
      if ignores.empty?
        @exclude_re = /^$/
      else
        re_str = ignores.collect { |p| "(" + p.to_s + ")" }.join("|")
        @exclude_re = Regexp.new(re_str)
      end
    end

    def resolve_add(fn)
      case fn
      when %r{[*?\[\{]}
        add_matching(fn)
      else
        self << fn
      end
    end
    private :resolve_add

    def resolve_exclude
      calculate_exclude_regexp
      reject! { |fn| exclude?(fn) }
      self
    end
    private :resolve_exclude

    # Return a new FileList with the results of running +sub+ against each
    # element of the oringal list.
    #
    # Example:
    #   FileList['a.c', 'b.c'].sub(/\.c$/, '.o')  => ['a.o', 'b.o']
    #
    def sub(pat, rep)
      inject(FileList.new) { |res, fn| res << fn.sub(pat,rep) }
    end

    # Return a new FileList with the results of running +gsub+ against each
    # element of the original list.
    #
    # Example:
    #   FileList['lib/test/file', 'x/y'].gsub(/\//, "\\")
    #      => ['lib\\test\\file', 'x\\y']
    #
    def gsub(pat, rep)
      inject(FileList.new) { |res, fn| res << fn.gsub(pat,rep) }
    end

    # Same as +sub+ except that the oringal file list is modified.
    def sub!(pat, rep)
      each_with_index { |fn, i| self[i] = fn.sub(pat,rep) }
      self
    end

    # Same as +gsub+ except that the original file list is modified.
    def gsub!(pat, rep)
      each_with_index { |fn, i| self[i] = fn.gsub(pat,rep) }
      self
    end

    # Apply the pathmap spec to each of the included file names, returning a
    # new file list with the modified paths.  (See String#pathmap for
    # details.)
    def pathmap(spec=nil)
      collect { |fn| fn.pathmap(spec) }
    end

    # Return a new FileList with <tt>String#ext</tt> method applied
    # to each member of the array.
    #
    # This method is a shortcut for:
    #
    #    array.collect { |item| item.ext(newext) }
    #
    # +ext+ is a user added method for the Array class.
    def ext(newext='')
      collect { |fn| fn.ext(newext) }
    end


    # Grep each of the files in the filelist using the given pattern. If a
    # block is given, call the block on each matching line, passing the file
    # name, line number, and the matching line of text.  If no block is given,
    # a standard emac style file:linenumber:line message will be printed to
    # standard out.
    def egrep(pattern, *options)
      each do |fn|
        open(fn, "rb", *options) do |inf|
          count = 0
          inf.each do |line|
            count += 1
            if pattern.match(line)
              if block_given?
                yield fn, count, line
              else
                puts "#{fn}:#{count}:#{line}"
              end
            end
          end
        end
      end
    end

    # Return a new file list that only contains file names from the current
    # file list that exist on the file system.
    def existing
      select { |fn| File.exist?(fn) }
    end

    # Modify the current file list so that it contains only file name that
    # exist on the file system.
    def existing!
      resolve
      @items = @items.select { |fn| File.exist?(fn) }
      self
    end

    # FileList version of partition.  Needed because the nested arrays should
    # be FileLists in this version.
    def partition(&block)       # :nodoc:
      resolve
      result = @items.partition(&block)
      [
        FileList.new.import(result[0]),
        FileList.new.import(result[1]),
      ]
    end

    # Convert a FileList to a string by joining all elements with a space.
    def to_s
      resolve
      self.join(' ')
    end

    # Add matching glob patterns.
    def add_matching(pattern)
      Dir[pattern].each do |fn|
        self << fn unless exclude?(fn)
      end
    end
    private :add_matching

    # Should the given file name be excluded?
    def exclude?(fn)
      calculate_exclude_regexp unless @exclude_re
      fn =~ @exclude_re || @exclude_procs.any? { |p| p.call(fn) }
    end

    DEFAULT_IGNORE_PATTERNS = [
      /(^|[\/\\])CVS([\/\\]|$)/,
      /(^|[\/\\])\.svn([\/\\]|$)/,
      /\.bak$/,
      /~$/
    ]
    DEFAULT_IGNORE_PROCS = [
      proc { |fn| fn =~ /(^|[\/\\])core$/ && ! File.directory?(fn) }
    ]
#    @exclude_patterns = DEFAULT_IGNORE_PATTERNS.dup

    def import(array)
      @items = array
      self
    end

    class << self
      # Create a new file list including the files listed. Similar to:
      #
      #   FileList.new(*args)
      def [](*args)
        new(*args)
      end
    end
  end # FileList
end

module Rake
  class << self

    # Yield each file or directory component.
    def each_dir_parent(dir)    # :nodoc:
      old_length = nil
      while dir != '.' && dir.length != old_length
        yield(dir)
        old_length = dir.length
        dir = File.dirname(dir)
      end
    end
  end
end # module Rake

# Alias FileList to be available at the top level.
FileList = Rake::FileList

#############################################################################
module Rake

  # Default Rakefile loader used by +import+.
  class DefaultLoader
    def load(fn)
      Kernel.load(File.expand_path(fn))
    end
  end

  # EarlyTime is a fake timestamp that occurs _before_ any other time value.
  class EarlyTime
    include Comparable
    include Singleton

    def <=>(other)
      -1
    end

    def to_s
      "<EARLY TIME>"
    end
  end

  EARLY = EarlyTime.instance
end # module Rake

#############################################################################
# Extensions to time to allow comparisons with an early time class.
#
class Time
  alias rake_original_time_compare :<=>
  def <=>(other)
    if Rake::EarlyTime === other
      - other.<=>(self)
    else
      rake_original_time_compare(other)
    end
  end
end # class Time

module Rake

  ####################################################################
  # The NameSpace class will lookup task names in the the scope
  # defined by a +namespace+ command.
  #
  class NameSpace

    # Create a namespace lookup object using the given task manager
    # and the list of scopes.
    def initialize(task_manager, scope_list)
      @task_manager = task_manager
      @scope = scope_list.dup
    end

    # Lookup a task named +name+ in the namespace.
    def [](name)
      @task_manager.lookup(name, @scope)
    end

    # Return the list of tasks defined in this and nested namespaces.
    def tasks
      @task_manager.tasks_in_scope(@scope)
    end
  end # NameSpace


  ####################################################################
  # The TaskManager module is a mixin for managing tasks.
  module TaskManager
    # Track the last comment made in the Rakefile.
    attr_accessor :last_description
    alias :last_comment :last_description    # Backwards compatibility

    def initialize
      super
      @tasks = Hash.new
      @rules = Array.new
      @scope = Array.new
      @last_description = nil
    end

    def create_rule(*args, &block)
      pattern, arg_names, deps = resolve_args(args)
      pattern = Regexp.new(Regexp.quote(pattern) + '$') if String === pattern
      @rules << [pattern, deps, block]
    end

    def define_task(task_class, *args, &block)
      task_name, arg_names, deps = resolve_args(args)
      task_name = task_class.scope_name(@scope, task_name)
      deps = [deps] unless deps.respond_to?(:to_ary)
      deps = deps.collect {|d| d.to_s }
      task = intern(task_class, task_name)
      task.set_arg_names(arg_names) unless arg_names.empty?
      task.add_description(@last_description)
      @last_description = nil
      task.enhance(deps, &block)
      task
    end

    # Lookup a task.  Return an existing task if found, otherwise
    # create a task of the current type.
    def intern(task_class, task_name)
      @tasks[task_name.to_s] ||= task_class.new(task_name, self)
    end

    # Find a matching task for +task_name+.
    def [](task_name, scopes=nil)
      task_name = task_name.to_s
      self.lookup(task_name, scopes) or
        enhance_with_matching_rule(task_name) or
        synthesize_file_task(task_name) or
        fail "Don't know how to build task '#{task_name}'"
    end

    def synthesize_file_task(task_name)
      return nil unless File.exist?(task_name)
      define_task(Rake::FileTask, task_name)
    end

    # Resolve the arguments for a task/rule.  Returns a triplet of
    # [task_name, arg_name_list, prerequisites].
    def resolve_args(args)
      if args.last.is_a?(Hash)
        deps = args.pop
        resolve_args_with_dependencies(args, deps)
      else
        resolve_args_without_dependencies(args)
      end
    end

    # Resolve task arguments for a task or rule when there are no
    # dependencies declared.
    #
    # The patterns recognized by this argument resolving function are:
    #
    #   task :t
    #   task :t, [:a]
    #   task :t, :a                 (deprecated)
    #
    def resolve_args_without_dependencies(args)
      task_name = args.shift
      if args.size == 1 && args.first.respond_to?(:to_ary)
        arg_names = args.first.to_ary
      else
        arg_names = args
      end
      [task_name, arg_names, []]
    end
    private :resolve_args_without_dependencies

    # Resolve task arguments for a task or rule when there are
    # dependencies declared.
    #
    # The patterns recognized by this argument resolving function are:
    #
    #   task :t => [:d]
    #   task :t, [a] => [:d]
    #   task :t, :needs => [:d]                 (deprecated)
    #   task :t, :a, :needs => [:d]             (deprecated)
    #
    def resolve_args_with_dependencies(args, hash) # :nodoc:
      fail "Task Argument Error" if hash.size != 1
      key, value = hash.map { |k, v| [k,v] }.first
      if args.empty?
        task_name = key
        arg_names = []
        deps = value
      elsif key == :needs
        task_name = args.shift
        arg_names = args
        deps = value
      else
        task_name = args.shift
        arg_names = key
        deps = value
      end
      deps = [deps] unless deps.respond_to?(:to_ary)
      [task_name, arg_names, deps]
    end
    private :resolve_args_with_dependencies

    # If a rule can be found that matches the task name, enhance the
    # task with the prerequisites and actions from the rule.  Set the
    # source attribute of the task appropriately for the rule.  Return
    # the enhanced task or nil of no rule was found.
    def enhance_with_matching_rule(task_name, level=0)
      fail Rake::RuleRecursionOverflowError,
        "Rule Recursion Too Deep" if level >= 16
      @rules.each do |pattern, extensions, block|
        if md = pattern.match(task_name)
          task = attempt_rule(task_name, extensions, block, level)
          return task if task
        end
      end
      nil
    rescue Rake::RuleRecursionOverflowError => ex
      ex.add_target(task_name)
      fail ex
    end

    # List of all defined tasks in this application.
    def tasks
      @tasks.values.sort_by { |t| t.name }
    end

    # List of all the tasks defined in the given scope (and its
    # sub-scopes).
    def tasks_in_scope(scope)
      prefix = scope.join(":")
      tasks.select { |t|
        /^#{prefix}:/ =~ t.name
      }
    end

    # Clear all tasks in this application.
    def clear
      @tasks.clear
      @rules.clear
    end

    # Lookup a task, using scope and the scope hints in the task name.
    # This method performs straight lookups without trying to
    # synthesize file tasks or rules.  Special scope names (e.g. '^')
    # are recognized.  If no scope argument is supplied, use the
    # current scope.  Return nil if the task cannot be found.
    def lookup(task_name, initial_scope=nil)
      initial_scope ||= @scope
      task_name = task_name.to_s
      if task_name =~ /^rake:/
        scopes = []
        task_name = task_name.sub(/^rake:/, '')
      elsif task_name =~ /^(\^+)/
        scopes = initial_scope[0, initial_scope.size - $1.size]
        task_name = task_name.sub(/^(\^+)/, '')
      else
        scopes = initial_scope
      end
      lookup_in_scope(task_name, scopes)
    end

    # Lookup the task name
    def lookup_in_scope(name, scope)
      n = scope.size
      while n >= 0
        tn = (scope[0,n] + [name]).join(':')
        task = @tasks[tn]
        return task if task
        n -= 1
      end
      nil
    end
    private :lookup_in_scope

    # Return the list of scope names currently active in the task
    # manager.
    def current_scope
      @scope.dup
    end

    # Evaluate the block in a nested namespace named +name+.  Create
    # an anonymous namespace if +name+ is nil.
    def in_namespace(name)
      name ||= generate_name
      @scope.push(name)
      ns = NameSpace.new(self, @scope)
      yield(ns)
      ns
    ensure
      @scope.pop
    end

    private

    # Generate an anonymous namespace name.
    def generate_name
      @seed ||= 0
      @seed += 1
      "_anon_#{@seed}"
    end

    def trace_rule(level, message)
      puts "#{"    "*level}#{message}" if Rake.application.options.trace_rules
    end

    # Attempt to create a rule given the list of prerequisites.
    def attempt_rule(task_name, extensions, block, level)
      sources = make_sources(task_name, extensions)
      prereqs = sources.collect { |source|
        trace_rule level, "Attempting Rule #{task_name} => #{source}"
        if File.exist?(source) || Rake::Task.task_defined?(source)
          trace_rule level, "(#{task_name} => #{source} ... EXIST)"
          source
        elsif parent = enhance_with_matching_rule(source, level+1)
          trace_rule level, "(#{task_name} => #{source} ... ENHANCE)"
          parent.name
        else
          trace_rule level, "(#{task_name} => #{source} ... FAIL)"
          return nil
        end
      }
      task = FileTask.define_task({task_name => prereqs}, &block)
      task.sources = prereqs
      task
    end

    # Make a list of sources from the list of file name extensions /
    # translation procs.
    def make_sources(task_name, extensions)
      extensions.collect { |ext|
        case ext
        when /%/
          task_name.pathmap(ext)
        when %r{/}
          ext
        when /^\./
          task_name.ext(ext)
        when String
          ext
        when Proc
          if ext.arity == 1
            ext.call(task_name)
          else
            ext.call
          end
        else
          fail "Don't know how to handle rule dependent: #{ext.inspect}"
        end
      }.flatten
    end

  end # TaskManager

  ######################################################################
  # Rake main application object.  When invoking +rake+ from the
  # command line, a Rake::Application object is created and run.
  #
  class Application
    include TaskManager

    # The name of the application (typically 'rake')
    attr_reader :name

    # The original directory where rake was invoked.
    attr_reader :original_dir

    # Name of the actual rakefile used.
    attr_reader :rakefile

    # List of the top level task names (task names from the command line).
    attr_reader :top_level_tasks

    DEFAULT_RAKEFILES = ['rakefile', 'Rakefile', 'rakefile.rb', 'Rakefile.rb'].freeze

    # Initialize a Rake::Application object.
    def initialize
      super
      @name = 'rake'
      @rakefiles = DEFAULT_RAKEFILES.dup
      @rakefile = nil
      @pending_imports = []
      @imported = []
      @loaders = {}
      @default_loader = Rake::DefaultLoader.new
      @original_dir = Dir.pwd
      @top_level_tasks = []
      add_loader('rb', DefaultLoader.new)
      add_loader('rf', DefaultLoader.new)
      add_loader('rake', DefaultLoader.new)
      @tty_output = STDOUT.tty?
    end

    # Run the Rake application.  The run method performs the following three steps:
    #
    # * Initialize the command line options (+init+).
    # * Define the tasks (+load_rakefile+).
    # * Run the top level tasks (+run_tasks+).
    #
    # If you wish to build a custom rake command, you should call +init+ on your
    # application.  The define any tasks.  Finally, call +top_level+ to run your top
    # level tasks.
    def run
      init
      load_rakefile
      top_level
    end

    # Initialize the command line parameters and app name.
    def init(app_name='rake')
      standard_exception_handling do
        @name = app_name
        handle_options
        collect_tasks
      end
    end

    # Find the rakefile and then load it and any pending imports.
    def load_rakefile
      standard_exception_handling do
        raw_load_rakefile
      end
    end

    # Run the top level tasks of a Rake application.
    def top_level
      standard_exception_handling do
        if options.show_tasks
          display_tasks_and_comments
        elsif options.show_prereqs
          display_prerequisites
        else
          top_level_tasks.each { |task_name| invoke_task(task_name) }
        end
      end
    end

    # Add a loader to handle imported files ending in the extension
    # +ext+.
    def add_loader(ext, loader)
      ext = ".#{ext}" unless ext =~ /^\./
      @loaders[ext] = loader
    end

    # Application options from the command line
    def options
      @options ||= OpenStruct.new
    end

    # private ----------------------------------------------------------------

    def invoke_task(task_string)
      name, args = parse_task_string(task_string)
      t = self[name]
      t.invoke(*args)
    end

    def parse_task_string(string)
      if string =~ /^([^\[]+)(\[(.*)\])$/
        name = $1
        args = $3.split(/\s*,\s*/)
      else
        name = string
        args = []
      end
      [name, args]
    end

    # Provide standard execption handling for the given block.
    def standard_exception_handling
      begin
        yield
      rescue SystemExit => ex
        # Exit silently with current status
        raise
      rescue OptionParser::InvalidOption => ex
        # Exit silently
        exit(false)
      rescue Exception => ex
        # Exit with error message
        $stderr.puts "#{name} aborted!"
        $stderr.puts ex.message
        if options.trace or true
          $stderr.puts ex.backtrace.join("\n")
        else
          $stderr.puts ex.backtrace.find {|str| str =~ /#{@rakefile}/ } || ""
          $stderr.puts "(See full trace by running task with --trace)"
        end
        exit(false)
      end
    end

    # True if one of the files in RAKEFILES is in the current directory.
    # If a match is found, it is copied into @rakefile.
    def have_rakefile
      @rakefiles.each do |fn|
        if File.exist?(fn)
          others = Dir.glob(fn, File::FNM_CASEFOLD)
          return others.size == 1 ? others.first : fn
        elsif fn == ''
          return fn
        end
      end
      return nil
    end

    # True if we are outputting to TTY, false otherwise
    def tty_output?
      @tty_output
    end

    # Override the detected TTY output state (mostly for testing)
    def tty_output=( tty_output_state )
      @tty_output = tty_output_state
    end

    # We will truncate output if we are outputting to a TTY or if we've been
    # given an explicit column width to honor
    def truncate_output?
      tty_output? || ENV['RAKE_COLUMNS']
    end

    # Display the tasks and comments.
    def display_tasks_and_comments
      displayable_tasks = tasks.select { |t|
        t.comment && t.name =~ options.show_task_pattern
      }
      if options.full_description
        displayable_tasks.each do |t|
          puts "#{name} #{t.name_with_args}"
          t.full_comment.split("\n").each do |line|
            puts "    #{line}"
          end
          puts
        end
      else
        width = displayable_tasks.collect { |t| t.name_with_args.length }.max || 10
        max_column = truncate_output? ? terminal_width - name.size - width - 7 : nil
        displayable_tasks.each do |t|
          printf "#{name} %-#{width}s  # %s\n",
            t.name_with_args, max_column ? truncate(t.comment, max_column) : t.comment
        end
      end
    end

    def terminal_width
      if ENV['RAKE_COLUMNS']
        result = ENV['RAKE_COLUMNS'].to_i
      else
        result = unix? ? dynamic_width : 80
      end
      (result < 10) ? 80 : result
    rescue
      80
    end

    # Calculate the dynamic width of the
    def dynamic_width
      @dynamic_width ||= (dynamic_width_stty.nonzero? || dynamic_width_tput)
    end

    def dynamic_width_stty
      %x{stty size 2>/dev/null}.split[1].to_i
    end

    def dynamic_width_tput
      %x{tput cols 2>/dev/null}.to_i
    end

    def unix?
      RUBY_PLATFORM =~ /(aix|darwin|linux|(net|free|open)bsd|cygwin|solaris|irix|hpux)/i
    end

    def windows?
      Win32.windows?
    end

    def truncate(string, width)
      if string.length <= width
        string
      else
        ( string[0, width-3] || "" ) + "..."
      end
    end

    # Display the tasks and prerequisites
    def display_prerequisites
      tasks.each do |t|
        puts "#{name} #{t.name}"
        t.prerequisites.each { |pre| puts "    #{pre}" }
      end
    end

    # A list of all the standard options used in rake, suitable for
    # passing to OptionParser.
    def standard_rake_options
      [
        ['--classic-namespace', '-C', "Put Task and FileTask in the top level namespace",
          lambda { |value|
            require 'rake/classic_namespace'
            options.classic_namespace = true
          }
        ],
        ['--describe', '-D [PATTERN]', "Describe the tasks (matching optional PATTERN), then exit.",
          lambda { |value|
            options.show_tasks = true
            options.full_description = true
            options.show_task_pattern = Regexp.new(value || '')
          }
        ],
        ['--dry-run', '-n', "Do a dry run without executing actions.",
          lambda { |value|
            verbose(true)
            nowrite(true)
            options.dryrun = true
            options.trace = true
          }
        ],
        ['--execute',  '-e CODE', "Execute some Ruby code and exit.",
          lambda { |value|
            eval(value)
            exit
          }
        ],
        ['--execute-print',  '-p CODE', "Execute some Ruby code, print the result, then exit.",
          lambda { |value|
            puts eval(value)
            exit
          }
        ],
        ['--execute-continue',  '-E CODE',
          "Execute some Ruby code, then continue with normal task processing.",
          lambda { |value| eval(value) }
        ],
        ['--libdir', '-I LIBDIR', "Include LIBDIR in the search path for required modules.",
          lambda { |value| $:.push(value) }
        ],
        ['--prereqs', '-P', "Display the tasks and dependencies, then exit.",
          lambda { |value| options.show_prereqs = true }
        ],
        ['--quiet', '-q', "Do not log messages to standard output.",
          lambda { |value| verbose(false) }
        ],
        ['--rakefile', '-f [FILE]', "Use FILE as the rakefile.",
          lambda { |value|
            value ||= ''
            @rakefiles.clear
            @rakefiles << value
          }
        ],
        ['--rakelibdir', '--rakelib', '-R RAKELIBDIR',
          "Auto-import any .rake files in RAKELIBDIR. (default is 'rakelib')",
          lambda { |value| options.rakelib = value.split(':') }
        ],
        ['--require', '-r MODULE', "Require MODULE before executing rakefile.",
          lambda { |value|
            begin
              require value
            rescue LoadError => ex
              begin
                rake_require value
              rescue LoadError => ex2
                raise ex
              end
            end
          }
        ],
        ['--rules', "Trace the rules resolution.",
          lambda { |value| options.trace_rules = true }
        ],
        ['--no-search', '--nosearch', '-N', "Do not search parent directories for the Rakefile.",
          lambda { |value| options.nosearch = true }
        ],
        ['--silent', '-s', "Like --quiet, but also suppresses the 'in directory' announcement.",
          lambda { |value|
            verbose(false)
            options.silent = true
          }
        ],
        ['--system',  '-g',
          "Using system wide (global) rakefiles (usually '~/.rake/*.rake').",
          lambda { |value| options.load_system = true }
        ],
        ['--no-system', '--nosystem', '-G',
          "Use standard project Rakefile search paths, ignore system wide rakefiles.",
          lambda { |value| options.ignore_system = true }
        ],
        ['--tasks', '-T [PATTERN]', "Display the tasks (matching optional PATTERN) with descriptions, then exit.",
          lambda { |value|
            options.show_tasks = true
            options.show_task_pattern = Regexp.new(value || '')
            options.full_description = false
          }
        ],
        ['--trace', '-t', "Turn on invoke/execute tracing, enable full backtrace.",
          lambda { |value|
            options.trace = true
            verbose(true)
          }
        ],
        ['--verbose', '-v', "Log message to standard output.",
          lambda { |value| verbose(true) }
        ],
        ['--version', '-V', "Display the program version.",
          lambda { |value|
            puts "rake, version #{RAKEVERSION}"
            exit
          }
        ]
      ]
    end

    # Read and handle the command line options.
    def handle_options
      options.rakelib = ['rakelib']

      OptionParser.new do |opts|
        opts.banner = "rake [-f rakefile] {options} targets..."
        opts.separator ""
        opts.separator "Options are ..."

        opts.on_tail("-h", "--help", "-H", "Display this help message.") do
          puts opts
          exit
        end

        standard_rake_options.each { |args| opts.on(*args) }
      end.parse!

      # If class namespaces are requested, set the global options
      # according to the values in the options structure.
      if options.classic_namespace
        $show_tasks = options.show_tasks
        $show_prereqs = options.show_prereqs
        $trace = options.trace
        $dryrun = options.dryrun
        $silent = options.silent
      end
    end

    # Similar to the regular Ruby +require+ command, but will check
    # for *.rake files in addition to *.rb files.
    def rake_require(file_name, paths=$LOAD_PATH, loaded=$")
      return false if loaded.include?(file_name)
      paths.each do |path|
        fn = file_name + ".rake"
        full_path = File.join(path, fn)
        if File.exist?(full_path)
          load full_path
          loaded << fn
          return true
        end
      end
      fail LoadError, "Can't find #{file_name}"
    end

    def find_rakefile_location
      here = Dir.pwd
      while ! (fn = have_rakefile)
        Dir.chdir("..")
        if Dir.pwd == here || options.nosearch
          return nil
        end
        here = Dir.pwd
      end
      [fn, here]
    ensure
      Dir.chdir(Rake.original_dir)
    end

    def raw_load_rakefile # :nodoc:
      rakefile, location = find_rakefile_location
      if (! options.ignore_system) &&
          (options.load_system || rakefile.nil?) &&
          system_dir && File.directory?(system_dir)
        puts "(in #{Dir.pwd})" unless options.silent
        glob("#{system_dir}/*.rake") do |name|
          add_import name
        end
      else
        fail "No Rakefile found (looking for: #{@rakefiles.join(', ')})" if
          rakefile.nil?
        @rakefile = rakefile
        Dir.chdir(location)
        puts "(in #{Dir.pwd})" unless options.silent
        $rakefile = @rakefile if options.classic_namespace
        load File.expand_path(@rakefile) if @rakefile && @rakefile != ''
        options.rakelib.each do |rlib|
          glob("#{rlib}/*.rake") do |name|
            add_import name
          end
        end
      end
      load_imports
    end

    def glob(path, &block)
      Dir[path.gsub("\\", '/')].each(&block)
    end
    private :glob

    # The directory path containing the system wide rakefiles.
    def system_dir
      @system_dir ||= ENV['RAKE_SYSTEM'] || standard_system_dir
    end

    # The standard directory containing system wide rake files.
    unless method_defined?(:standard_system_dir)
      def standard_system_dir #:nodoc:
        File.expand_path('~/.rake')
      end
    end
    private :standard_system_dir

    # Collect the list of tasks on the command line.  If no tasks are
    # given, return a list containing only the default task.
    # Environmental assignments are processed at this time as well.
    def collect_tasks
      @top_level_tasks = []
      ARGV.each do |arg|
        if arg =~ /^(\w+)=(.*)$/
          ENV[$1] = $2
        else
          @top_level_tasks << arg unless arg =~ /^-/
        end
      end
      @top_level_tasks.push("default") if @top_level_tasks.size == 0
    end

    # Add a file to the list of files to be imported.
    def add_import(fn)
      @pending_imports << fn
    end

    # Load the pending list of imported files.
    def load_imports
      while fn = @pending_imports.shift
        next if @imported.member?(fn)
        if fn_task = lookup(fn)
          fn_task.invoke
        end
        ext = File.extname(fn)
        loader = @loaders[ext] || @default_loader
        loader.load(fn)
        @imported << fn
      end
    end

    # Warn about deprecated use of top level constant names.
    def const_warning(const_name)
      @const_warning ||= false
      if ! @const_warning
        $stderr.puts %{WARNING: Deprecated reference to top-level constant '#{const_name}' } +
          %{found at: #{rakefile_location}} # '
        $stderr.puts %{    Use --classic-namespace on rake command}
        $stderr.puts %{    or 'require "rake/classic_namespace"' in Rakefile}
      end
      @const_warning = true
    end

    def rakefile_location
      begin
        fail
      rescue RuntimeError => ex
        ex.backtrace.find {|str| str =~ /#{@rakefile}/ } || ""
      end
    end
  end
end


class Module
  # Rename the original handler to make it available.
  alias :rake_original_const_missing :const_missing

  # Check for deprecated uses of top level (i.e. in Object) uses of
  # Rake class names.  If someone tries to reference the constant
  # name, display a warning and return the proper object.  Using the
  # --classic-namespace command line option will define these
  # constants in Object and avoid this handler.
  def const_missing(const_name)
    case const_name
    when :Task
      Rake.application.const_warning(const_name)
      Rake::Task
    when :FileTask
      Rake.application.const_warning(const_name)
      Rake::FileTask
    when :FileCreationTask
      Rake.application.const_warning(const_name)
      Rake::FileCreationTask
    when :RakeApp
      Rake.application.const_warning(const_name)
      Rake::Application
    else
      rake_original_const_missing(const_name)
    end
  end
end
