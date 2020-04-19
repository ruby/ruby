# Ruby::Signature

Ruby::Signature provides syntax and semantics definition for the `Ruby Signature` language, `.rbs` files.
It consists of a parser, the syntax, and class definition interpreter, the semantics.

## Build

We haven't published a gem yet.
You need to install the dependencies, and build its parser with `bin/setup`.

```
$ bin/setup
$ bundle exec exe/ruby-signature
```

## Usage

```
$ ruby-signature list
$ ruby-signature ancestors ::Object
$ ruby-signature methods ::Object
$ ruby-signature method ::Object tap
```

### ruby-signature [--class|--module|interface] list

```
$ ruby-signature list
```

This command lists all of the classes/modules/interfaces defined in `.rbs` files.

### ruby-signature ancestors [--singleton|--instance] CLASS

```
$ ruby-signature ancestors Array                    # ([].class.ancestors)
$ ruby-signature ancestors --singleton Array        # (Array.class.ancestors)
```

This command prints the _ancestors_ of the class.
The name of the command is borrowed from `Class#ancestors`, but the semantics is a bit different.
The `ancestors` command is more precise (I believe).

### ruby-signature methods [--singleton|--instance] CLASS

```
$ ruby-signature methods ::Integer                  # 1.methods
$ ruby-signature methods --singleton ::Object       # Object.methods
```

This command prints all methods provided for the class.

### ruby-signature method [--singleton|--instance] CLASS METHOD

```
$ ruby-signature method ::Integer '+'               # 1+2
$ ruby-signature method --singleton ::Object tap    # Object.tap { ... }
```

This command prints type and properties of the method.

### Options

It accepts two global options, `-r` and `-I`.

`-r` is for libraries. You can specify the names of libraries.

```
$ ruby-signature -r set list
```

`-I` is for application signatures. You can specify the name of directory.

```
$ ruby-signature -I sig list
```

## Guides

- [Standard library signature contribution guide](docs/CONTRIBUTING.md)
- [Writing signatures guide](docs/sigs.md)
- [Stdlib signatures guide](docs/stdlib.md)
- [Syntax](docs/syntax.md)

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/ruby/ruby-signature.
