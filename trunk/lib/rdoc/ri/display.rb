require 'rdoc/ri'

##
# This is a kind of 'flag' module. If you want to write your own 'ri' display
# module (perhaps because you're writing an IDE), you write a class which
# implements the various 'display' methods in RDoc::RI::DefaultDisplay, and
# include the RDoc::RI::Display module in that class.
#
# To access your class from the command line, you can do
#
#    ruby -r <your source file>  ../ri ....

module RDoc::RI::Display

  @@display_class = nil

  def self.append_features(display_class)
    @@display_class = display_class
  end

  def self.new(*args)
    @@display_class.new(*args)
  end

end

##
# A paging display module. Uses the RDoc::RI::Formatter class to do the actual
# presentation.

class RDoc::RI::DefaultDisplay

  include RDoc::RI::Display

  def initialize(formatter, width, use_stdout, output = $stdout)
    @use_stdout = use_stdout
    @formatter = formatter.new output, width, "     "
  end

  ##
  # Display information about +klass+.  Fetches additional information from
  # +ri_reader+ as necessary.

  def display_class_info(klass, ri_reader)
    page do
      superclass = klass.superclass_string

      if superclass
        superclass = " < " + superclass
      else
        superclass = ""
      end

      @formatter.draw_line(klass.display_name + ": " +
                           klass.full_name + superclass)

      display_flow(klass.comment)
      @formatter.draw_line

      unless klass.includes.empty?
        @formatter.blankline
        @formatter.display_heading("Includes:", 2, "")
        incs = []
        klass.includes.each do |inc|
          inc_desc = ri_reader.find_class_by_name(inc.name)
          if inc_desc
            str = inc.name + "("
            str << inc_desc.instance_methods.map{|m| m.name}.join(", ")
            str << ")"
            incs << str
          else
            incs << inc.name
          end
      end
        @formatter.wrap(incs.sort.join(', '))
      end

      unless klass.constants.empty?
        @formatter.blankline
        @formatter.display_heading("Constants:", 2, "")

        constants = klass.constants.sort_by { |constant| constant.name }

        constants.each do |constant|
          if constant.comment then
            @formatter.wrap "#{constant.name}:"

            @formatter.indent do
              @formatter.display_flow constant.comment
            end
          else
            @formatter.wrap constant.name
          end
        end
      end

      class_data = [
        :class_methods,
        :class_method_extensions,
        :instance_methods,
        :instance_method_extensions,
      ]

      class_data.each do |data_type|
        data = klass.send data_type

        unless data.empty? then
          @formatter.blankline

          heading = data_type.to_s.split('_').join(' ').capitalize << ':'
          @formatter.display_heading heading, 2, ''

          data = data.map { |item| item.name }.sort.join ', '
          @formatter.wrap data
        end
      end

      unless klass.attributes.empty? then
        @formatter.blankline

        @formatter.display_heading 'Attributes:', 2, ''

        attributes = klass.attributes.sort_by { |attribute| attribute.name }

        attributes.each do |attribute|
          if attribute.comment then
            @formatter.wrap "#{attribute.name} (#{attribute.rw}):"
            @formatter.indent do
              @formatter.display_flow attribute.comment
            end
          else
            @formatter.wrap "#{attribute.name} (#{attribute.rw})"
          end
        end
      end
    end
  end

  ##
  # Display an Array of RDoc::Markup::Flow objects, +flow+.

  def display_flow(flow)
    if flow and not flow.empty? then
      @formatter.display_flow flow
    else
      @formatter.wrap '[no description]'
    end
  end

  ##
  # Display information about +method+.

  def display_method_info(method)
    page do
      @formatter.draw_line(method.full_name)
      display_params(method)

      @formatter.draw_line
      display_flow(method.comment)

      if method.aliases and not method.aliases.empty? then
        @formatter.blankline
        aka = "(also known as #{method.aliases.map { |a| a.name }.join(', ')})"
        @formatter.wrap aka
      end
    end
  end

  ##
  # Display the list of +methods+.

  def display_method_list(methods)
    page do
      @formatter.wrap "More than one method matched your request.  You can refine your search by asking for information on one of:"

      @formatter.blankline

      @formatter.wrap methods.map { |m| m.full_name }.join(", ")
    end
  end

  ##
  # Display the params for +method+.

  def display_params(method)
    params = method.params

    if params[0,1] == "(" then
      if method.is_singleton
        params = method.full_name + params
      else
        params = method.name + params
      end
    end

    params.split(/\n/).each do |param|
      @formatter.wrap param
      @formatter.break_to_newline
    end

    if method.source_path then
      @formatter.blankline
      @formatter.wrap("Extension from #{method.source_path}")
    end
  end

  ##
  # List the classes in +classes+.

  def list_known_classes(classes)
    if classes.empty?
      warn_no_database
    else
      page do
        @formatter.draw_line "Known classes and modules"
        @formatter.blankline

        @formatter.wrap classes.sort.join(', ')
      end
    end
  end

  ##
  # Paginates output through a pager program.

  def page
    if pager = setup_pager then
      begin
        orig_output = @formatter.output
        @formatter.output = pager
        yield
      ensure
        @formatter.output = orig_output
        pager.close
      end
    else
      yield
    end
  rescue Errno::EPIPE
  end

  ##
  # Sets up a pager program to pass output through.

  def setup_pager
    unless @use_stdout then
      for pager in [ ENV['PAGER'], "less", "more", 'pager' ].compact.uniq
        return IO.popen(pager, "w") rescue nil
      end
      @use_stdout = true
      nil
    end
  end

  ##
  # Displays a message that describes how to build RI data.

  def warn_no_database
    output = @formatter.output

    output.puts "No ri data found"
    output.puts
    output.puts "If you've installed Ruby yourself, you need to generate documentation using:"
    output.puts
    output.puts "  make install-doc"
    output.puts
    output.puts "from the same place you ran `make` to build ruby."
    output.puts
    output.puts "If you installed Ruby from a packaging system, then you may need to"
    output.puts "install an additional package, or ask the packager to enable ri generation."
  end

end

