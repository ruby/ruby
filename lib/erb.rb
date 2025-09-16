# -*- coding: us-ascii -*-
# frozen_string_literal: true
# = ERB -- Ruby Templating
#
# Author:: Masatoshi SEKI
# Documentation:: James Edward Gray II, Gavin Sinclair, and Simon Chiang
#
# See ERB for primary documentation and ERB::Util for a couple of utility
# routines.
#
# Copyright (c) 1999-2000,2002,2003 Masatoshi SEKI
#
# You can redistribute it and/or modify it under the same terms as Ruby.

require 'erb/version'
require 'erb/compiler'
require 'erb/def_method'
require 'erb/util'

# :markup: markdown
#
# Class **ERB** (the name stands for **Embedded Ruby**)
# is an easy-to-use, but also very powerful, [template processor][template processor].
#
# Like method [sprintf][sprintf], \ERB can format run-time data into a string.
# \ERB, however,s is *much more powerful*.
#
# \ERB is commonly used to produce:
#
# - Customized or personalized email messages.
# - Customized or personalized web pages.
# - Software code (in code-generating applications).
#
# ## Usage
#
# Before you can use \ERB, you must first require it
# (examples on this page assume that this has been done):
#
# ```
# require 'erb'
# ```
#
# ## In Brief
#
# Here's how \ERB works:
#
# - You can create an \ERB object (a *template*) to store text that includes specially formatted *tags*.
# - You can call instance method ERB#result to get the *result*.
#
# \ERB supports tags of three kinds:
#
# - [Expression tags][expression tags]:
#   each begins with `'<%'`, ends with `'%>'`; contains a Ruby expression;
#   in the result, the value of the expression replaces the entire tag:
#
#         magic_word = 'xyzzy'
#         template.result(binding) # => "The magic word is xyzzy."
#
#         ERB.new('Today is <%= Date::DAYNAMES[Date.today.wday] %>.').result # => "Today is Monday."
#
#     The first call to #result passes argument `binding`,
#     which contains the binding of variable `magic_word` to its string value `'xyzzy'`.
#
#     The second call need not pass a binding,
#     because its expression `Date::DAYNAMES` is globally defined.
#
# - [Execution tags][execution tags]:
#   each begins with `'<%='`, ends with `'%>'`; contains Ruby code to be executed:
#
#          s = '<% File.write("t.txt", "Some stuff.") %>'
#          ERB.new(s).result
#          File.read('t.txt') # => "Some stuff."
#
# - [Comment tags][comment tags]:
#   each begins with `'<%#'`, ends with `'%>'`; contains comment text;
#   in the result, the entire tag is omitted.
#
#          s = 'Some stuff;<%# Note to self: figure out what the stuff is. %> more stuff.'
#          ERB.new(s).result # => "Some stuff; more stuff."
#
# ## Some Simple Examples
#
# Here's a simple example of \ERB in action:
#
# ```
# s = 'The time is <%= Time.now %>.'
# template = ERB.new(s)
# template.result
# # => "The time is 2025-09-09 10:49:26 -0500."
# ```
#
# Details:
#
# 1. A plain-text string is assigned to variable `s`.
#    Its embedded [expression tag][expression tags] `'<%= Time.now %>'` includes a Ruby expression, `Time.now`.
# 2. The string is put into a new \ERB object, and stored in variable `template`.
# 4. Method call `template.result` generates a string that contains the run-time value of `Time.now`,
#    as computed at the time of the call.
#
# The template may be re-used:
#
# ```
# template.result
# # => "The time is 2025-09-09 10:49:33 -0500."
# ```
#
# Another example:
#
# ```
# s = 'The magic word is <%= magic_word %>.'
# template = ERB.new(s)
# magic_word = 'abracadabra'
# # => "abracadabra"
# template.result(binding)
# # => "The magic word is abracadabra."
# ```
#
# Details:
#
# 1. As before, a plain-text string is assigned to variable `s`.
#    Its embedded [expression tag][expression tags] `'<%= magic_word %>'` has a variable *name*, `magic_word`.
# 2. The string is put into a new \ERB object, and stored in variable `template`;
#    note that `magic_word` need not be defined before the \ERB object is created.
# 3. `magic_word = 'abracadabra'` assigns a value to variable `magic_word`.
# 4. Method call `template.result(binding)` generates a string
#    that contains the *value* of `magic_word`.
#
# As before, the template may be re-used:
#
# ```
# magic_word = 'xyzzy'
# template.result(binding)
# # => "The magic word is xyzzy."
# ```
#
# ## Bindings
#
# The first example above passed no argument to method `result`;
# the second example passed argument `binding`.
#
# Here's why:
#
# - The first example has tag `<%= Time.now %>`,
#   which cites *globally-defined* constant `Time`;
#   the default `binding` (details not needed here) includes the binding of global constant `Time` to its value.
# - The second example has tag `<%= magic_word %>`,
#   which cites *locally-defined* variable `magic_word`;
#   the passed argument `binding` (which is simply a call to method [Kernel#binding][kernel#binding])
#   includes the binding of local variable `magic_word` to its value.
#
# ## Tags
#
# The examples above use expression tags.
# These are the tags available in \ERB:
#
# - [Expression tag][expression tags]: the tag contains a Ruby exprssion;
#   in the result, the entire tag is to be replaced with the run-time value of the expression.
# - [Execution tag][execution tags]: the tag contains Ruby code;
#   in the result, the entire tag is to be replaced with the run-time value of the code.
# - [Comment tag][comment tags]: the tag contains comment code;
#   in the result, the entire tag is to be omitted.
#
# ### Expression Tags
#
# You can embed a Ruby expression in a template using an *expression tag*.
#
# Its syntax is `<%= _expression_ %>`,
# where *expression* is any valid Ruby expression.
#
# When you call method #result,
# the method evaluates the expression and replaces the entire expression tag with the expression's value:
#
# ```
# ERB.new('Today is <%= Date::DAYNAMES[Date.today.wday] %>.').result
# # => "Today is Monday."
# ERB.new('Tomorrow will be <%= Date::DAYNAMES[Date.today.wday + 1] %>.').result
# # => "Tomorrow will be Tuesday."
# ERB.new('Yesterday was <%= Date::DAYNAMES[Date.today.wday - 1] %>.').result
# # => "Yesterday was Sunday."
# ```
#
# Note that whitespace before and after the expression
# is allowed but not required,
# and that such whitespace is stripped from the result.
#
# ```
# ERB.new('My appointment is on <%=Date::DAYNAMES[Date.today.wday + 2]%>.').result
# # => "My appointment is on Wednesday."
# ERB.new('My appointment is on <%=     Date::DAYNAMES[Date.today.wday + 2]    %>.').result
# # => "My appointment is on Wednesday."
# ```
#
# ### Execution Tags
#
# You can embed Ruby executable code in template using an *execution tag*.
#
# Its syntax is `<% _code_ %>`,
# where *code* is any valid Ruby code.
#
# When you call method #result,
# the method executes the code and removes the entire execution tag
# (generating no text in the result):
#
# ```
# ERB.new('foo <% Dir.chdir("C:/") %> bar').result # => "foo  bar"
# ```
#
# Whitespace before and after the embedded code is optional:
#
# ```
# ERB.new('foo <%Dir.chdir("C:/")%> bar').result   # => "foo  bar"
# ```
#
# You can interleave text with execution tags to form a control structure
# such as a conditional, a loop, or a `case` statements.
#
# Conditional:
#
# ```
# s = <<EOT
# <% if verbosity %>
# An error has occurred.
# <% else %>
# Oops!
# <% end %>
# EOT
# template = ERB.new(s)
# verbosity = true
# template.result(binding)
# # => "\nAn error has occurred.\n\n"
# verbosity = false
# template.result(binding)
# # => "\nOops!\n\n"
# ```
#
# Note that the interleaved text may itself contain expression tags:
#
# Loop:
#
# ```
# s = <<EOT
# <% Date::ABBR_DAYNAMES.each do |dayname| %>
# <%= dayname %>
# <% end %>
# EOT
# ERB.new(s).result
# # => "\nSun\n\nMon\n\nTue\n\nWed\n\nThu\n\nFri\n\nSat\n\n"
# ```
#
# Other, non-control, lines of Ruby code may be interleaved with the text,
# and the Ruby code may itself contain regular Ruby comments:
#
# ```
# s = <<EOT
# <% 3.times do %>
# <%= Time.now %>
# <% sleep(1) # Let's make the times different. %>
# <% end %>
# EOT
# ERB.new(s).result
# # => "\n2025-09-09 11:36:02 -0500\n\n\n2025-09-09 11:36:03 -0500\n\n\n2025-09-09 11:36:04 -0500\n\n\n"
# ```
#
# The execution tag may also contain multiple lines of code:
#
# ```
# s = <<EOT
# <%
#   (0..2).each do |i|
#     (0..2).each do |j|
# %>
# * <%=i%>,<%=j%>
# <%
#     end
#   end
# %>
# EOT
# ERB.new(s).result
# # => "\n* 0,0\n\n* 0,1\n\n* 0,2\n\n* 1,0\n\n* 1,1\n\n* 1,2\n\n* 2,0\n\n* 2,1\n\n* 2,2\n\n"
# ```
#
# #### Shorthand Format for Execution Tags
#
# You can use keyword argument `trim_mode: '%'` to enable a shorthand format for execution tags;
# this example uses the shorthand format `% _code_` instead of `<% _code_ %>`:
#
# ```
# s = <<EOT
# % priorities.each do |priority|
#   * <%= priority %>
# % end
# EOT
# template = ERB.new(s, trim_mode: '%')
# priorities = [ 'Run Ruby Quiz',
#                'Document Modules',
#                'Answer Questions on Ruby Talk' ]
# puts template.result(binding)
#   * Run Ruby Quiz
#   * Document Modules
#   * Answer Questions on Ruby Talk
# ```
#
# Note that in the shorthand format, the character `'%'` must be the first character in the code line
# (no leading whitespace).
#
# #### Suppressing Unwanted Blank Lines
#
# With keyword argument `trim_mode` not given,
# all blank lines go into the result:
#
# ```
# s = <<EOT
# <% if true %>
# <%= RUBY_VERSION %>
# <% end %>
# EOT
# ERB.new(s).result.lines.each {|line| puts line.inspect }
# "\n"
# "3.4.5\n"
# "\n"
# ```
#
# You can give `trim_mode: '-'`, you can suppress each blank line
# whose source line ends with `-%>` (instead of `%>`):
#
# ```
# s = <<EOT
# <% if true -%>
# <%= RUBY_VERSION %>
# <% end -%>
# EOT
# ERB.new(s, trim_mode: '-').result.lines.each {|line| puts line.inspect }
# "3.4.5\n"
# ```
#
# It is an error to use the trailing `'-%>'` notation without `trim_mode: '-'`:
#
# ```
# ERB.new(s).result.lines.each {|line| puts line.inspect } # Raises SyntaxError.
# ```
#
# #### Suppressing Unwanted Newlines
#
# Consider this input string:
#
# ```
# s = <<EOT
# <% RUBY_VERSION %>
# <%= RUBY_VERSION %>
# foo <% RUBY_VERSION %>
# foo <%= RUBY_VERSION %>
# EOT
# ```
#
# With keyword argument `trim_mode` not given, all newlines go into the result:
#
# ```
# ERB.new(s).result.lines.each {|line| puts line.inspect }
# "\n"
# "3.4.5\n"
# "foo \n"
# "foo 3.4.5\n"
# ```
#
# You can give `trim_mode: '>'` to suppress the trailing newline
# for each line that ends with `'%<'` (regardless of its beginning):
#
# ```
# ERB.new(s, trim_mode: '>').result.lines.each {|line| puts line.inspect }
# "3.4.5foo foo 3.4.5"
# ```
#
# You can give `trim_mode: '<>'` to suppress the trailing newline
# for each line that both begins with `'<%'` and ends with `'%>'`:
#
# ```
# ERB.new(s, trim_mode: '<>').result.lines.each {|line| puts line.inspect }
# "3.4.5foo \n"
# "foo 3.4.5\n"
# ```
#
# #### Combining Trim Modes
#
# You can combine certain trim modes:
#
# - `'%-'`: Enable shorthand and omit each blank line ending with `'-%>'`.
# - `'%>'`: Enable shorthand and omit newline for each line ending with `'%>'`.
# - `'%<>'`: Enable shorthand and omit newline for each line starting with `'<%'` and ending with `'%>'`.
#
# ### Comment Tags
#
# You can embed a comment in a template using a *comment tag*;
# its syntax is `<%# _text_ %>`,
# where *text* is the text of the comment.
#
# When you call method #result,
# it removes the entire comment tag
# (generating no text in the result).
#
# Example:
#
# ```
# s = 'Some stuff;<%# Note to self: figure out what the stuff is. %> more stuff.'
# ERB.new(s).result # => "Some stuff; more stuff."
# ```
#
# A comment tag may appear anywhere in the template text.
#
# Note that the beginning of the tag must be `'<%#'`, not `'<% #'`.
#
# In this example, the tag begins with `'<% #'`, and so is an execution tag, not a comment tag;
# the cited code consists entirely of a Ruby-style comment (which is of course ignored):
#
# ```
# ERB.new('Some stuff;<% # Note to self: figure out what the stuff is. %> more stuff.').result
# # => "Some stuff;"
# ```
#
# ## Encodings
#
# In general, an \ERB result string (or Ruby code generated by \ERB)
# has the same encoding as the string originally passed to ERB.new;
# see [Encoding][encoding].
#
# You can specify the output encoding by adding a [magic comment][magic comments]
# at the top of the given string:
#
# ```
# s = <<EOF
# <%#-*- coding: Big5 -*-%>
#
# Some text.
# EOF
# # => "<%#-*- coding: Big5 -*-%>\n\nSome text.\n"
# s.encoding
# # => #<Encoding:UTF-8>
# ERB.new(s).result.encoding
# # => #<Encoding:Big5>
# ```
#
# ## Plain Text Example
#
# Here's a plain-text string;
# it uses the literal notation `'%q{ ... }'` to define the string
# (see [%q literals][%q literals]);
# this avoids problems with backslashes.
#
# ```
# s = %q{
# From:  James Edward Gray II <james@grayproductions.net>
# To:  <%= to %>
# Subject:  Addressing Needs
#
# <%= to[/\w+/] %>:
#
# Just wanted to send a quick note assuring that your needs are being
# addressed.
#
# I want you to know that my team will keep working on the issues,
# especially:
#
# <%# ignore numerous minor requests -- focus on priorities %>
# % priorities.each do |priority|
#   * <%= priority %>
# % end
#
# Thanks for your patience.
#
# James Edward Gray II
# }
# ```
#
# The template will need these:
#
# ```
# to = 'Community Spokesman <spokesman@ruby_community.org>'
# priorities = [ 'Run Ruby Quiz',
#                'Document Modules',
#                'Answer Questions on Ruby Talk' ]
# ```
#
# Finally, make the template and get the result
#
# ```
# template = ERB.new(s, trim_mode: '%<>')
# puts template.result(binding)
#
# From:  James Edward Gray II <james@grayproductions.net>
# To:  Community Spokesman <spokesman@ruby_community.org>
# Subject:  Addressing Needs
#
# Community:
#
# Just wanted to send a quick note assuring that your needs are being
# addressed.
#
# I want you to know that my team will keep working on the issues,
# especially:
#
# * Run Ruby Quiz
# * Document Modules
# * Answer Questions on Ruby Talk
#
# Thanks for your patience.
#
# James Edward Gray II
# ```
#
# ## HTML Example
#
# This example shows an HTML template.
#
# First, here's a custom class, `Product`:
#
# ```
# class Product
#   def initialize(code, name, desc, cost)
#     @code = code
#     @name = name
#     @desc = desc
#     @cost = cost
#     @features = []
#   end
#
#   def add_feature(feature)
#     @features << feature
#   end
#
#   # Support templating of member data.
#   def get_binding
#     binding
#   end
#
# end
# ```
#
# The template below will need these values:
#
# ```
# toy = Product.new('TZ-1002',
#                   'Rubysapien',
#                   "Geek's Best Friend!  Responds to Ruby commands...",
#                   999.95
#                   )
# toy.add_feature('Listens for verbal commands in the Ruby language!')
# toy.add_feature('Ignores Perl, Java, and all C variants.')
# toy.add_feature('Karate-Chop Action!!!')
# toy.add_feature('Matz signature on left leg.')
# toy.add_feature('Gem studded eyes... Rubies, of course!')
# ```
#
# Here's the HTML:
#
# ```
# s = <<EOT
# <html>
#   <head><title>Ruby Toys -- <%= @name %></title></head>
#   <body>
#     <h1><%= @name %> (<%= @code %>)</h1>
#     <p><%= @desc %></p>
#     <ul>
#       <% @features.each do |f| %>
#         <li><b><%= f %></b></li>
#       <% end %>
#     </ul>
#     <p>
#       <% if @cost < 10 %>
#         <b>Only <%= @cost %>!!!</b>
#       <% else %>
#          Call for a price, today!
#       <% end %>
#     </p>
#   </body>
# </html>
# EOT
# ```
#
# Finally, build the template and get the result (omitting some blank lines):
#
# ```
# template = ERB.new(s)
# puts template.result(toy.get_binding)
# <html>
#   <head><title>Ruby Toys -- Rubysapien</title></head>
#   <body>
#     <h1>Rubysapien (TZ-1002)</h1>
#     <p>Geek's Best Friend!  Responds to Ruby commands...</p>
#     <ul>
#         <li><b>Listens for verbal commands in the Ruby language!</b></li>
#         <li><b>Ignores Perl, Java, and all C variants.</b></li>
#         <li><b>Karate-Chop Action!!!</b></li>
#         <li><b>Matz signature on left leg.</b></li>
#         <li><b>Gem studded eyes... Rubies, of course!</b></li>
#     </ul>
#     <p>
#          Call for a price, today!
#     </p>
#   </body>
# </html>
# ```
#
#
# ## Other Template Processors
#
# Various Ruby projects have their own template processors.
# The Ruby Processing System [RDoc][rdoc], for example, has one that can be used elsewhere.
#
# Other popular template processors may found in the [Template Engines][template engines] page
# of the Ruby Toolbox.
#
# [binding object]: https://docs.ruby-lang.org/en/master/Binding.html
# [comment tags]: rdoc-ref:ERB@Comment+Tags
# [encoding]: https://docs.ruby-lang.org/en/master/Encoding.html
# [execution tags]: rdoc-ref:ERB@Execution+Tags
# [expression tags]: rdoc-ref:ERB@Expression+Tags
# [kernel#binding]: https://docs.ruby-lang.org/en/master/Kernel.html#method-i-binding
# [%q literals]: https://docs.ruby-lang.org/en/master/syntax/literals_rdoc.html#label-25q-3A+Non-Interpolable+String+Literals
# [magic comments]: https://docs.ruby-lang.org/en/master/syntax/comments_rdoc.html#label-Magic+Comments
# [rdoc]: https://ruby.github.io/rdoc
# [sprintf]: https://docs.ruby-lang.org/en/master/Kernel.html#method-i-sprintf
# [template engines]: https://www.ruby-toolbox.com/categories/template_engines
# [template processor]: https://en.wikipedia.org/wiki/Template_processor
#
class ERB
  Revision = '$Date::                           $' # :nodoc: #'
  deprecate_constant :Revision

  # :markup: markdown
  #
  # :call-seq:
  #   self.version -> string
  #
  # Returns the string revision for \ERB:
  #
  # ```
  # ERB.version # => "4.0.4"
  # ```
  #
  def self.version
    VERSION
  end

  # :markup: markdown
  #
  # :call-seq:
  #   ERB.new(string, trim_mode: nil, eoutvar: '_erbout')
  #
  # Returns a new \ERB object containing the given +string+.
  #
  # For details about `string`, its embedded tags, and generated results, see ERB.
  #
  # **Keyword Argument `trim_mode`**
  #
  # You can use keyword argument `trim_mode: '%'`
  # to enable the [shorthand format][shorthand format] for execution tags.
  #
  # This value allows [blank line control][blank line control]:
  #
  # - `'-'`: Omit each blank line ending with `'%>'`.
  #
  # Other values allow [newline control][newline control]:
  #
  # - `'>'`: Omit newline for each line ending with `'%>'`.
  # - `'<>'`: Omit newline for each line starting with `'<%'` and ending with `'%>'`.
  #
  # You can also [combine trim modes][combine trim modes].
  #
  # **Keyword Argument `eoutvar`**
  #
  # The string value of keyword argument `eoutvar` specifies the name of the variable
  # that method #result uses to construct its result string.
  # This is useful when you need to run multiple \ERB templates through the same binding
  # and/or when you want to control where output ends up.
  #
  # It's good practice to choose a variable name that begins with an underscore: `'_'`.
  #
  # <b>Backward Compatibility</b>
  #
  # The calling sequence given above -- which is the one you should use --
  # is a simplified version of the complete formal calling sequence,
  # which is:
  #
  # ```
  # ERB.new(string,
  # safe_level=NOT_GIVEN, legacy_trim_mode=NOT_GIVEN, legacy_eoutvar=NOT_GIVEN,
  # trim_mode: nil, eoutvar: '_erbout')
  # ```
  #
  # The second, third, and fourth positional arguments (those in the second line above) are deprecated;
  # this method issues warnings if they are given.
  #
  # However, their values, if given, are handled thus:
  #
  # - `safe_level`: ignored.
  # - `legacy_trim_mode`: overrides keyword argument `trim_mode`.
  # - `legacy_eoutvar`: overrides keyword argument `eoutvar`.
  #
  # [blank line control]: rdoc-ref:ERB@Suppressing+Unwanted+Blank+Lines
  # [combine trim modes]: rdoc-ref:ERB@Combining+Trim+Modes
  # [newline control]: rdoc-ref:ERB@Suppressing+Unwanted+Newlines
  # [shorthand format]: rdoc-ref:ERB@Shorthand+Format+for+Execution+Tags
  #
  def initialize(str, safe_level=NOT_GIVEN, legacy_trim_mode=NOT_GIVEN, legacy_eoutvar=NOT_GIVEN, trim_mode: nil, eoutvar: '_erbout')
    # Complex initializer for $SAFE deprecation at [Feature #14256]. Use keyword arguments to pass trim_mode or eoutvar.
    if safe_level != NOT_GIVEN
      warn 'Passing safe_level with the 2nd argument of ERB.new is deprecated. Do not use it, and specify other arguments as keyword arguments.', uplevel: 1
    end
    if legacy_trim_mode != NOT_GIVEN
      warn 'Passing trim_mode with the 3rd argument of ERB.new is deprecated. Use keyword argument like ERB.new(str, trim_mode: ...) instead.', uplevel: 1
      trim_mode = legacy_trim_mode
    end
    if legacy_eoutvar != NOT_GIVEN
      warn 'Passing eoutvar with the 4th argument of ERB.new is deprecated. Use keyword argument like ERB.new(str, eoutvar: ...) instead.', uplevel: 1
      eoutvar = legacy_eoutvar
    end

    compiler = make_compiler(trim_mode)
    set_eoutvar(compiler, eoutvar)
    @src, @encoding, @frozen_string = *compiler.compile(str)
    @filename = nil
    @lineno = 0
    @_init = self.class.singleton_class
  end
  NOT_GIVEN = defined?(Ractor) ? Ractor.make_shareable(Object.new) : Object.new
  private_constant :NOT_GIVEN

  ##
  # Creates a new compiler for ERB.  See ERB::Compiler.new for details

  def make_compiler(trim_mode)
    ERB::Compiler.new(trim_mode)
  end

  # The Ruby code generated by ERB
  attr_reader :src

  # The encoding to eval
  attr_reader :encoding

  # The optional _filename_ argument passed to Kernel#eval when the ERB code
  # is run
  attr_accessor :filename

  # The optional _lineno_ argument passed to Kernel#eval when the ERB code
  # is run
  attr_accessor :lineno

  #
  # Sets optional filename and line number that will be used in ERB code
  # evaluation and error reporting. See also #filename= and #lineno=
  #
  #   erb = ERB.new('<%= some_x %>')
  #   erb.render
  #   # undefined local variable or method `some_x'
  #   #   from (erb):1
  #
  #   erb.location = ['file.erb', 3]
  #   # All subsequent error reporting would use new location
  #   erb.render
  #   # undefined local variable or method `some_x'
  #   #   from file.erb:4
  #
  def location=((filename, lineno))
    @filename = filename
    @lineno = lineno if lineno
  end

  #
  # Can be used to set _eoutvar_ as described in ERB::new.  It's probably
  # easier to just use the constructor though, since calling this method
  # requires the setup of an ERB _compiler_ object.
  #
  def set_eoutvar(compiler, eoutvar = '_erbout')
    compiler.put_cmd = "#{eoutvar}.<<"
    compiler.insert_cmd = "#{eoutvar}.<<"
    compiler.pre_cmd = ["#{eoutvar} = +''"]
    compiler.post_cmd = [eoutvar]
  end

  # Generate results and print them. (see ERB#result)
  def run(b=new_toplevel)
    print self.result(b)
  end

  #
  # Executes the generated ERB code to produce a completed template, returning
  # the results of that code.
  #
  # _b_ accepts a Binding object which is used to set the context of
  # code evaluation.
  #
  def result(b=new_toplevel)
    unless @_init.equal?(self.class.singleton_class)
      raise ArgumentError, "not initialized"
    end
    eval(@src, b, (@filename || '(erb)'), @lineno)
  end

  # Render a template on a new toplevel binding with local variables specified
  # by a Hash object.
  def result_with_hash(hash)
    b = new_toplevel(hash.keys)
    hash.each_pair do |key, value|
      b.local_variable_set(key, value)
    end
    result(b)
  end

  ##
  # Returns a new binding each time *near* TOPLEVEL_BINDING for runs that do
  # not specify a binding.

  def new_toplevel(vars = nil)
    b = TOPLEVEL_BINDING
    if vars
      vars = vars.select {|v| b.local_variable_defined?(v)}
      unless vars.empty?
        return b.eval("tap {|;#{vars.join(',')}| break binding}")
      end
    end
    b.dup
  end
  private :new_toplevel

  # Define _methodname_ as instance method of _mod_ from compiled Ruby source.
  #
  # example:
  #   filename = 'example.rhtml'   # 'arg1' and 'arg2' are used in example.rhtml
  #   erb = ERB.new(File.read(filename))
  #   erb.def_method(MyClass, 'render(arg1, arg2)', filename)
  #   print MyClass.new.render('foo', 123)
  def def_method(mod, methodname, fname='(ERB)')
    src = self.src.sub(/^(?!#|$)/) {"def #{methodname}\n"} << "\nend\n"
    mod.module_eval do
      eval(src, binding, fname, -1)
    end
  end

  # Create unnamed module, define _methodname_ as instance method of it, and return it.
  #
  # example:
  #   filename = 'example.rhtml'   # 'arg1' and 'arg2' are used in example.rhtml
  #   erb = ERB.new(File.read(filename))
  #   erb.filename = filename
  #   MyModule = erb.def_module('render(arg1, arg2)')
  #   class MyClass
  #     include MyModule
  #   end
  def def_module(methodname='erb')
    mod = Module.new
    def_method(mod, methodname, @filename || '(ERB)')
    mod
  end

  # Define unnamed class which has _methodname_ as instance method, and return it.
  #
  # example:
  #   class MyClass_
  #     def initialize(arg1, arg2)
  #       @arg1 = arg1;  @arg2 = arg2
  #     end
  #   end
  #   filename = 'example.rhtml'  # @arg1 and @arg2 are used in example.rhtml
  #   erb = ERB.new(File.read(filename))
  #   erb.filename = filename
  #   MyClass = erb.def_class(MyClass_, 'render()')
  #   print MyClass.new('foo', 123).render()
  def def_class(superklass=Object, methodname='result')
    cls = Class.new(superklass)
    def_method(cls, methodname, @filename || '(ERB)')
    cls
  end
end
