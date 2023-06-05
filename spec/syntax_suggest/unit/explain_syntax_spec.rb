# frozen_string_literal: true

require_relative "../spec_helper"

module SyntaxSuggest
  RSpec.describe "ExplainSyntax" do
    it "handles shorthand syntaxes with non-bracket characters" do
      source = <<~EOM
        %Q* lol
      EOM

      explain = ExplainSyntax.new(
        code_lines: CodeLine.from_source(source)
      ).call

      expect(explain.missing).to eq([])
      expect(explain.errors.join).to include("unterminated string")
    end

    it "handles %w[]" do
      source = <<~EOM
        node.is_a?(Op) && %w[| ||].include?(node.value) &&
      EOM

      explain = ExplainSyntax.new(
        code_lines: CodeLine.from_source(source)
      ).call

      expect(explain.missing).to eq([])
    end

    it "doesn't falsely identify strings or symbols as critical chars" do
      source = <<~EOM
        a = ['(', '{', '[', '|']
      EOM

      explain = ExplainSyntax.new(
        code_lines: CodeLine.from_source(source)
      ).call

      expect(explain.missing).to eq([])

      source = <<~EOM
        a = [:'(', :'{', :'[', :'|']
      EOM

      explain = ExplainSyntax.new(
        code_lines: CodeLine.from_source(source)
      ).call

      expect(explain.missing).to eq([])
    end

    it "finds missing |" do
      source = <<~EOM
        Foo.call do |
        end
      EOM

      explain = ExplainSyntax.new(
        code_lines: CodeLine.from_source(source)
      ).call

      expect(explain.missing).to eq(["|"])
      expect(explain.errors).to eq([explain.why("|")])
    end

    it "finds missing {" do
      source = <<~EOM
        class Cat
          lol = {
        end
      EOM

      explain = ExplainSyntax.new(
        code_lines: CodeLine.from_source(source)
      ).call

      expect(explain.missing).to eq(["}"])
      expect(explain.errors).to eq([explain.why("}")])
    end

    it "finds missing }" do
      source = <<~EOM
        def foo
          lol = "foo" => :bar }
        end
      EOM

      explain = ExplainSyntax.new(
        code_lines: CodeLine.from_source(source)
      ).call

      expect(explain.missing).to eq(["{"])
      expect(explain.errors).to eq([explain.why("{")])
    end

    it "finds missing [" do
      source = <<~EOM
        class Cat
          lol = [
        end
      EOM

      explain = ExplainSyntax.new(
        code_lines: CodeLine.from_source(source)
      ).call

      expect(explain.missing).to eq(["]"])
      expect(explain.errors).to eq([explain.why("]")])
    end

    it "finds missing ]" do
      source = <<~EOM
        def foo
          lol = ]
        end
      EOM

      explain = ExplainSyntax.new(
        code_lines: CodeLine.from_source(source)
      ).call

      expect(explain.missing).to eq(["["])
      expect(explain.errors).to eq([explain.why("[")])
    end

    it "finds missing (" do
      source = "def initialize; ); end"

      explain = ExplainSyntax.new(
        code_lines: CodeLine.from_source(source)
      ).call

      expect(explain.missing).to eq(["("])
      expect(explain.errors).to eq([explain.why("(")])
    end

    it "finds missing )" do
      source = "def initialize; (; end"

      explain = ExplainSyntax.new(
        code_lines: CodeLine.from_source(source)
      ).call

      expect(explain.missing).to eq([")"])
      expect(explain.errors).to eq([explain.why(")")])
    end

    it "finds missing keyword" do
      source = <<~EOM
        class Cat
          end
        end
      EOM

      explain = ExplainSyntax.new(
        code_lines: CodeLine.from_source(source)
      ).call

      expect(explain.missing).to eq(["keyword"])
      expect(explain.errors).to eq([explain.why("keyword")])
    end

    it "finds missing end" do
      source = <<~EOM
        class Cat
          def meow
        end
      EOM

      explain = ExplainSyntax.new(
        code_lines: CodeLine.from_source(source)
      ).call

      expect(explain.missing).to eq(["end"])
      expect(explain.errors).to eq([explain.why("end")])
    end

    it "falls back to ripper on unknown errors" do
      source = <<~EOM
        class Cat
          def meow
            1 *
          end
        end
      EOM

      explain = ExplainSyntax.new(
        code_lines: CodeLine.from_source(source)
      ).call

      expect(explain.missing).to eq([])
      expect(explain.errors).to eq(RipperErrors.new(source).call.errors)
    end

    it "handles an unexpected rescue" do
      source = <<~EOM
        def foo
          if bar
            "baz"
          else
            "foo"
        rescue FooBar
          nil
        end
      EOM

      explain = ExplainSyntax.new(
        code_lines: CodeLine.from_source(source)
      ).call

      expect(explain.missing).to eq(["end"])
    end

    # String embeds are `"#{foo} <-- here`
    #
    # We need to count a `#{` as a `{`
    # otherwise it will report that we are
    # missing a curly when we are using valid
    # string embed syntax
    it "is not confused by valid string embed" do
      source = <<~'EOM'
        foo = "#{hello}"
      EOM

      explain = ExplainSyntax.new(
        code_lines: CodeLine.from_source(source)
      ).call
      expect(explain.missing).to eq([])
    end

    # Missing string embed beginnings are not a
    # syntax error. i.e. `"foo}"` or `"{foo}` or "#foo}"
    # would just be strings with extra characters.
    #
    # However missing the end curly will trigger
    # an error: i.e. `"#{foo`
    #
    # String embed beginning is a `#{` rather than
    # a `{`, make sure we handle that case and
    # report the correct missing `}` diagnosis
    it "finds missing string embed end" do
      source = <<~'EOM'
        "#{foo
      EOM

      explain = ExplainSyntax.new(
        code_lines: CodeLine.from_source(source)
      ).call

      expect(explain.missing).to eq(["}"])
    end
  end
end
