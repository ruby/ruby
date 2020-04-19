# Stdlib Signatures Guide

This is a guide for contributing to `ruby-signature` by writing/revising stdlib signatures.

The typical steps of writing signatures will be like the following:

1. Generate a prototype
2. Import RDoc document
3. Give correct types to the prototype
4. Add tests

## Signatures

Signatures for standard libraries are located in `stdlib` directory. `stdlib/builtin` is for builtin libraries. Other libraries have directories like `stdlib/set` or `stdlib/pathname`.

To write signatures see [syntax guide](syntax.md).

## Generating prototypes

`ruby-signature` provides a tool to generate a prototype of signatures, `rbs prototype`.
It provides several options, `rbi` from Sorbet RBI files, `rb` from Ruby code, and `runtime` from runtime API.
`runtime` should be the best option for standard libraries because they may be implemented in C, no Ruby source code.

The tool `require`s all of the libraries specified with `-r` option, and then use introspection APIs like `instance_methods` to know the structure of the class.
The commandline receives the name of classes you want to prototype, exact class name (like `Pathname`) or pattern with `*` (like `IO::*`).

```
$ bundle exec rbs prototype runtime --require pathname Pathname
class Pathname
  def self.getwd: () -> untyped

  def self.glob: (*untyped) -> untyped

  def self.pwd: () -> untyped

  def +: (untyped other) -> untyped

  alias / +

  def <=>: (untyped) -> untyped

  # snip
end

# snip
```

The prototype includes:

* Instance method definitions,
* Singleton method definitions,
* Includes, and
* Constants

It generate a simple prototype in the sense that all of the types included are `untyped`.
But it will help you to have an overview of the signatures you are trying to write.

### What to do with existing RBS files

Generating prototypes will override everything, so the problem is if there is a RBS files already.
You can try to find missing parts, or you can start from the scratch.

One non-trivial but absolutely better solution is to make a tool:

1. To load type definitions from existing RBS file, and
2. Generate prototypes only for missing methods.

## Import RDoc document

The next step should be importing RDoc documents.

```
$ bin/annotate-with-rdoc stdlib/pathname/pathname.rbs
Loading store from /Users/soutaro/.rbenv/versions/2.7.0-dev/share/ri/2.7.0/system...
Loading store from /Users/soutaro/.rbenv/versions/2.7.0-dev/share/ri/2.7.0/site...
Opening stdlib/pathname/pathname.rbs...
  Importing documentation for Pathname...
    Processing glob...
    Processing +...
    # snip
Writing stdlib/pathname/pathname.rbs...
```

The `annotate-with-rdoc` command adds annotations to RBS files.

1. Query RDoc documents to annotate classes, modules, methods, and constants,
2. Put annotations on RBS AST, and
3. Update the given .RBS files

We recommend using the command to annotate the RBS files.

## Writing types

The next step is to replace `untyped` types in the prototype.
See [syntax guide](syntax.md) for the detail of the syntax.

We can show some of the guides for writing types.

1. Use `bool` for truth values, truthy or falsey. More specific types like `TrueClass | FalseClass` may be too strict.
2. Use `void` if the return value is useless.
3. Use `nil` instead of `NilClass`.
4. The most strict types may not be the best types. Use `untyped` if you cannot find the best one.

## Add Tests

We support writing tests for stdlib signatures.

### Writing tests

First, execute `generate:stdlib_test` rake task with a class name that you want to test.

```bash
$ bundle exec rake 'generate:stdlib_test[String]'
Created: test/stdlib/String_test.rb
```

It generates `test/stdlib/[class_name]_test.rb`.
The test scripts would look like the following:

```rb
class StringTest < StdlibTest
  target String
  using hook.refinement

  def test_gsub
    s = "string"
    s.gsub(/./, "")
    s.gsub("a", "b")
    s.gsub(/./) {|x| "" }
    s.gsub(/./, {"foo" => "bar"})
    s.gsub(/./)
    s.gsub("")
  end
end
```

You need two method calls, `target` and `using`.
`target` method call tells which class is the subject of the class.
`using hook.refinement` installs a special instrumentation for stdlib, based on refinements.
And you write the sample programs which calls all of the patterns of overloads.

Note that the instrumentation is based on refinements and you need to write all method calls in the unit class definitions.
If the execution of the program escape from the class definition, the instrumentation is disabled and no check will be done.

### Running tests

You can run the test with:

```
$ bundle exec ruby bin/test_runner.rb         # Run all tests
$ bundle exec ruby test/stdlib/String_test.rb # Run specific tests
```
