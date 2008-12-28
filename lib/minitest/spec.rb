############################################################
# This file is imported from a different project.
# DO NOT make modifications in this repo.
# File a patch instead and assign it to Ryan Davis
############################################################

#!/usr/bin/ruby -w

require 'minitest/unit'

class Module
  def infect_with_assertions pos_prefix, neg_prefix, skip_re, map = {}
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

      # warn "%-22p -> %p %p" % [meth, new_name, regexp]
      self.class_eval <<-EOM
        def #{new_name} *args, &block
          return MiniTest::Spec.current.#{meth}(*args, &self)     if Proc === self
          return MiniTest::Spec.current.#{meth}(args.first, self) if args.size == 1
          return MiniTest::Spec.current.#{meth}(self, *args)
        end
      EOM
    end
  end
end

Object.infect_with_assertions(:must, :wont,
                              /^(must|wont)$|wont_(throw)|
                                 must_(block|not?_|nothing|raise$)/x,
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
  def describe desc, &block
    cls = Class.new(MiniTest::Spec)
    Object.const_set desc.to_s.split(/\W+/).map { |s| s.capitalize }.join, cls

    cls.class_eval(&block)
  end
  private :describe
end

class MiniTest::Spec < MiniTest::Unit::TestCase
  def self.current
    @@current_spec
  end

  def initialize name
    super
    @@current_spec = self
  end

  def self.before(type = :each, &block)
    raise "unsupported before type: #{type}" unless type == :each
    define_method :setup, &block
  end

  def self.after(type = :each, &block)
    raise "unsupported after type: #{type}" unless type == :each
    define_method :teardown, &block
  end

  def self.it desc, &block
    define_method "test_#{desc.gsub(/\W+/, '_').downcase}", &block
  end
end
