# = Synopsis
#
# This library allows command-line tools to encapsulate their usage
# as a comment at the top of the main file. Calling <tt>RDoc::usage</tt>
# then displays some or all of that comment, and optionally exits
# the program with an exit status. We always look for the comment
# in the main program file, so it is safe to call this method
# from anywhere in the executing program.
#
# = Usage
#
#   RDoc::usage( [ exit_status ], [ section, ...])
#   RDoc::usage_no_exit( [ section, ...])
#
# where:
#
# exit_status::
#     the integer exit code (default zero). RDoc::usage will exit
#     the calling program with this status.
#
# section::
#     an optional list of section names. If specified, only the
#     sections with the given names as headings will be output.
#     For example, this section is named 'Usage', and the next
#     section is named 'Examples'. The section names are case
#     insensitive.
#
# = Examples
#
#    # Comment block describing usage
#    # with (optional) section headings
#    # . . .
#
#    require 'rdoc/usage'
#
#    # Display all usage and exit with a status of 0
#
#    RDoc::usage
#
#    # Display all usage and exit with a status of 99
#
#    RDoc::usage(99)
#
#    # Display usage in the 'Summary' section only, then
#    # exit with a status of 99
#
#    RDoc::usage(99, 'Summary')
#
#    # Display information in the Author and Copyright
#    # sections, then exit 0.
#    
#    RDoc::usage('Author', 'Copyright')
#
#    # Display information in the Author and Copyright
#    # sections, but don't exit
#  
#    RDoc::usage_no_exit('Author', 'Copyright')
#
# = Author
#
# Dave Thomas, The Pragmatic Programmers, LLC
#
# = Copyright
#
# Copyright (c) 2004 Dave Thomas.
# Licensed under the same terms as Ruby
#

require 'rdoc/markup/simple_markup'
require 'rdoc/markup/simple_markup/to_flow'
require 'rdoc/ri/ri_formatter'
require 'rdoc/ri/ri_options'

module RDoc

  # Display usage information from the comment at the top of
  # the file. String arguments identify specific sections of the
  # comment to display. An optional integer first argument
  # specifies the exit status  (defaults to 0)

  def RDoc.usage(*args)
    exit_code = 0

    if args.size > 0
      status = args[0]
      if status.respond_to?(:to_int)
        exit_code = status.to_int
        args.shift
      end
    end

    # display the usage and exit with the given code
    usage_no_exit(*args)
    exit(exit_code)
  end

  # Display usage
  def RDoc.usage_no_exit(*args)
    main_program_file, = caller[-1].split(/:\d+/, 2)
    comment = File.open(main_program_file) do |file|
      find_comment(file)
    end

    comment = comment.gsub(/^\s*#/, '')

    markup = SM::SimpleMarkup.new
    flow_convertor = SM::ToFlow.new
    
    flow = markup.convert(comment, flow_convertor)

    format = "plain"

    unless args.empty?
      flow = extract_sections(flow, args)
    end

    options = RI::Options.instance
    if args = ENV["RI"]
      options.parse(args.split)
    end
    formatter = options.formatter.new(options, "")
    formatter.display_flow(flow)
  end

  ######################################################################

  private

  # Find the first comment in the file (that isn't a shebang line)
  # If the file doesn't start with a comment, report the fact
  # and return empty string

  def RDoc.gets(file)
    if (line = file.gets) && (line =~ /^#!/) # shebang
      throw :exit, find_comment(file)
    else
      line
    end
  end

  def RDoc.find_comment(file)
    catch(:exit) do
      # skip leading blank lines
      0 while (line = gets(file)) && (line =~ /^\s*$/)

      comment = []
      while line && line =~ /^\s*#/
        comment << line
        line = gets(file)
      end

      0 while line && (line = gets(file))
      return no_comment if comment.empty?
      return comment.join
    end
  end


  #####
  # Given an array of flow items and an array of section names, extract those
  # sections from the flow which have headings corresponding to
  # a section name in the list. Return them in the order
  # of names in the +sections+ array.

  def RDoc.extract_sections(flow, sections)
    result = []
    sections.each do |name|
      name = name.downcase
      copy_upto_level = nil

      flow.each do |item|
        case item
        when SM::Flow::H
          if copy_upto_level && item.level >= copy_upto_level
            copy_upto_level = nil
          else
            if item.text.downcase == name
              result << item
              copy_upto_level = item.level
            end
          end
        else
          if copy_upto_level
            result << item
          end
        end
      end
    end
    if result.empty?
      puts "Note to developer: requested section(s) [#{sections.join(', ')}] " +
           "not found"
      result = flow
    end
    result
  end

  #####
  # Report the fact that no doc comment count be found
  def RDoc.no_comment
    $stderr.puts "No usage information available for this program"
    ""
  end
end


if $0 == __FILE__

  RDoc::usage(*ARGV)

end
