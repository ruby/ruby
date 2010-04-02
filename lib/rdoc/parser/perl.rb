require 'rdoc/parser'

##
#
# This is an attamept to write a basic parser for Perl's
# POD (Plain old Documentation) format.  Ruby code must
# co-exist with Perl, and some tasks are easier in Perl
# than Ruby because of existing libraries.
#
# One difficult is that Perl POD has no means of identifying
# the classes (packages) and methods (subs) with which it
# is associated, it is more like literate programming in so
# far as it just happens to be in the same place as the code,
# but need not be.
#
# We would like to support all the markup the POD provides
# so that it will convert happily to HTML.  At the moment
# I don't think I can do that: time constraints.
#

class RDoc::Parser::PerlPOD < RDoc::Parser

  parse_files_matching(/.p[lm]$/)

  ##
  # Prepare to parse a perl file

  def initialize(top_level, file_name, content, options, stats)
    super

    preprocess = RDoc::Markup::PreProcess.new @file_name, @options.rdoc_include

    preprocess.handle @content do |directive, param|
      warn "Unrecognized directive '#{directive}' in #{@file_name}"
    end
  end

  ##
  # Extract the Pod(-like) comments from the code.
  # At its most basic there will ne no need to distinguish
  # between the different types of header, etc.
  #
  # This uses a simple finite state machine, in a very
  # procedural pattern. I could "replace case with polymorphism"
  # but I think it would obscure the intent, scatter the
  # code all over tha place.  This machine is necessary
  # because POD requires that directives be preceded by
  # blank lines, so reading line by line is necessary,
  # and preserving state about what is seen is necesary.

  def scan

    @top_level.comment ||= ""
    state=:code_blank
    line_number = 0
    line = nil

    # This started out as a really long nested case statement,
    # which also led to repetitive code.  I'd like to avoid that
    # so I'm using a "table" instead.

    # Firstly we need some procs to do the transition and processing
    # work.  Because these are procs they are closures, and they can
    # use variables in the local scope.
    #
    # First, the "nothing to see here" stuff.
    code_noop = lambda do
      if line =~ /^\s+$/
	state = :code_blank
      end
    end

    pod_noop = lambda do
      if line =~ /^\s+$/
	state = :pod_blank
      end
      @top_level.comment += filter(line)
    end

    begin_noop = lambda do
      if line =~ /^\s+$/
	state = :begin_blank
      end
      @top_level.comment += filter(line)
    end

    # Now for the blocks that process code and comments...

    transit_to_pod = lambda do
      case line
      when /^=(?:pod|head\d+)/
	state = :pod_no_blank
	@top_level.comment += filter(line)
      when /^=over/
	state = :over_no_blank
	@top_level.comment += filter(line)
      when /^=(?:begin|for)/
	state = :begin_no_blank
      end
    end

    process_pod = lambda do
      case line
      when  /^\s*$/
	state = :pod_blank
	@top_level.comment += filter(line)
      when /^=cut/
	state = :code_no_blank
      when /^=end/
	$stderr.puts "'=end' unexpected at #{line_number} in #{@file_name}"
      else
	@top_level.comment += filter(line)
      end
    end


    process_begin = lambda do
      case line
      when  /^\s*$/
	state = :begin_blank
	@top_level.comment += filter(line)
      when /^=end/
	state = :code_no_blank
      when /^=cut/
	$stderr.puts "'=cut' unexpected at #{line_number} in #{@file_name}"
      else
	@top_level.comment += filter(line)
      end

    end


    transitions = { :code_no_blank => code_noop,
                    :code_blank => transit_to_pod,
		    :pod_no_blank => pod_noop,
		    :pod_blank => process_pod,
		    :begin_no_blank => begin_noop,
		    :begin_blank => process_begin}
    @content.each_line do |l|
      line = l
      line_number += 1
      transitions[state].call
    end # each line

    @top_level
  end

  # Filter the perl markup that does the same as the rdoc
  # filtering.  Only basic for now. Will probably need a
  # proper parser to cope with C<<...>> etc
  def filter(comment)
    return '' if comment =~ /^=pod\s*$/
    comment.gsub!(/^=pod/, '==')
    comment.gsub!(/^=head(\d+)/) do
      "=" * $1.to_i
    end
    comment.gsub!(/=item/, '');
    comment.gsub!(/C<(.*?)>/, '<tt>\1</tt>');
    comment.gsub!(/I<(.*?)>/, '<i>\1</i>');
    comment.gsub!(/B<(.*?)>/, '<b>\1</b>');
    comment
  end

end

