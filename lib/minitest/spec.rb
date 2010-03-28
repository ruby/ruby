############################################################
# This file is imported from a different project.
# DO NOT make modifications in this repo.
# File a patch instead and assign it to Ryan Davis
############################################################

#!/usr/bin/ruby -w

require 'minitest/unit'

class Module
  def infect_an_assertion meth, new_name, dont_flip = false
    # warn "%-22p -> %p %p" % [meth, new_name, dont_flip]
    self.class_eval <<-EOM
      def #{new_name} *args, &block
        return MiniTest::Spec.current.#{meth}(*args, &self) if
          Proc === self
        return MiniTest::Spec.current.#{meth}(args.first, self) if
          args.size == 1 unless #{!!dont_flip}
        return MiniTest::Spec.current.#{meth}(self, *args)
      end
    EOM
  end

  def infect_with_assertions(pos_prefix, neg_prefix,
                             skip_re,
                             dont_flip_re = /\c0/,
                             map = {})
    MiniTest::Assertions.public_instance_methods(false).each do |meth|
      meth = meth.to_s

      new_name = case meth
                 when /^assert/ then
                   meth.sub(/^assert/, pos_prefix.to_s)
                 when /^refute/ then
                   meth.sub(/^refute/, neg_prefix.to_s)
                 end
      next unless new_name
      next if new_name =~ skip_re

      regexp, replacement = map.find { |re, _| new_name =~ re }
      new_name.sub! regexp, replacement if replacement

      infect_an_assertion meth, new_name, new_name =~ dont_flip_re
    end
  end
end

Object.infect_with_assertions(:must, :wont,
                              /^(must|wont)$|wont_(throw)|
                                 must_(block|not?_|nothing|raise$)/x,
                              /(must|wont)_(include|respond_to)/,
                              /(must_throw)s/                 => '\1',
                              /(?!not)_same/                  => '_be_same_as',
                              /_in_/                          => '_be_within_',
                              /_operator/                     => '_be',
                              /_includes/                     => '_include',
                              /(must|wont)_(.*_of|nil|empty)/ => '\1_be_\2',
                              /must_raises/                   => 'must_raise')

class Object
  alias :must_be_close_to :must_be_within_delta
  alias :wont_be_close_to :wont_be_within_delta
end

module Kernel
  ##
  # Describe a series of expectations for a given target +desc+.
  #
  # TODO: find good tutorial url.
  #
  # Defines a test class subclassing from either
  # MiniTest::Unit::TestCase or from the surrounding describe's class.

  def describe desc, &block
    stack = MiniTest::Spec.describe_stack
    name  = desc.to_s.split(/\W+/).map { |s| s.capitalize }.join + "Spec"
    prev  = stack.last
    name  = "#{prev == MiniTest::Spec ? nil : prev}::#{name}"
    cls   = Object.class_eval "class #{name} < #{prev}; end; #{name}"

    cls.nuke_test_methods!

    stack.push cls
    cls.class_eval(&block)
    stack.pop
  end
  private :describe
end

class Module
  def classes type = Object # :nodoc:
    constants.map { |n| const_get n }.find_all { |c|
      c.class == Class and type > c
    } - [self]
  end
end

class MiniTest::Spec < MiniTest::Unit::TestCase
  @@describe_stack = [MiniTest::Spec]
  def self.describe_stack # :nodoc:
    @@describe_stack
  end

  def self.current # :nodoc:
    @@current_spec
  end

  def initialize name # :nodoc:
    super
    @@current_spec = self
  end

  def self.nuke_test_methods! # :nodoc:
    self.public_instance_methods.grep(/^test_/).each do |name|
      self.send :undef_method, name
    end
  end

  def self.define_inheritable_method name, &block # :nodoc:
    super_method = self.superclass.instance_method name

    define_method name do
      super_method.bind(self).call if super_method # regular super() warns
      instance_eval(&block)
    end
  end

  ##
  # Define a 'before' action. Inherits the way normal methods should.
  #
  # NOTE: +type+ is ignored and is only there to make porting easier.
  #
  # Equivalent to MiniTest::Unit::TestCase#setup.

  def self.before type = :each, &block
    raise "unsupported before type: #{type}" unless type == :each
    define_inheritable_method :setup, &block
  end

  ##
  # Define an 'after' action. Inherits the way normal methods should.
  #
  # NOTE: +type+ is ignored and is only there to make porting easier.
  #
  # Equivalent to MiniTest::Unit::TestCase#teardown.

  def self.after type = :each, &block
    raise "unsupported after type: #{type}" unless type == :each
    define_inheritable_method :teardown, &block
  end

  ##
  # Define an expectation with name +desc+. Name gets morphed to a
  # proper test method name. For some freakish reason, people who
  # write specs don't like class inheritence, so this goes way out of
  # its way to make sure that expectations aren't inherited.
  #
  # Hint: If you _do_ want inheritence, use minitest/unit. You can mix
  # and match between assertions and expectations as much as you want.

  def self.it desc, &block
    block ||= proc { skip "(no tests defined)" }

    @specs ||= 0
    @specs += 1

    name = "test_%04d_%s" % [ @specs, desc.gsub(/\W+/, '_').downcase ]

    define_method name, &block

    classes(MiniTest::Spec).each do |mod|
      mod.send :undef_method, name if mod.respond_to? name
    end
  end

  ##
  # :method: must_be
  # See MiniTest::Assertions#assert

  ##
  # :method: must_be_close_to
  # See MiniTest::Assertions#assert_in_delta

  ##
  # :method: must_be_empty
  # See MiniTest::Assertions#assert_empty

  ##
  # :method: must_be_instance_of
  # See MiniTest::Assertions#assert_instance_of

  ##
  # :method: must_be_kind_of
  # See MiniTest::Assertions#assert_kind_of

  ##
  # :method: must_be_nil
  # See MiniTest::Assertions#assert_nil

  ##
  # :method: must_be_same_as
  # See MiniTest::Assertions#assert_same

  ##
  # :method: must_be_within_delta
  # See MiniTest::Assertions#assert_in_delta

  ##
  # :method: must_be_within_epsilon
  # See MiniTest::Assertions#assert_in_epsilon

  ##
  # :method: must_equal
  # See MiniTest::Assertions#assert_equal

  ##
  # :method: must_include
  # See MiniTest::Assertions#assert_includes

  ##
  # :method: must_match
  # See MiniTest::Assertions#assert_match

  ##
  # :method: must_raise
  # See MiniTest::Assertions#assert_raises

  ##
  # :method: must_respond_to
  # See MiniTest::Assertions#assert_respond_to

  ##
  # :method: must_send
  # See MiniTest::Assertions#assert_send

  ##
  # :method: must_throw
  # See MiniTest::Assertions#assert_throw

  ##
  # :method: wont_be
  # See MiniTest::Assertions#refute

  ##
  # :method: wont_be_close_to
  # See MiniTest::Assertions#refute_in_delta

  ##
  # :method: wont_be_empty
  # See MiniTest::Assertions#refute_empty

  ##
  # :method: wont_be_instance_of
  # See MiniTest::Assertions#refute_instance_of

  ##
  # :method: wont_be_kind_of
  # See MiniTest::Assertions#refute_kind_of

  ##
  # :method: wont_be_nil
  # See MiniTest::Assertions#refute_nil

  ##
  # :method: wont_be_same_as
  # See MiniTest::Assertions#refute_same

  ##
  # :method: wont_be_within_delta
  # See MiniTest::Assertions#refute_in_delta

  ##
  # :method: wont_be_within_epsilon
  # See MiniTest::Assertions#refute_in_epsilon

  ##
  # :method: wont_equal
  # See MiniTest::Assertions#refute_equal

  ##
  # :method: wont_include
  # See MiniTest::Assertions#refute_includes

  ##
  # :method: wont_match
  # See MiniTest::Assertions#refute_match

  ##
  # :method: wont_respond_to
  # See MiniTest::Assertions#refute_respond_to
end
