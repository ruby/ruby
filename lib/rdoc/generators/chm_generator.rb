require 'rdoc/generators/html_generator'

module Generators

  class CHMGenerator < HTMLGenerator

    HHC_PATH = "c:\\Program Files\\HTML Help Workshop\\hhc.exe"

    # Standard generator factory
    def CHMGenerator.for(options)
      CHMGenerator.new(options)
    end

    
    def initialize(*args)
      super
      @op_name = @options.op_name || "rdoc"
      check_for_html_help_workshop
    end

    def check_for_html_help_workshop
      stat = File.stat(HHC_PATH)
    rescue
      $stderr <<
	"\n.chm output generation requires that Microsoft's Html Help\n" <<
	"Workshop is installed. RDoc looks for it in:\n\n    " <<
	HHC_PATH <<
	"\n\nYou can download a copy for free from:\n\n" <<
	"    http://msdn.microsoft.com/library/default.asp?" <<
	"url=/library/en-us/htmlhelp/html/hwMicrosoftHTMLHelpDownloads.asp\n\n"
      
      exit 99
    end

    # Generate the html as normal, then wrap it
    # in a help project
    def generate(info)
      super
      @project_name = @op_name + ".hhp"
      create_help_project
    end

    # The project contains the project file, a table of contents
    # and an index
    def create_help_project
      create_project_file
      create_contents_and_index
      compile_project
    end

    # The project file links together all the various
    # files that go to make up the help.

    def create_project_file
      template = TemplatePage.new(RDoc::Page::HPP_FILE)
      values = { "title" => @options.title, "opname" => @op_name }
      files = []
      @files.each do |f|
	files << { "html_file_name" => f.path }
      end

      values['all_html_files'] = files
      
      File.open(@project_name, "w") do |f|
        template.write_html_on(f, values)
      end
    end

    # The contents is a list of all files and modules.
    # For each we include  as sub-entries the list
    # of methods they contain. As we build the contents
    # we also build an index file

    def create_contents_and_index
      contents = []
      index    = []

      (@files+@classes).sort.each do |entry|
	content_entry = { "c_name" => entry.name, "ref" => entry.path }
	index << { "name" => entry.name, "aref" => entry.path }

	internals = []

	methods = entry.build_method_summary_list(entry.path)

	content_entry["methods"] = methods unless methods.empty?
        contents << content_entry
	index.concat methods
      end

      values = { "contents" => contents }
      template = TemplatePage.new(RDoc::Page::CONTENTS)
      File.open("contents.hhc", "w") do |f|
	template.write_html_on(f, values)
      end

      values = { "index" => index }
      template = TemplatePage.new(RDoc::Page::CHM_INDEX)
      File.open("index.hhk", "w") do |f|
	template.write_html_on(f, values)
      end      
    end

    # Invoke the windows help compiler to compiler the project
    def compile_project
      system("\"#{HHC_PATH}\" #@project_name")
    end

  end


end
