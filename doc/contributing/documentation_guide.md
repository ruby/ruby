# Documentation Guide

This guide discusses recommendations for documenting
classes, modules, and methods
in the Ruby core and in the Ruby standard library.

## Generating documentation

Most Ruby documentation lives in the source files and is written in
[RDoc format](https://ruby.github.io/rdoc/RDoc/MarkupReference.html).

Some pages live under the `doc` folder and can be written in either
`.rdoc` or `.md` format, determined by the file extension.

To generate the output of documentation changes in HTML in the
`{build folder}/.ext/html` directory, run the following inside your
build directory:

```sh
make html
```

If you don't have a build directory, follow the [quick start
guide](building_ruby.md#label-Quick+start+guide) up to step 4.

Then you can preview your changes by opening
`{build folder}/.ext/html/index.html` file in your browser.

## Goal

The goal of Ruby documentation is to impart the most important
and relevant information in the shortest time.
The reader should be able to quickly understand the usefulness
of the subject code and how to use it.

Providing too little information is bad, but providing unimportant
information or unnecessary examples is not good either.
Use your judgment about what the user needs to know.

## General Guidelines

- Keep in mind that the reader may not be fluent in \English.
- Write short declarative or imperative sentences.
- Group sentences into (ideally short) paragraphs,
  each covering a single topic.
- Organize material with
  [headings].
- Refer to authoritative and relevant sources using
  [links](https://ruby.github.io/rdoc/RDoc/MarkupReference.html#class-RDoc::MarkupReference-label-Links).
- Use simple verb tenses: simple present, simple past, simple future.
- Use simple sentence structure, not compound or complex structure.
- Avoid:
    - Excessive comma-separated phrases; consider a [list].
    - Idioms and culture-specific references.
    - Overuse of headings.
    - Using US-ASCII-incompatible characters in C source files;
      see [Characters](#label-Characters) below.

### Characters

Use only US-ASCII-compatible characters in a C source file.
(If you use other characters, the Ruby CI will gently let you know.)

If you want to put ASCII-incompatible characters into the documentation
for a C-coded class, module, or method, there are workarounds
involving new files `doc/*.rdoc`:

- For class `Foo` (defined in file `foo.c`),
  create file `doc/foo.rdoc`, declare `class Foo; end`,
  and place the class documentation above that declaration:

    ```ruby
    # Documentation for class Foo goes here.
    class Foo; end
    ```

- Similarly, for module `Bar` (defined in file `bar.c`),
  create file `doc/bar.rdoc`, declare `module Bar; end`,
  and place the module documentation above that declaration:

    ```ruby
    # Documentation for module Bar goes here.
    module Bar; end
    ```

- For a method, things are different.
  Documenting a method as above disables the "click to toggle source" feature
  in the rendered documentation.

    Therefore it's best to use file inclusion:

    - Retain the `call-seq` in the C code.
    - Use file inclusion (`:include:`) to include text from an .rdoc file.

    Example:

    ```c
    /*
     *  call-seq:
     *    each_byte {|byte| ... } -> self
     *    each_byte               -> enumerator
     *
     *  :include: doc/string/each_byte.rdoc
     *
     */
    ```

### \RDoc

Ruby is documented using RDoc.
For information on \RDoc syntax and features, see the
[RDoc Markup Reference](https://ruby.github.io/rdoc/RDoc/MarkupReference.html).

### Output from `irb`

For code examples, consider using interactive Ruby,
[irb](https://ruby-doc.org/stdlib/libdoc/irb/rdoc/IRB.html).

For a code example that includes `irb` output,
consider aligning `# => ...` in successive lines.
Alignment may sometimes aid readability:

```ruby
a = [1, 2, 3] #=> [1, 2, 3]
a.shuffle!    #=> [2, 3, 1]
a             #=> [2, 3, 1]
```

### Headings

Organize a long discussion for a class or module with [headings].

Do not use formal headings in the documentation for a method or constant.

In the rare case where heading-like structures are needed
within the documentation for a method or constant, use
[bold text](https://ruby.github.io/rdoc/RDoc/MarkupReference.html#class-RDoc::MarkupReference-label-Bold)
as pseudo-headings.

### Blank Lines

A blank line begins a new paragraph.

A [code block](https://ruby.github.io/rdoc/RDoc/MarkupReference.html#class-RDoc::MarkupReference-label-Code+Blocks)
or [list] should be preceded by and followed by a blank line.
This is unnecessary for the HTML output, but helps in the `ri` output.

### \Method Names

For a method name in text:

- For a method in the current class or module,
  use a double-colon for a singleton method,
  or a hash mark for an instance method:
  <tt>::bar</tt>, <tt>#baz</tt>.
- Otherwise, include the class or module name
  and use a dot for a singleton method,
  or a hash mark for an instance method:
  <tt>Foo.bar</tt>, <tt>Foo#baz</tt>.

### Embedded Code and Commands

Code or commands embedded in running text (i.e., not in a code block)
should marked up as
[monofont].

Code that is a simple string should include the quote marks.

### Auto-Linking

Most often, the name of a class, module, or method
is auto-linked:

```rdoc
- Float.
- Enumerable.
- File.new
- File#read.
```

renders as:

> - Float.
> - Enumerable.
> - File.new
> - File#read.

In general, \RDoc's auto-linking should not be suppressed.
For example, we should write just plain _Float_ (which is auto-linked):

```rdoc
Returns a Float.
```

which renders as:

> Returns a Float.

However, _do_ suppress auto-linking when the word in question
does not refer to a Ruby entity (e.g., some uses of _Class_ or _English_):

```rdoc
Class variables can be tricky.
```

renders as:

> Class variables can be tricky.

Also, _do_ suppress auto-linking when the word in question
refers to the current document
(e.g., _Float_ in the documentation for class Float).

In this case you may consider forcing the name to
[monofont],
which suppresses auto-linking, and also emphasizes that the word is a class name:

```rdoc
A +Float+ object represents ....
```

renders as:

> A `Float` object represents ....

For a _very_ few, _very_ often-discussed classes,
you might consider avoiding the capitalized class name altogether.
For example, for some mentions of arrays,
you might write simply the lowercase _array_.

Instead of:

```rdoc
For an empty Array, ....
```

which renders as:

> For an empty Array, ....

you might write:

```rdoc
For an empty array, ....
```

which renders as:

> For an empty array, ....

This more casual usage avoids both auto-linking and distracting font changes,
and is unlikely to cause confusion.

This principle may be usefully applied, in particular, for:

- An array.
- An integer.
- A hash.
- A string.

However, it should be applied _only_ when referring to an _instance_ of the class,
and _never_ when referring to the class itself.

### Explicit Links

When writing an explicit link, follow these guidelines.

#### +rdoc-ref+ Scheme

Use the +rdoc-ref+ scheme for:

- A link in core documentation to other core documentation.
- A link in core documentation to documentation in a standard library package.
- A link in a standard library package to other documentation in that same
  standard library package.

See section "+rdoc-ref+ Scheme" in [links].

#### URL-Based Link

Use a full URL-based link for:

- A link in standard library documentation to documentation in the core.
- A link in standard library documentation to documentation in a different
  standard library package.

Doing so ensures that the link will be valid even when the package documentation
is built independently (separately from the core documentation).

The link should lead to a target in https://docs.ruby-lang.org/en/master/.

Also use a full URL-based link for a link to an off-site document.

### Variable Names

The name of a variable (as specified in its call-seq) should be marked up as
[monofont].

Also, use monofont text for the name of a transient variable
(i.e., one defined and used only in the discussion, such as +n+).

### HTML Tags

In general, avoid using HTML tags (even in formats where it's allowed)
because `ri` (the Ruby Interactive reference tool)
may not render them properly.

### Tables

In particular, avoid building tables with HTML tags
(<tt><table></tt>, etc.).

Alternatives:

- A {verbatim text block}[https://ruby.github.io/rdoc/RDoc/MarkupReference.html#class-RDoc::MarkupReference-label-Verbatim+Text+Blocks],
  using spaces and punctuation to format the text;
  note that {text markup}[https://ruby.github.io/rdoc/RDoc/MarkupReference.html#class-RDoc::MarkupReference-label-Text+Markup]
  will not be honored:

    - Example {source}[https://github.com/ruby/ruby/blob/34d802f32f00df1ac0220b62f72605827c16bad8/file.c#L6570-L6596].
    - Corresponding {output}[rdoc-ref:File@Read-2FWrite+Mode].

- (Markdown format only): A {Github Flavored Markdown (GFM) table}[https://github.github.com/gfm/#tables-extension-],
  using special formatting for the text:

    - Example {source}[https://github.com/ruby/ruby/blob/34d802f32f00df1ac0220b62f72605827c16bad8/doc/contributing/glossary.md?plain=1].
    - Corresponding {output}[https://docs.ruby-lang.org/en/master/contributing/glossary_md.html].

## Documenting Classes and Modules

The general structure of the class or module documentation should be:

- Synopsis
- Common uses, with examples
- "What's Here" summary (optional)

### Synopsis

The synopsis is a short description of what the class or module does
and why the reader might want to use it.
Avoid details in the synopsis.

### Common Uses

Show common uses of the class or module.
Depending on the class or module, this section may vary greatly
in both length and complexity.

### What's Here Summary

The documentation for a class or module may include a "What's Here" section.

Guidelines:

- The section title is `What's Here`.
- Consider listing the parent class and any included modules; consider
  [links] to their "What's Here" sections if those exist.
- All methods mentioned in the left-pane table of contents
  should be listed (including any methods extended from another class).
- Attributes (which are not included in the TOC) may also be listed.
- Display methods as items in one or more bullet lists:

    - Begin each item with the method name, followed by a colon
      and a short description.
    - If the method has aliases, mention them in parentheses before the colon
      (and do not list the aliases separately).
    - Check the rendered documentation to determine whether \RDoc has recognized
      the method and linked to it;  if not, manually insert a
      [link](https://ruby.github.io/rdoc/RDoc/MarkupReference.html#class-RDoc::MarkupReference-label-Links).

- If there are numerous entries, consider grouping them into subsections with headings.
- If there are more than a few such subsections,
  consider adding a table of contents just below the main section title.

## Documenting Methods

### General Structure

The general structure of the method documentation should be:

- Calling sequence (for methods written in C).
- Synopsis (short description).
- In-brief examples (optional)
- Details and examples.
- Argument description (if necessary).
- Corner cases and exceptions.
- Related methods (optional).

### Calling Sequence (for methods written in C)

For methods written in Ruby, \RDoc documents the calling sequence automatically.

For methods written in C, \RDoc cannot determine what arguments
the method accepts, so those need to be documented using \RDoc directive
[`call-seq:`](https://ruby.github.io/rdoc/RDoc/MarkupReference.html#class-RDoc::MarkupReference-label-Directives+for+Method+Documentation).

For a singleton method, use the form:

```rdoc
class_name.method_name(method_args) {|block_args| ... } -> return_type
```

Example:

```rdoc
*  call-seq:
*    Hash.new(default_value = nil) -> new_hash
*    Hash.new {|hash, key| ... } -> new_hash
```

For an instance method, use the form
(omitting any prefix, just as RDoc does for a Ruby-coded method):

```rdoc
method_name(method_args) {|block_args| ... } -> return_type
```

For example, in Array, use:

```rdoc
*  call-seq:
*    count -> integer
*    count(obj) -> integer
*    count {|element| ... } -> integer
```

```rdoc
*  call-seq:
*    <=> other -> -1, 0, 1, or nil
```

For a binary-operator style method (e.g., Array#&),
cite `self` in the call-seq (not, e.g., `array` or `receiver`):

```rdoc
*  call-seq:
*    self & other_array -> new_array
```

Arguments:

- If the method does not accept arguments, omit the parentheses.
- If the method accepts optional arguments:

    - Separate each argument name and its default value with ` = `
      (equal-sign with surrounding spaces).
    - If the method has the same behavior with either an omitted
      or an explicit argument, use a `call-seq` with optional arguments.
      For example, use:

        ```rdoc
        *  call-seq:
        *    respond_to?(symbol, include_all = false) -> true or false
        ```

    - If the behavior is different with an omitted or an explicit argument,
      use a `call-seq` with separate lines.
      For example, in Enumerable, use:

        ```rdoc
        *  call-seq:
        *    max    -> element
        *    max(n) -> array
        ```

Block:

- If the method does not accept a block, omit the block.
- If the method accepts a block, the `call-seq` should have `{|args| ... }`,
  not `{|args| block }` or `{|args| code }`.
- If the method accepts a block, but returns an Enumerator when the block is omitted,
  the `call-seq` should show both forms:

    ```rdoc
    *  call-seq:
    *    array.select {|element| ... } -> new_array
    *    array.select -> new_enumerator
    ```

Return types:

- If the method can return multiple different types,
  separate the types with "or" and, if necessary, commas.
- If the method can return multiple types, use +object+.
- If the method returns the receiver, use +self+.
- If the method returns an object of the same class,
  prefix `new_` if and only if the object is not +self+;
  example: `new_array`.

Aliases:

- Omit aliases from the `call-seq`, unless the alias is an
  operator method. If listing both a regular method and an
  operator method in the `call-seq`, explain in the details and
  examples section when it is recommended to use the regular method
  and when it is recommended to use the operator method.

### Synopsis

The synopsis comes next, and is a short description of what the
method does and why you would want to use it.  Ideally, this
is a single sentence, but for more complex methods it may require
an entire paragraph.

For `Array#count`, the synopsis is:

> Returns a count of specified elements.

This is great as it is short and descriptive.  Avoid documenting
too much in the synopsis, stick to the most important information
for the benefit of the reader.

### In-Brief Examples

For a method whose documentation is lengthy,
consider adding an "in-brief" passage,
showing examples that summarize the method's uses.

The passage may answer some users' questions
(without their having to read long documentation);
see Array#[] and Array#[]=.

### Details and Examples

Most non-trivial methods benefit from examples, as well as details
beyond what is given in the synopsis.  In the details and examples
section, you can document how the method handles different types
of arguments, and provides examples on proper usage.  In this
section, focus on how to use the method properly, not on how the
method handles improper arguments or corner cases.

Not every behavior of a method requires an example.  If the method
is documented to return `self`, you don't need to provide an example
showing the return value is the same as the receiver.  If the method
is documented to return `nil`, you don't need to provide an example
showing that it returns `nil`.  If the details mention that for a
certain argument type, an empty array is returned, you don't need
to provide an example for that.

Only add an example if it provides the user additional information,
do not add an example if it provides the same information given
in the synopsis or details.  The purpose of examples is not to prove
what the details are stating.

Many methods that can take an optional block call the block if it is given,
but return a new Enumerator if the block is not given;
in that case, do not provide an example,
but do state the fact (with the auto-linking uppercase Enumerator):

```rdoc
*  With no block given, returns a new Enumerator.
```

### Argument Description (if necessary)

For methods that require arguments, if not obvious and not explicitly
mentioned in the details or implicitly shown in the examples, you can
provide details about the types of arguments supported.  When discussing
the types of arguments, use simple language even if less-precise, such
as "level must be an integer", not "level must be an Integer-convertible
object".  The vast majority of use will be with the expected type, not an
argument that is explicitly convertible to the expected type, and
documenting the difference is not important.

For methods that take blocks, it can be useful to document the type of
argument passed if it is not obvious, not explicitly mentioned in the
details, and not implicitly shown in the examples.

If there is more than one argument or block argument, use a
[labeled list](https://ruby.github.io/rdoc/RDoc/MarkupReference.html#class-RDoc::MarkupReference-label-Labeled+Lists).

### Corner Cases and Exceptions

For corner cases of methods, such as atypical usage, briefly mention
the behavior, but do not provide any examples.

Only document exceptions raised if they are not obvious.  For example,
if you have stated earlier than an argument type must be an integer,
you do not need to document that a `TypeError` is raised if a non-integer
is passed.  Do not provide examples of exceptions being raised unless
that is a common case, such as `Hash#fetch` raising a `KeyError`.

### Related Methods (optional)

In some cases, it is useful to document which methods are related to
the current method.  For example, documentation for `Hash#[]` might
mention `Hash#fetch` as a related method, and `Hash#merge` might mention
`Hash#merge!` as a related method.

- Consider which methods may be related
  to the current method, and if you think the reader would benefit from it,
  at the end of the method documentation, add a line starting with
  "Related: " (e.g. "Related: #fetch.").
- Don't list more than three related methods.
  If you think more than three methods are related,
  list the three you think are most important.
- Consider adding:

    - A phrase suggesting how the related method is similar to,
      or different from, the current method.
      See an example at Time#getutc.
    - Example code that illustrates the similarities and differences.
      See examples at Time#ctime, Time#inspect, Time#to_s.

### Methods Accepting Multiple Argument Types

For methods that accept multiple argument types, in some cases it can
be useful to document the different argument types separately.  It's
best to use a separate paragraph for each case you are discussing.

[headings]: https://ruby.github.io/rdoc/RDoc/MarkupReference.html#class-RDoc::MarkupReference-label-Headings
[list]: https://ruby.github.io/rdoc/RDoc/MarkupReference.html#class-RDoc::MarkupReference-label-Lists
[monofont]: https://ruby.github.io/rdoc/RDoc/MarkupReference.html#class-RDoc::MarkupReference-label-Monofont
