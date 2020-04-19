# Standard Library Signatures Contribution Guide

## Guides

* [Stdlib Signatures Guide](stdlib.md)
* [Syntax](syntax.md)
* [Writing Signature Guide](sigs.md)

## Steps for Contribution

1. Pick the class/library you will work for.
2. Assign yourself on the [work spreadsheet](https://docs.google.com/spreadsheets/d/199rRB93I16H0k4TGZS3EGojns2R0W1oCsN8UPJzOpyU/edit#gid=1383307992) (optional but recommended to avoid duplication).
3. Sort RBS members (if there is RBS files for the classes).
    - Use `bin/sort stdlib/path/to/signature.rbs` command and confirm it does not break definitions.
    - Committing the sorted RBSs is recommended.
4. Add method prototypes.
    - Use `rbs prototype runtime --merge CLASS_NAME` command to generate the missing method definitions.
    - Committing the auto generated signatures is recommended.
5. Annotate with RDoc.
    - Use `bin/annotate-with-rdoc stdlib/path/to/signature.rbs` to annotate the RBS files.
    - Committing the generated annotations is recommended.
6. Fix method types and comments.
    - The auto generated RDoc comments include `arglists` section, which we don't expect to be included the RBS files.
    - Delete the `arglists` sections.
    - Give methods correct types.
    - Write tests, if possible. (If it is too difficult to write test, skip it.)

## The Target Version

* The standard library signatures targets Ruby 2.7 for now.
* The library code targets Ruby 2.6, 2.7, and 3.0.

## Stdlib Worksheet

You can find the list of classes/libraries:

* https://docs.google.com/spreadsheets/d/199rRB93I16H0k4TGZS3EGojns2R0W1oCsN8UPJzOpyU/edit#gid=1383307992

Assign yourself when you start working for a class or library.
After reviewing and merging your pull request, I will update the status of the library.

You may find the *Good for first contributor* column where you can find some classes are recommended for new contributors (👍), and some classes are not-recommended (👎).

## Useful Tools

* `rbs prototype runtime --merge String`
  * Generate a prototype using runtime API.
  * `--merge` tells to use the method types in RBS if exists.
* `rbs prototype runtime --merge --method-owner=Numeric Integer`
  * You can use --method-owner if you want to print method of other classes too, for documentation purpose.
* `bin/annotate-with-rdoc stdlib/builtin/string.rbs`
  * Write comments using RDoc.
  * It contains arglists section, but I don't think we should have it in RBS files.
* `bin/query-rdoc String#initialize`
  * Print RDoc documents in the format you can copy-and-paste to RBS.
* `bin/sort stdlib/builtin/string.rbs`
  * Sort declarations members in RBS files.
* `rbs validate -r LIB`
  Validate the syntax and some of the semantics.
* `rake generate:stdlib_test[String]`
  Scaffold the stdlib test.

## Standard STDLIB Members Order

We define the standard members order so that ordering doesn't bother reading diffs or git-annotate outputs.

1. `def self.new` or `def initialize`
2. Mixins
3. Attributes
4. Singleton methods
5. `public` & public instance methods
6. `private` & private instance methods

```
class HelloWorld[X]
  def self.new: [A] () { (void) -> A } -> HelloWorld[A]         # new or initialize comes first
  def initialize: () -> void

  include Enumerable[X, void]                                   # Mixin comes next

  attr_reader language: (:ja | :en)                             # Attributes

  def self.all_languages: () -> Array[Symbol]                   # Singleton methods

  public                                                        # Public instance methods

  def each: () { (A) -> void } -> void                          # Members are sorted dicionary order

  def to_s: (?Locale) -> String

  private                                                       # Private instance methods

  alias validate validate_locale

  def validate_locale: () -> void
end
```
