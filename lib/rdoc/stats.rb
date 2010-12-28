require 'rdoc'

##
# RDoc statistics collector which prints a summary and report of a project's
# documentation totals.

class RDoc::Stats

  ##
  # Count of files parsed during parsing

  attr_reader :files_so_far

  ##
  # Total number of files found

  attr_reader :num_files

  ##
  # Creates a new Stats that will have +num_files+.  +verbosity+ defaults to 1
  # which will create an RDoc::Stats::Normal outputter.

  def initialize num_files, verbosity = 1
    @files_so_far = 0
    @num_files = num_files
    @fully_documented = nil
    @percent_doc = nil

    @start = Time.now

    @display = case verbosity
               when 0 then Quiet.new   num_files
               when 1 then Normal.new  num_files
               else        Verbose.new num_files
               end
  end

  ##
  # Records the parsing of an alias +as+.

  def add_alias as
    @display.print_alias as
  end

  ##
  # Records the parsing of an attribute +attribute+

  def add_attribute attribute
    @display.print_attribute attribute
  end

  ##
  # Records the parsing of a class +klass+

  def add_class klass
    @display.print_class klass
  end

  ##
  # Records the parsing of +constant+

  def add_constant constant
    @display.print_constant constant
  end

  ##
  # Records the parsing of +file+

  def add_file(file)
    @files_so_far += 1
    @display.print_file @files_so_far, file
  end

  ##
  # Records the parsing of +method+

  def add_method(method)
    @display.print_method method
  end

  ##
  # Records the parsing of a module +mod+

  def add_module(mod)
    @display.print_module mod
  end

  ##
  # Call this to mark the beginning of parsing for display purposes

  def begin_adding
    @display.begin_adding
  end

  ##
  # Calculates documentation totals and percentages

  def calculate
    return if @percent_doc

    ucm = RDoc::TopLevel.unique_classes_and_modules
    constants = []
    ucm.each { |cm| constants.concat cm.constants }

    methods = []
    ucm.each { |cm| methods.concat cm.method_list }

    attributes = []
    ucm.each { |cm| attributes.concat cm.attributes }

    @num_attributes, @undoc_attributes = doc_stats attributes
    @num_classes,    @undoc_classes    = doc_stats RDoc::TopLevel.unique_classes
    @num_constants,  @undoc_constants  = doc_stats constants
    @num_methods,    @undoc_methods    = doc_stats methods
    @num_modules,    @undoc_modules    = doc_stats RDoc::TopLevel.unique_modules

    @num_items =
      @num_attributes +
      @num_classes +
      @num_constants +
      @num_methods +
      @num_modules

    @undoc_items =
      @undoc_attributes +
      @undoc_classes +
      @undoc_constants +
      @undoc_methods +
      @undoc_modules

    @doc_items = @num_items - @undoc_items

    @fully_documented = (@num_items - @doc_items) == 0

    @percent_doc = @doc_items.to_f / @num_items * 100 if @num_items.nonzero?
  end

  ##
  # Returns the length and number of undocumented items in +collection+.

  def doc_stats collection
    [collection.length, collection.count { |item| not item.documented? }]
  end

  ##
  # Call this to mark the end of parsing for display purposes

  def done_adding
    @display.done_adding
  end

  ##
  # The documentation status of this project.  +true+ when 100%, +false+ when
  # less than 100% and +nil+ when unknown.
  #
  # Set by calling #calculate

  def fully_documented?
    @fully_documented
  end

  ##
  # Returns a report on which items are not documented

  def report
    report = []

    calculate

    if @num_items == @doc_items then
      report << '100% documentation!'
      report << nil
      report << 'Great Job!'

      return report.join "\n"
    end

    report << 'The following items are not documented:'
    report << nil

    ucm = RDoc::TopLevel.unique_classes_and_modules

    ucm.sort.each do |cm|
      type = case cm # TODO #definition
             when RDoc::NormalClass  then 'class'
             when RDoc::SingleClass  then 'class <<'
             when RDoc::NormalModule then 'module'
             end

      if cm.fully_documented? then
        next
      elsif cm.in_files.empty? or
            (cm.constants.empty? and cm.method_list.empty?) then
        report << "# #{type} #{cm.full_name} is referenced but empty."
        report << '#'
        report << '# It probably came from another project.  ' \
                  'I\'m sorry I\'m holding it against you.'
        report << nil

        next
      elsif cm.documented? then
        report << "#{type} #{cm.full_name} # is documented"
      else
        report << '# in files:'

        cm.in_files.each do |file|
          report << "#   #{file.full_name}"
        end

        report << nil

        report << "#{type} #{cm.full_name}"
      end

      unless cm.constants.empty? then
        report << nil

        cm.each_constant do |constant|
          # TODO constant aliases are listed in the summary but not reported
          # figure out what to do here
          next if constant.documented? || constant.is_alias_for
          report << "  # in file #{constant.file.full_name}"
          report << "  #{constant.name} = nil"
        end
      end

      unless cm.attributes.empty? then
        report << nil

        cm.each_attribute do |attr|
          next if attr.documented?
          report << "  #{attr.definition} #{attr.name} " \
                    "# in file #{attr.file.full_name}"
        end
      end

      unless cm.method_list.empty? then
        report << nil

        cm.each_method do |method|
          next if method.documented?
          report << "  # in file #{method.file.full_name}"
          report << "  def #{method.name}#{method.params}; end"
          report << nil
        end
      end

      report << 'end'
      report << nil
    end

    report.join "\n"
  end

  ##
  # Returns a summary of the collected statistics.

  def summary
    calculate

    num_width = [@num_files, @num_items].max.to_s.length
    nodoc_width = [
      @undoc_attributes,
      @undoc_classes,
      @undoc_constants,
      @undoc_items,
      @undoc_methods,
      @undoc_modules,
    ].max.to_s.length

    report = []
    report << 'Files:      %*d' % [num_width, @num_files]

    report << nil

    report << 'Classes:    %*d (%*d undocumented)' % [
      num_width, @num_classes, nodoc_width, @undoc_classes]
    report << 'Modules:    %*d (%*d undocumented)' % [
      num_width, @num_modules, nodoc_width, @undoc_modules]
    report << 'Constants:  %*d (%*d undocumented)' % [
      num_width, @num_constants, nodoc_width, @undoc_constants]
    report << 'Attributes: %*d (%*d undocumented)' % [
      num_width, @num_attributes, nodoc_width, @undoc_attributes]
    report << 'Methods:    %*d (%*d undocumented)' % [
      num_width, @num_methods, nodoc_width, @undoc_methods]

    report << nil

    report << 'Total:      %*d (%*d undocumented)' % [
      num_width, @num_items, nodoc_width, @undoc_items]

    report << '%6.2f%% documented' % @percent_doc if @percent_doc
    report << nil
    report << 'Elapsed: %0.1fs' % (Time.now - @start)

    report.join "\n"
  end

  autoload :Quiet,   'rdoc/stats/quiet'
  autoload :Normal,  'rdoc/stats/normal'
  autoload :Verbose, 'rdoc/stats/verbose'

end

