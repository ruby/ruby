require 'rdoc/ri'

# readline support might not be present, so be careful
# when requiring it.
begin
  require('readline')
  require('abbrev')
  CAN_USE_READLINE = true # HACK use an RDoc namespace constant
rescue LoadError
  CAN_USE_READLINE = false
end

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

  def display_class_info(klass)
    page do
      superclass = klass.superclass

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
          incs << inc.name
        end

        @formatter.wrap(incs.sort.join(', '))
      end

      unless klass.constants.empty?
        @formatter.blankline
        @formatter.display_heading("Constants:", 2, "")

        constants = klass.constants.sort_by { |constant| constant.name }

        constants.each do |constant|
          @formatter.wrap "#{constant.name} = #{constant.value}"
          if constant.comment then
            @formatter.indent do
              @formatter.display_flow constant.comment
            end
          else
            @formatter.break_to_newline
          end
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
            @formatter.break_to_newline
          end
        end
      end

      return display_class_method_list(klass)
    end
  end

  ##
  # Given a Hash mapping a class' methods to method types (returned by
  # display_class_method_list), this method allows the user to
  # choose one of the methods.

  def get_class_method_choice(method_map)
    if CAN_USE_READLINE
      # prepare abbreviations for tab completion
      abbreviations = method_map.keys.abbrev
      Readline.completion_proc = proc do |string|
        abbreviations.values.uniq.grep(/^#{string}/)
      end
    end

    @formatter.raw_print_line "\nEnter the method name you want.\n"
    @formatter.raw_print_line "Class methods can be preceeded by '::' and instance methods by '#'.\n"

    if CAN_USE_READLINE
      @formatter.raw_print_line "You can use tab to autocomplete.\n"
      @formatter.raw_print_line "Enter a blank line to exit.\n"

      choice_string = Readline.readline(">> ").strip
    else
      @formatter.raw_print_line "Enter a blank line to exit.\n"
      @formatter.raw_print_line ">> "
      choice_string = $stdin.gets.strip
    end

    if choice_string == ''
      return nil
    else
      class_or_instance = method_map[choice_string]

      if class_or_instance
        # If the user's choice is not preceeded by a '::' or a '#', figure
        # out whether they want a class or an instance method and decorate
        # the choice appropriately.
        if(choice_string =~ /^[a-zA-Z]/)
          if(class_or_instance == :class)
            choice_string = "::#{choice_string}"
          else
            choice_string = "##{choice_string}"
          end
        end

        return choice_string
      else
        @formatter.raw_print_line "No method matched '#{choice_string}'.\n"
        return nil
      end
    end
  end


  ##
  # Display methods on +klass+
  # Returns a hash mapping method name to method contents (HACK?)

  def display_class_method_list(klass)
    method_map = {}

    class_data = [
                  :class_methods,
                  :class_method_extensions,
                  :instance_methods,
                  :instance_method_extensions,
                 ]

    class_data.each do |data_type|
      data = klass.send data_type

      unless data.nil? or data.empty? then
        @formatter.blankline

        heading = data_type.to_s.split('_').join(' ').capitalize << ':'
        @formatter.display_heading heading, 2, ''

        method_names = []
        data.each do |item|
          method_names << item.name

          if(data_type == :class_methods ||
             data_type == :class_method_extensions) then
            method_map["::#{item.name}"] = :class
            method_map[item.name] = :class
          else
            #
            # Since we iterate over instance methods after class methods,
            # an instance method always will overwrite the unqualified
            # class method entry for a class method of the same name.
            #
            method_map["##{item.name}"] = :instance
            method_map[item.name] = :instance
          end
        end
        method_names.sort!

        @formatter.wrap method_names.join(', ')
      end
    end

    method_map
  end
  private :display_class_method_list

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

      methods.each do |method|
        @formatter.raw_print_line "#{method.full_name} [#{method.source_path}]\n"
      end
    end
  end

  ##
  # Display a list of +methods+ and allow the user to select one of them.

  def display_method_list_choice(methods)
    page do
      @formatter.wrap "More than one method matched your request.  Please choose one of the possible matches."
      @formatter.blankline

      methods.each_with_index do |method, index|
        @formatter.raw_print_line "%3d %s [%s]\n" % [index + 1, method.full_name, method.source_path]
      end

      @formatter.raw_print_line ">> "

      choice = $stdin.gets.strip!

      if(choice == '')
        return
      end

      choice = choice.to_i

      if ((choice == 0) || (choice > methods.size)) then
        @formatter.raw_print_line "Invalid choice!\n"
      else
        method = methods[choice - 1]
        display_method_info(method)
      end
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

    @formatter.blankline
    @formatter.wrap("From #{method.source_path}")
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
