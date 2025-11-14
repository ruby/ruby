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

# A NOTE ABOUT TERMS:
#
# Formerly: The documentation in this file used the term _template_ to refer to an ERB object.
#
# Now: The documentation in this file uses the term _template_
# to refer to the string input to ERB.new.
#
# The reason for the change:  When documenting the ERB executable erb,
# we need a term that refers to its string input;
# _source_ is not a good idea, because ERB#src means something entirely different;
# the two different sorts of sources would bring confusion.
#
# Therefore we use the term _template_ to refer to:
#
# - The string input to ERB.new
# - The string input to executable erb.
#

require 'erb/version'
require 'erb/compiler'
require 'erb/def_method'
require 'erb/util'

# :markup: markdown
#
# Class **ERB** (the name stands for **Embedded Ruby**)
# is an easy-to-use, but also very powerful, [template processor][template processor].
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
# - You can create a *template*: a plain-text string that includes specially formatted *tags*..
# - You can create an \ERB object to store the template.
# - You can call instance method ERB#result to get the *result*.
#
# \ERB supports tags of three kinds:
#
# - [Expression tags][expression tags]:
#   each begins with `'<%='`, ends with `'%>'`; contains a Ruby expression;
#   in the result, the value of the expression replaces the entire tag:
#
#         template = 'The magic word is <%= magic_word %>.'
#         erb = ERB.new(template)
#         magic_word = 'xyzzy'
#         erb.result(binding) # => "The magic word is xyzzy."
#
#     The above call to #result passes argument `binding`,
#     which contains the binding of variable `magic_word` to its string value `'xyzzy'`.
#
#     The below call to #result need not pass a binding,
#     because its expression `Date::DAYNAMES` is globally defined.
#
#         ERB.new('Today is <%= Date::DAYNAMES[Date.today.wday] %>.').result # => "Today is Monday."
#
# - [Execution tags][execution tags]:
#   each begins with `'<%'`, ends with `'%>'`; contains Ruby code to be executed:
#
#          template = '<% File.write("t.txt", "Some stuff.") %>'
#          ERB.new(template).result
#          File.read('t.txt') # => "Some stuff."
#
# - [Comment tags][comment tags]:
#   each begins with `'<%#'`, ends with `'%>'`; contains comment text;
#   in the result, the entire tag is omitted.
#
#          template = 'Some stuff;<%# Note to self: figure out what the stuff is. %> more stuff.'
#          ERB.new(template).result # => "Some stuff; more stuff."
#
# ## Some Simple Examples
#
# Here's a simple example of \ERB in action:
#
# ```
# template = 'The time is <%= Time.now %>.'
# erb = ERB.new(template)
# erb.result
# # => "The time is 2025-09-09 10:49:26 -0500."
# ```
#
# Details:
#
# 1. A plain-text string is assigned to variable `template`.
#    Its embedded [expression tag][expression tags] `'<%= Time.now %>'` includes a Ruby expression, `Time.now`.
# 2. The string is put into a new \ERB object, and stored in variable `erb`.
# 4. Method call `erb.result` generates a string that contains the run-time value of `Time.now`,
#    as computed at the time of the call.
#
# The
# \ERB object may be re-used:
#
# ```
# erb.result
# # => "The time is 2025-09-09 10:49:33 -0500."
# ```
#
# Another example:
#
# ```
# template = 'The magic word is <%= magic_word %>.'
# erb = ERB.new(template)
# magic_word = 'abracadabra'
# erb.result(binding)
# # => "The magic word is abracadabra."
# ```
#
# Details:
#
# 1. As before, a plain-text string is assigned to variable `template`.
#    Its embedded [expression tag][expression tags] `'<%= magic_word %>'` has a variable *name*, `magic_word`.
# 2. The string is put into a new \ERB object, and stored in variable `erb`;
#    note that `magic_word` need not be defined before the \ERB object is created.
# 3. `magic_word = 'abracadabra'` assigns a value to variable `magic_word`.
# 4. Method call `erb.result(binding)` generates a string
#    that contains the *value* of `magic_word`.
#
# As before, the \ERB object may be re-used:
#
# ```
# magic_word = 'xyzzy'
# erb.result(binding)
# # => "The magic word is xyzzy."
# ```
#
# ## Bindings
#
# A call to method #result, which produces the formatted result string,
# requires a [Binding object][binding object] as its argument.
#
# The binding object provides the bindings for expressions in [expression tags][expression tags].
#
# There are three ways to provide the required binding:
#
# - [Default binding][default binding].
# - [Local binding][local binding].
# - [Augmented binding][augmented binding]
#
# ### Default Binding
#
# When you pass no `binding` argument to method #result,
# the method uses its default binding: the one returned by method #new_toplevel.
# This binding has the bindings defined by Ruby itself,
# which are those for Ruby's constants and variables.
#
# That binding is sufficient for an expression tag that refers only to Ruby's constants and variables;
# these expression tags refer only to Ruby's global constant `RUBY_COPYRIGHT` and global variable `$0`:
#
# ```
# template = <<TEMPLATE
# The Ruby copyright is <%= RUBY_COPYRIGHT.inspect %>.
# The current process is <%= $0 %>.
# TEMPLATE
# puts ERB.new(template).result
# The Ruby copyright is "ruby - Copyright (C) 1993-2025 Yukihiro Matsumoto".
# The current process is irb.
# ```
#
# (The current process is `irb` because that's where we're doing these examples!)
#
# ### Local Binding
#
# The default binding is *not* sufficient for an expression
# that refers to a a constant or variable that is not defined there:
#
# ```
# Foo = 1 # Defines local constant Foo.
# foo = 2 # Defines local variable foo.
# template = <<TEMPLATE
# The current value of constant Foo is <%= Foo %>.
# The current value of variable foo is <%= foo %>.
# The Ruby copyright is <%= RUBY_COPYRIGHT.inspect %>.
# The current process is <%= $0 %>.
# TEMPLATE
# erb = ERB.new(template)
# ```
#
# This call below raises `NameError` because although `Foo` and `foo` are defined locally,
# they are not defined in the default binding:
#
# ```
# erb.result # Raises NameError.
# ```
#
# To make the locally-defined constants and variables available,
# you can call #result with the local binding:
#
# ```
# puts erb.result(binding)
# The current value of constant Foo is 1.
# The current value of variable foo is 2.
# The Ruby copyright is "ruby - Copyright (C) 1993-2025 Yukihiro Matsumoto".
# The current process is irb.
# ```
#
# ### Augmented Binding
#
# Another way to make variable bindings (but not constant bindings) available
# is to use method #result_with_hash(hash);
# the passed hash has name/value pairs that are to be used to define and assign variables
# in a copy of the default binding:
#
# ```
# template = <<TEMPLATE
# The current value of variable bar is <%= bar %>.
# The current value of variable baz is <%= baz %>.
# The Ruby copyright is <%= RUBY_COPYRIGHT.inspect %>.
# The current process is <%= $0 %>.
# TEMPLATE
# erb = ERB.new(template)
# ```
#
# Both of these calls raise `NameError`, because `bar` and `baz`
# are not defined in either the default binding or the local binding.
#
# ```
# puts erb.result          # Raises NameError.
# puts erb.result(binding) # Raises NameError.
# ```
#
# This call passes a hash that causes `bar` and `baz` to be defined
# in a new binding (derived from #new_toplevel):
#
# ```
# hash = {bar: 3, baz: 4}
# puts erb.result_with_hash(hash)
# The current value of variable bar is 3.
# The current value of variable baz is 4.
# The Ruby copyright is "ruby - Copyright (C) 1993-2025 Yukihiro Matsumoto".
# The current process is irb.
# ```
#
# ## Tags
#
# The examples above use expression tags.
# These are the tags available in \ERB:
#
# - [Expression tag][expression tags]: the tag contains a Ruby expression;
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
# template = <<TEMPLATE
# <% if verbosity %>
# An error has occurred.
# <% else %>
# Oops!
# <% end %>
# TEMPLATE
# erb = ERB.new(template)
# verbosity = true
# erb.result(binding)
# # => "\nAn error has occurred.\n\n"
# verbosity = false
# erb.result(binding)
# # => "\nOops!\n\n"
# ```
#
# Note that the interleaved text may itself contain expression tags:
#
# Loop:
#
# ```
# template = <<TEMPLATE
# <% Date::ABBR_DAYNAMES.each do |dayname| %>
# <%= dayname %>
# <% end %>
# TEMPLATE
# ERB.new(template).result
# # => "\nSun\n\nMon\n\nTue\n\nWed\n\nThu\n\nFri\n\nSat\n\n"
# ```
#
# Other, non-control, lines of Ruby code may be interleaved with the text,
# and the Ruby code may itself contain regular Ruby comments:
#
# ```
# template = <<TEMPLATE
# <% 3.times do %>
# <%= Time.now %>
# <% sleep(1) # Let's make the times different. %>
# <% end %>
# TEMPLATE
# ERB.new(template).result
# # => "\n2025-09-09 11:36:02 -0500\n\n\n2025-09-09 11:36:03 -0500\n\n\n2025-09-09 11:36:04 -0500\n\n\n"
# ```
#
# The execution tag may also contain multiple lines of code:
#
# ```
# template = <<TEMPLATE
# <%
#   (0..2).each do |i|
#     (0..2).each do |j|
# %>
# * <%=i%>,<%=j%>
# <%
#     end
#   end
# %>
# TEMPLATE
# ERB.new(template).result
# # => "\n* 0,0\n\n* 0,1\n\n* 0,2\n\n* 1,0\n\n* 1,1\n\n* 1,2\n\n* 2,0\n\n* 2,1\n\n* 2,2\n\n"
# ```
#
# #### Shorthand Format for Execution Tags
#
# You can use keyword argument `trim_mode: '%'` to enable a shorthand format for execution tags;
# this example uses the shorthand format `% _code_` instead of `<% _code_ %>`:
#
# ```
# template = <<TEMPLATE
# % priorities.each do |priority|
#   * <%= priority %>
# % end
# TEMPLATE
# erb = ERB.new(template, trim_mode: '%')
# priorities = [ 'Run Ruby Quiz',
#                'Document Modules',
#                'Answer Questions on Ruby Talk' ]
# puts erb.result(binding)
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
# template = <<TEMPLATE
# <% if true %>
# <%= RUBY_VERSION %>
# <% end %>
# TEMPLATE
# ERB.new(template).result.lines.each {|line| puts line.inspect }
# "\n"
# "3.4.5\n"
# "\n"
# ```
#
# You can give `trim_mode: '-'`, you can suppress each blank line
# whose source line ends with `-%>` (instead of `%>`):
#
# ```
# template = <<TEMPLATE
# <% if true -%>
# <%= RUBY_VERSION %>
# <% end -%>
# TEMPLATE
# ERB.new(template, trim_mode: '-').result.lines.each {|line| puts line.inspect }
# "3.4.5\n"
# ```
#
# It is an error to use the trailing `'-%>'` notation without `trim_mode: '-'`:
#
# ```
# ERB.new(template).result.lines.each {|line| puts line.inspect } # Raises SyntaxError.
# ```
#
# #### Suppressing Unwanted Newlines
#
# Consider this template:
#
# ```
# template = <<TEMPLATE
# <% RUBY_VERSION %>
# <%= RUBY_VERSION %>
# foo <% RUBY_VERSION %>
# foo <%= RUBY_VERSION %>
# TEMPLATE
# ```
#
# With keyword argument `trim_mode` not given, all newlines go into the result:
#
# ```
# ERB.new(template).result.lines.each {|line| puts line.inspect }
# "\n"
# "3.4.5\n"
# "foo \n"
# "foo 3.4.5\n"
# ```
#
# You can give `trim_mode: '>'` to suppress the trailing newline
# for each line that ends with `'%>'` (regardless of its beginning):
#
# ```
# ERB.new(template, trim_mode: '>').result.lines.each {|line| puts line.inspect }
# "3.4.5foo foo 3.4.5"
# ```
#
# You can give `trim_mode: '<>'` to suppress the trailing newline
# for each line that both begins with `'<%'` and ends with `'%>'`:
#
# ```
# ERB.new(template, trim_mode: '<>').result.lines.each {|line| puts line.inspect }
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
# template = 'Some stuff;<%# Note to self: figure out what the stuff is. %> more stuff.'
# ERB.new(template).result # => "Some stuff; more stuff."
# ```
#
# A comment tag may appear anywhere in the template.
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
# An \ERB object has an [encoding][encoding],
# which is by default the encoding of the template string;
# the result string will also have that encoding.
#
# ```
# template = <<TEMPLATE
# <%# Comment. %>
# TEMPLATE
# erb = ERB.new(template)
# template.encoding   # => #<Encoding:UTF-8>
# erb.encoding        # => #<Encoding:UTF-8>
# erb.result.encoding # => #<Encoding:UTF-8>
# ```
#
# You can specify a different encoding by adding a [magic comment][magic comments]
# at the top of the given template:
#
# ```
# template = <<TEMPLATE
# <%#-*- coding: Big5 -*-%>
# <%# Comment. %>
# TEMPLATE
# erb = ERB.new(template)
# template.encoding   # => #<Encoding:UTF-8>
# erb.encoding        # => #<Encoding:Big5>
# erb.result.encoding # => #<Encoding:Big5>
# ```
#
# ## Error Reporting
#
# Consider this template (containing an error):
#
# ```
# template = '<%= nosuch %>'
# erb = ERB.new(template)
# ```
#
# When \ERB reports an error,
# it includes a file name (if available) and a line number;
# the file name comes from method #filename, the line number from method #lineno.
#
# Initially, those values are `nil` and `0`, respectively;
# these initial values are reported as `'(erb)'` and `1`, respectively:
#
# ```
# erb.filename # => nil
# erb.lineno   # => 0
# erb.result
# (erb):1:in '<main>': undefined local variable or method 'nosuch' for main (NameError)
# ```
#
# You can use methods #filename= and #lineno= to assign values
# that are more meaningful in your context:
#
# ```
# erb.filename = 't.txt'
# erb.lineno = 555
# erb.result
# t.txt:556:in '<main>': undefined local variable or method 'nosuch' for main (NameError)
# ```
#
# You can use method #location= to set both values:
#
# ```
# erb.location = ['u.txt', 999]
# erb.result
# u.txt:1000:in '<main>': undefined local variable or method 'nosuch' for main (NameError)
# ```
#
# ## Plain Text with Embedded Ruby
#
# Here's a plain-text template;
# it uses the literal notation `'%q{ ... }'` to define the template
# (see [%q literals][%q literals]);
# this avoids problems with backslashes.
#
# ```
# template = %q{
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
# Finally, create the \ERB object and get the result
#
# ```
# erb = ERB.new(template, trim_mode: '%<>')
# puts erb.result(binding)
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
# ## HTML with Embedded Ruby
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
# template = <<TEMPLATE
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
# TEMPLATE
# ```
#
# Finally, create the \ERB object and get the result (omitting some blank lines):
#
# ```
# erb = ERB.new(template)
# puts erb.result(toy.get_binding)
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
# [%q literals]: https://docs.ruby-lang.org/en/master/syntax/literals_rdoc.html#label-25q-3A+Non-Interpolable+String+Literals
# [augmented binding]: rdoc-ref:ERB@Augmented+Binding
# [binding object]: https://docs.ruby-lang.org/en/master/Binding.html
# [comment tags]: rdoc-ref:ERB@Comment+Tags
# [default binding]: rdoc-ref:ERB@Default+Binding
# [encoding]: https://docs.ruby-lang.org/en/master/Encoding.html
# [execution tags]: rdoc-ref:ERB@Execution+Tags
# [expression tags]: rdoc-ref:ERB@Expression+Tags
# [kernel#binding]: https://docs.ruby-lang.org/en/master/Kernel.html#method-i-binding
# [local binding]: rdoc-ref:ERB@Local+Binding
# [magic comments]: https://docs.ruby-lang.org/en/master/syntax/comments_rdoc.html#label-Magic+Comments
# [rdoc]: https://ruby.github.io/rdoc
# [sprintf]: https://docs.ruby-lang.org/en/master/Kernel.html#method-i-sprintf
# [template engines]: https://www.ruby-toolbox.com/categories/template_engines
# [template processor]: https://en.wikipedia.org/wiki/Template_processor
#
class ERB
  # :markup: markdown
  #
  # :call-seq:
  #   self.version -> string
  #
  # Returns the string \ERB version.
  def self.version
    VERSION
  end

  # :markup: markdown
  #
  # :call-seq:
  #   ERB.new(template, trim_mode: nil, eoutvar: '_erbout')
  #
  # Returns a new \ERB object containing the given string +template+.
  #
  # For details about `template`, its embedded tags, and generated results, see ERB.
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
  # that method #result uses to construct its result string;
  # see #src.
  #
  # This is useful when you need to run multiple \ERB templates through the same binding
  # and/or when you want to control where output ends up.
  #
  # It's good practice to choose a variable name that begins with an underscore: `'_'`.
  #
  # [blank line control]: rdoc-ref:ERB@Suppressing+Unwanted+Blank+Lines
  # [combine trim modes]: rdoc-ref:ERB@Combining+Trim+Modes
  # [newline control]: rdoc-ref:ERB@Suppressing+Unwanted+Newlines
  # [shorthand format]: rdoc-ref:ERB@Shorthand+Format+for+Execution+Tags
  #
  def initialize(str, trim_mode: nil, eoutvar: '_erbout')
    compiler = make_compiler(trim_mode)
    set_eoutvar(compiler, eoutvar)
    @src, @encoding, @frozen_string = *compiler.compile(str)
    @filename = nil
    @lineno = 0
    @_init = self.class.singleton_class
  end

  # :markup: markdown
  #
  # :call-seq:
  #   make_compiler -> erb_compiler
  #
  # Returns a new ERB::Compiler with the given `trim_mode`;
  # for `trim_mode` values, see ERB.new:
  #
  # ```
  # ERB.new('').make_compiler(nil)
  # # => #<ERB::Compiler:0x000001cff9467678 @insert_cmd="print", @percent=false, @post_cmd=[], @pre_cmd=[], @put_cmd="print", @trim_mode=nil>
  # ```
  #
  def make_compiler(trim_mode)
    ERB::Compiler.new(trim_mode)
  end

  # :markup: markdown
  #
  # Returns the Ruby code that, when executed, generates the result;
  # the code is executed by method #result,
  # and by its wrapper methods #result_with_hash and #run:
  #
  # ```
  # template = 'The time is <%= Time.now %>.'
  # erb = ERB.new(template)
  # erb.src
  # # => "#coding:UTF-8\n_erbout = +''; _erbout.<< \"The time is \".freeze; _erbout.<<(( Time.now ).to_s); _erbout.<< \".\".freeze; _erbout"
  # erb.result
  # # => "The time is 2025-09-18 15:58:08 -0500."
  # ```
  #
  # In a more readable format:
  #
  # ```
  #   # puts erb.src.split('; ')
  #   # #coding:UTF-8
  #   # _erbout = +''
  #   # _erbout.<< "The time is ".freeze
  #   # _erbout.<<(( Time.now ).to_s)
  #   # _erbout.<< ".".freeze
  #   # _erbout
  # ```
  #
  # Variable `_erbout` is used to store the intermediate results in the code;
  # the name `_erbout` is the default in ERB.new,
  # and can be changed via keyword argument `eoutvar`:
  #
  # ```
  # erb = ERB.new(template, eoutvar: '_foo')
  # puts template.src.split('; ')
  # #coding:UTF-8
  # _foo = +''
  # _foo.<< "The time is ".freeze
  # _foo.<<(( Time.now ).to_s)
  # _foo.<< ".".freeze
  # _foo
  # ```
  #
  attr_reader :src

  # :markup: markdown
  #
  # Returns the encoding of `self`;
  # see [Encodings][encodings]:
  #
  # [encodings]: rdoc-ref:ERB@Encodings
  #
  attr_reader :encoding

  # :markup: markdown
  #
  # Sets or returns the file name to be used in reporting errors;
  # see [Error Reporting][error reporting].
  #
  # [error reporting]: rdoc-ref:ERB@Error+Reporting
  attr_accessor :filename

  # :markup: markdown
  #
  # Sets or returns the line number to be used in reporting errors;
  # see [Error Reporting][error reporting].
  #
  # [error reporting]: rdoc-ref:ERB@Error+Reporting
  attr_accessor :lineno

  # :markup: markdown
  #
  # :call-seq:
  #   location = [filename, lineno] => [filename, lineno]
  #   location = filename -> filename
  #
  # Sets the values of #filename and, if given, #lineno;
  # see [Error Reporting][error reporting].
  #
  # [error reporting]: rdoc-ref:ERB@Error+Reporting
  def location=((filename, lineno))
    @filename = filename
    @lineno = lineno if lineno
  end

  # :markup: markdown
  #
  # :call-seq:
  #   set_eoutvar(compiler, eoutvar = '_erbout') -> [eoutvar]
  #
  # Sets the `eoutvar` value in the ERB::Compiler object `compiler`;
  # returns a 1-element array containing the value of `eoutvar`:
  #
  # ```
  # template = ERB.new('')
  # compiler = template.make_compiler(nil)
  # pp compiler
  # #<ERB::Compiler:0x000001cff8a9aa00
  #  @insert_cmd="print",
  #  @percent=false,
  #  @post_cmd=[],
  #  @pre_cmd=[],
  #  @put_cmd="print",
  #  @trim_mode=nil>
  # template.set_eoutvar(compiler, '_foo') # => ["_foo"]
  # pp compiler
  # #<ERB::Compiler:0x000001cff8a9aa00
  #  @insert_cmd="_foo.<<",
  #  @percent=false,
  #  @post_cmd=["_foo"],
  #  @pre_cmd=["_foo = +''"],
  #  @put_cmd="_foo.<<",
  #  @trim_mode=nil>
  # ```
  #
  def set_eoutvar(compiler, eoutvar = '_erbout')
    compiler.put_cmd = "#{eoutvar}.<<"
    compiler.insert_cmd = "#{eoutvar}.<<"
    compiler.pre_cmd = ["#{eoutvar} = +''"]
    compiler.post_cmd = [eoutvar]
  end

  # :markup: markdown
  #
  # :call-seq:
  #   run(binding = new_toplevel) -> nil
  #
  # Like #result, but prints the result string (instead of returning it);
  # returns `nil`.
  def run(b=new_toplevel)
    print self.result(b)
  end

  # :markup: markdown
  #
  # :call-seq:
  #   result(binding = new_toplevel) -> new_string
  #
  # Returns the string result formed by processing \ERB tags found in the stored template in `self`.
  #
  # With no argument given, uses the default binding;
  # see [Default Binding][default binding].
  #
  # With argument `binding` given, uses the local binding;
  # see [Local Binding][local binding].
  #
  # See also #result_with_hash.
  #
  # [default binding]: rdoc-ref:ERB@Default+Binding
  # [local binding]: rdoc-ref:ERB@Local+Binding
  #
  def result(b=new_toplevel)
    unless @_init.equal?(self.class.singleton_class)
      raise ArgumentError, "not initialized"
    end
    eval(@src, b, (@filename || '(erb)'), @lineno)
  end

  # :markup: markdown
  #
  # :call-seq:
  #   result_with_hash(hash) -> new_string
  #
  # Returns the string result formed by processing \ERB tags found in the stored string in `self`;
  # see [Augmented Binding][augmented binding].
  #
  # See also #result.
  #
  # [augmented binding]: rdoc-ref:ERB@Augmented+Binding
  #
  def result_with_hash(hash)
    b = new_toplevel(hash.keys)
    hash.each_pair do |key, value|
      b.local_variable_set(key, value)
    end
    result(b)
  end

  # :markup: markdown
  #
  # :call-seq:
  #   new_toplevel(symbols) -> new_binding
  #
  # Returns a new binding based on `TOPLEVEL_BINDING`;
  # used to create a default binding for a call to #result.
  #
  # See [Default Binding][default binding].
  #
  # Argument `symbols` is an array of symbols;
  # each symbol `symbol` is defined as a new variable to hide and
  # prevent it from overwriting a variable of the same name already
  # defined within the binding.
  #
  # [default binding]: rdoc-ref:ERB@Default+Binding
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

  # :markup: markdown
  #
  # :call-seq:
  #   def_method(module, method_signature, filename = '(ERB)') -> method_name
  #
  # Creates and returns a new instance method in the given module `module`;
  # returns the method name as a symbol.
  #
  # The method is created from the given `method_signature`,
  # which consists of the method name and its argument names (if any).
  #
  # The `filename` sets the value of #filename;
  # see [Error Reporting][error reporting].
  #
  # [error reporting]: rdoc-ref:ERB@Error+Reporting
  #
  # ```
  # template = '<%= arg1 %> <%= arg2 %>'
  # erb = ERB.new(template)
  # MyModule = Module.new
  # erb.def_method(MyModule, 'render(arg1, arg2)') # => :render
  # class MyClass; include MyModule; end
  # MyClass.new.render('foo', 123)                      # => "foo 123"
  # ```
  #
  def def_method(mod, methodname, fname='(ERB)')
    src = self.src.sub(/^(?!#|$)/) {"def #{methodname}\n"} << "\nend\n"
    mod.module_eval do
      eval(src, binding, fname, -1)
    end
  end

  # :markup: markdown
  #
  # :call-seq:
  #    def_module(method_name = 'erb') -> new_module
  #
  # Returns a new nameless module that has instance method `method_name`.
  #
  # ```
  # template = '<%= arg1 %> <%= arg2 %>'
  # erb = ERB.new(template)
  # MyModule = template.def_module('render(arg1, arg2)')
  # class MyClass
  #   include MyModule
  # end
  # MyClass.new.render('foo', 123)
  # # => "foo 123"
  # ```
  #
  def def_module(methodname='erb')
    mod = Module.new
    def_method(mod, methodname, @filename || '(ERB)')
    mod
  end

  # :markup: markdown
  #
  # :call-seq:
  #   def_class(super_class = Object, method_name = 'result') -> new_class
  #
  # Returns a new nameless class whose superclass is `super_class`,
  # and which has instance method `method_name`.
  #
  # Create a template from HTML that has embedded expression tags that use `@arg1` and `@arg2`:
  #
  # ```
  # html = <<TEMPLATE
  # <html>
  # <body>
  #   <p><%= @arg1 %></p>
  #   <p><%= @arg2 %></p>
  # </body>
  # </html>
  # TEMPLATE
  # template = ERB.new(html)
  # ```
  #
  # Create a base class that has `@arg1` and `@arg2`:
  #
  # ```
  # class MyBaseClass
  #   def initialize(arg1, arg2)
  #     @arg1 = arg1
  #     @arg2 = arg2
  #   end
  # end
  # ```
  #
  # Use method #def_class to create a subclass that has method `:render`:
  #
  # ```
  # MySubClass = template.def_class(MyBaseClass, :render)
  # ```
  #
  # Generate the result:
  #
  # ```
  # puts MySubClass.new('foo', 123).render
  # <html>
  # <body>
  #   <p>foo</p>
  #   <p>123</p>
  # </body>
  # </html>
  # ```
  #
  def def_class(superklass=Object, methodname='result')
    cls = Class.new(superklass)
    def_method(cls, methodname, @filename || '(ERB)')
    cls
  end
end
