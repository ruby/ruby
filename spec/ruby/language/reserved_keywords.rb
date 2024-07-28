require_relative '../spec_helper'

describe "Ruby's reserved keywords" do
  # Copied from Prism::Translation::Ripper
  keywords = [
    "alias",
    "and",
    "begin",
    "BEGIN",
    "break",
    "case",
    "class",
    "def",
    "defined?",
    "do",
    "else",
    "elsif",
    "end",
    "END",
    "ensure",
    "false",
    "for",
    "if",
    "in",
    "module",
    "next",
    "nil",
    "not",
    "or",
    "redo",
    "rescue",
    "retry",
    "return",
    "self",
    "super",
    "then",
    "true",
    "undef",
    "unless",
    "until",
    "when",
    "while",
    "yield",
    "__ENCODING__",
    "__FILE__",
    "__LINE__"
  ]

  invalid_kw_param_names = [
    "BEGIN",
    "END",
    "defined?",
  ]

  invalid_method_names = [
    "BEGIN",
    "END",
    "defined?",
  ]

  def expect_syntax_error(ruby_src)
    -> { eval(ruby_src) }.should raise_error(SyntaxError)
  end

  # Evaluates the given Ruby source in a temporary Module, to prevent
  # the surrounding context from being polluted with the new methods.
  def sandboxed_eval(ruby_src)
    Module
      # Allows instance methods defined by `ruby_src` to be called directly.
      .new { extend self }
      .class_eval(ruby_src)
  end

  keywords.each do |kw|
    describe "keyword '#{kw}'" do
      it "can't be used as local variable name" do
        expect_syntax_error <<~RUBY
            #{kw} = "a local variable named '#{kw}'"
        RUBY
      end

      it "can't be used as a positional parameter name" do
        expect_syntax_error <<~RUBY
            def x(#{kw}); end
        RUBY
      end

      unless invalid_kw_param_names.include?(kw)
        it "can be used a keyword parameter name" do
          result = sandboxed_eval <<~RUBY
            def m(#{kw}:) = { #{kw}: }

            m(#{kw}: "an argument to '#{kw}'")
          RUBY

          result.should == { kw.to_sym => "an argument to '#{kw}'" }
        end
      end

      unless invalid_method_names.include?(kw)
        it "can refer to a method called '#{kw}'" do
          result = sandboxed_eval <<~RUBY
            def #{kw} = "a method named '#{kw}'"

            { #{kw}: }
          RUBY

          result.should == { kw.to_sym => "a method named '#{kw}'" }
        end
      end
    end
  end
end
