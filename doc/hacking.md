# Ruby Hacking Guide

This document gives some helpful instructions which should make your experience as a Ruby core developer easier.

## Configure Ruby

It's generally advisable to use a build directory.

	./autogen.sh
	mkdir build
	cd build
	../configure --prefix $HOME/.rubies/ruby-head
	make -j16 install

### Without Documentation

If you are frequently building Ruby, this will reduce the time it takes to `make install`.

	../configure --disable-install-doc

## Running Ruby

### Run Local Test Script

You can create a file in the Ruby source root called `test.rb`. You can build `miniruby` and execute this script:

	make -j16 run

If you want more of the standard library, you can use `runruby` instead of `run`.

### Run Bootstrap Tests

There are a set of tests in `bootstraptest/` which cover most basic features of the core Ruby language.

	make -j16 test

### Run Extensive Tests

There are extensive tests in `test/` which cover a wide range of features of the Ruby core language.

	make -j16 test-all

You can run specific tests by specifying their path:

	make -j16 test-all TESTS=../test/fiber/test_io.rb

### Run RubySpec Tests

RubySpec is a project to write a complete, executable specification for the Ruby programming language.

	make -j16 test-all test-rubyspec
