require 'rdoc/ri'

##
# This is a kind of 'flag' module. If you want to write your own 'ri' display
# module (perhaps because you'r writing an IDE or somesuch beast), you simply
# write a class which implements the various 'display' methods in
# 'DefaultDisplay', and include the 'RiDisplay' module in that class.
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

  def initialize(formatter, width, use_stdout)
    @use_stdout = use_stdout
    @formatter = formatter.new width, "     "
  end

  def display_method_info(method)
    page do
      @formatter.draw_line(method.full_name)
      display_params(method)
      @formatter.draw_line
      display_flow(method.comment)
      if method.aliases && !method.aliases.empty?
        @formatter.blankline
        aka = "(also known as "
        aka << method.aliases.map {|a| a.name }.join(", ")
        aka << ")"
        @formatter.wrap(aka)
      end
    end
  end

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
        len = 0
        klass.constants.each { |c| len = c.name.length if c.name.length > len }
        len += 2
        klass.constants.each do |c|
          @formatter.wrap(c.value,
                          @formatter.indent+((c.name+":").ljust(len)))
        end
      end

      unless klass.class_methods.empty?
        @formatter.blankline
        @formatter.display_heading("Class methods:", 2, "")
        @formatter.wrap(klass.class_methods.map{|m| m.name}.sort.join(', '))
      end

      unless klass.class_method_extensions.empty?
        @formatter.blankline
        @formatter.display_heading("Class Method Extensions:", 2, "")
        @formatter.wrap(klass.class_method_extensions.map{|m| m.name}.sort.join(', '))
      end

      unless klass.instance_methods.empty?
        @formatter.blankline
        @formatter.display_heading("Instance methods:", 2, "")
        @formatter.wrap(klass.instance_methods.map{|m| m.name}.sort.join(', '))
      end

      unless klass.instance_method_extensions.empty?
        @formatter.blankline
        @formatter.display_heading("Instance Method Extensions:", 2, "")
        @formatter.wrap(klass.instance_method_extensions.map{|m| m.name}.sort.join(', '))
      end

      unless klass.attributes.empty?
        @formatter.blankline
        @formatter.wrap("Attributes:", "")
        @formatter.wrap(klass.attributes.map{|a| a.name}.sort.join(', '))
      end
    end
  end

  ##
  # Display a list of method names

  def display_method_list(methods)
    page do
      puts "More than one method matched your request. You can refine"
      puts "your search by asking for information on one of:\n\n"
      @formatter.wrap(methods.map {|m| m.full_name} .join(", "))
    end
  end

  def display_class_list(namespaces)
    page do
      puts "More than one class or module matched your request. You can refine"
      puts "your search by asking for information on one of:\n\n"
      @formatter.wrap(namespaces.map {|m| m.full_name}.join(", "))
    end
  end

  def list_known_classes(classes)
    if classes.empty?
      warn_no_database
    else
      page do
        @formatter.draw_line("Known classes and modules")
        @formatter.blankline
        @formatter.wrap(classes.sort.join(", "))
      end
    end
  end

  def list_known_names(names)
    if names.empty?
      warn_no_database
    else
      page do
        names.each {|n| @formatter.raw_print_line(n)}
      end
    end
  end

  private

  def page
    if pager = setup_pager then
      begin
        orig_stdout = $stdout
        $stdout = pager
        yield
      ensure
        $stdout = orig_stdout
        pager.close
      end
    else
      yield
    end
  rescue Errno::EPIPE
  end

  def setup_pager
    unless @use_stdout then
      for pager in [ ENV['PAGER'], "less", "more", 'pager' ].compact.uniq
        return IO.popen(pager, "w") rescue nil
      end
      @use_stdout = true
      nil
    end
  end

  def display_params(method)
    params = method.params

    if params[0,1] == "("
      if method.is_singleton
        params = method.full_name + params
      else
        params = method.name + params
      end
    end
    params.split(/\n/).each do |p|
      @formatter.wrap(p)
      @formatter.break_to_newline
    end
    if method.source_path then
      @formatter.blankline
      @formatter.wrap("Extension from #{method.source_path}")
    end
  end

  def display_flow(flow)
    if !flow || flow.empty?
      @formatter.wrap("(no description...)")
    else
      @formatter.display_flow(flow)
    end
  end

  def warn_no_database
    puts "No ri data found"
    puts
    puts "If you've installed Ruby yourself, you need to generate documentation using:"
    puts
    puts "  make install-doc"
    puts
    puts "from the same place you ran `make` to build ruby."
    puts
    puts "If you installed Ruby from a packaging system, then you may need to"
    puts "install an additional package, or ask the packager to enable ri generation."
  end
end

