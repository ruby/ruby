# Documentation Guide

This guide discusses recommendations for documenting
classes, modules, and methods
in the Ruby core and in the Ruby standard library.

## Generating documentation

Most Ruby documentation lives in the source files and is written in
[RDoc format](rdoc-ref:RDoc::Markup).

Some pages live under the `doc` folder and can be written in either
`.rdoc` or `.md` format, determined by the file extension.

To generate the output of documentation changes in HTML in the
`{build folder}/.ext/html` directory, run the following inside your
build directory:

```sh
make html
```

Then you can preview your changes by opening
`{build folder}/.ext/html/index.html` file in your browser.


## Goal

The goal of Ruby documentation is to impart the most important
and relevant in the shortest time.
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
- Organize material with [headers](rdoc-ref:RDoc::Markup@Headers).
- Refer to authoritative and relevant sources using
  [links](rdoc-ref:RDoc::Markup@Links).
- Use simple verb tenses: simple present, simple past, simple future.
- Use simple sentence structure, not compound or complex structure.
- Avoid:
    - Excessive comma-separated phrases;
      consider a [list](rdoc-ref:RDoc::Markup@Simple+Lists).
    - Idioms and culture-specific references.
    - Overuse of headers.
    - Using US-ASCII-incompatible characters in C source files;
      see [Characters](#label-Characters) below.

### Characters

Use only US-ASCII-compatible characters in a C source file.
(If you use other characters, the Ruby CI will gently let you know.)

If want to put ASCII-incompatible characters into the documentation
for a C-coded class, module, or method, there are workarounds
involving new files `doc/*.rdoc`:

- For class `Foo` (defined in file `foo.c`),
  create file `doc/foo.rdoc`, declare `class Foo; end`,
  and place the class documentation above that declaration:

    ```ruby
    # Documentation for class Foo goes here.
    class Foo; end
    ```

- Similarly, for module `Bar` (defined in file `bar.c`,
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

    ```
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
[RDoc Markup Reference](rdoc-ref:RDoc::Markup@RDoc+Markup+Reference).

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

### Headers

Organize a long discussion with [headers](rdoc-ref:RDoc::Markup@Headers).

### Blank Lines

A blank line begins a new paragraph.

A [code block](rdoc-ref:RDoc::Markup@Paragraphs+and+Verbatim)
or [list](rdoc-ref:RDoc::Markup@Simple+Lists)
should be preceded by and followed by a blank line.
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

### Auto-Linking

In general, \RDoc's auto-linking should not be suppressed.
For example, we should write `Array`, not `\Array`.

We might consider whether to suppress when:

- The word in question does not refer to a Ruby entity
  (e.g., some uses of _Class_ or _English_).
- The reference is to the current class document
  (e.g., _Array_ in the documentation for class `Array`).
- The same reference is repeated many times
  (e.g., _RDoc_ on this page).

### HTML Tags

In general, avoid using HTML tags (even in formats where it's allowed)
because `ri` (the Ruby Interactive reference tool)
may not render them properly.

### Tables

In particular, avoid building tables with HTML tags
(<tt><table></tt>, etc.).

Alternatives are:

- The GFM (GitHub Flavored Markdown) table extension,
  which is enabled by default. See
  {GFM tables extension}[https://github.github.com/gfm/#tables-extension-].

- A {verbatim text block}[rdoc-ref:RDoc::MarkupReference@Verbatim+Text+Blocks],
  using spaces and punctuation to format the text.
  Note that {text markup}[rdoc-ref:RDoc::MarkupReference@Text+Markup]
  will not be honored.

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
  [links](rdoc-ref:RDoc::Markup@Links)
  to their "What's Here" sections if those exist.
- List methods as a bullet list:

    - Begin each item with the method name, followed by a colon
      and a short description.
    - If the method has aliases, mention them in parentheses before the colon
      (and do not list the aliases separately).
    - Check the rendered documentation to determine whether \RDoc has recognized
      the method and linked to it;  if not, manually insert a
      [link](rdoc-ref:RDoc::Markup@Links).

- If there are numerous entries, consider grouping them into subsections with headers.
- If there are more than a few such subsections,
  consider adding a table of contents just below the main section title.

## Documenting Methods

### General Structure

The general structure of the method documentation should be:

- Calling sequence (for methods written in C).
- Synopsis (short description).
- Details and examples.
- Argument description (if necessary).
- Corner cases and exceptions.
- Aliases.
- Related methods (optional).

### Calling Sequence (for methods written in C)

For methods written in Ruby, \RDoc documents the calling sequence automatically.

For methods written in C, \RDoc cannot determine what arguments
the method accepts, so those need to be documented using \RDoc directive
[`call-seq:`](rdoc-ref:RDoc::Markup@Method+arguments).

For a singleton method, use the form:

```
class_name.method_name(method_args) {|block_args| ... } -> return_type
```

Example:

```
*  call-seq:
*    Hash.new(default_value = nil) -> new_hash
*    Hash.new {|hash, key| ... } -> new_hash
```

For an instance method, use the form
(omitting any prefix, just as RDoc does for a Ruby-coded method):

```
method_name(method_args) {|block_args| ... } -> return_type
```
For example, in Array, use:

```
*  call-seq:
*    count -> integer
*    count(obj) -> integer
*    count {|element| ... } -> integer
```

```
* call-seq:
*    <=> other -> -1, 0, 1, or nil
```

Arguments:

- If the method does not accept arguments, omit the parentheses.
- If the method accepts optional arguments:

    - Separate each argument name and its default value with ` = `
      (equal-sign with surrounding spaces).
    - If the method has the same behavior with either an omitted
      or an explicit argument, use a `call-seq` with optional arguments.
      For example, use:

        ```
        respond_to?(symbol, include_all = false) -> true or false
        ```

    - If the behavior is different with an omitted or an explicit argument,
      use a `call-seq` with separate lines.
      For example, in Enumerable, use:

        ```
        *    max    -> element
        *    max(n) -> array
        ```

Block:

- If the method does not accept a block, omit the block.
- If the method accepts a block, the `call-seq` should have `{|args| ... }`,
  not `{|args| block }` or `{|args| code }`.

Return types:

- If the method can return multiple different types,
  separate the types with "or" and, if necessary, commas.
- If the method can return multiple types, use +object+.
- If the method returns the receiver, use +self+.
- If the method returns an object of the same class,
  prefix `new_` if an only if the object is not  +self+;
  example: `new_array`.

Aliases:

- Omit aliases from the `call-seq`, but mention them near the end (see below).

### Synopsis

The synopsis comes next, and is a short description of what the
method does and why you would want to use it.  Ideally, this
is a single sentence, but for more complex methods it may require
an entire paragraph.

For `Array#count`, the synopsis is:

```
Returns a count of specified elements.
```

This is great as it is short and descriptive.  Avoid documenting
too much in the synopsis, stick to the most important information
for the benefit of the reader.

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
[labeled list](rdoc-ref:RDoc::Markup@Labeled+Lists).

### Corner Cases and Exceptions

For corner cases of methods, such as atypical usage, briefly mention
the behavior, but do not provide any examples.

Only document exceptions raised if they are not obvious.  For example,
if you have stated earlier than an argument type must be an integer,
you do not need to document that a `TypeError` is raised if a non-integer
is passed.  Do not provide examples of exceptions being raised unless
that is a common case, such as `Hash#fetch` raising a `KeyError`.

### Aliases

Mention aliases in the form

```
// Array#find_index is an alias for Array#index.
```

### Related Methods (optional)

In some cases, it is useful to document which methods are related to
the current method.  For example, documentation for `Hash#[]` might
mention `Hash#fetch` as a related method, and `Hash#merge` might mention
`Hash#merge!` as a related method.

- Consider which methods may be related
  to the current method, and if you think the reader would benefit it,
  at the end of the method documentation, add a line starting with
  "Related: " (e.g. "Related: #fetch.").
- Don't list more than three related methods.
  If you think more than three methods are related,
  list the three you think are most important.
- Consider adding:

    - A phrase suggesting how the related method is similar to,
      or different from,the current method.
      See an example at Time#getutc.
    - Example code that illustrates the similarities and differences.
      See examples at Time#ctime, Time#inspect, Time#to_s.

### Methods Accepting Multiple Argument Types

For methods that accept multiple argument types, in some cases it can
be useful to document the different argument types separately.  It's
best to use a separate paragraph for each case you are discussing.
