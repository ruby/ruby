require_relative '../../../spec_helper'
require_relative '../../../fixtures/source_range_helpers'
require_relative '../fixtures/classes'
require 'coverage'

describe "Coverage.result with lines: true" do
  it "returns how many times each line with code ran and nil for the other lines" do
    CoverageSpecs.line_coverage(<<~'RUBY').should == [nil, nil, 1, 1, 0, nil, 1, 3, nil]
      # comment

      x = 1
      def never
        :never
      end
      3.times do
        x += 1
      end
    RUBY
  end

  it "counts a call whose arguments continue on the next line on its first line" do
    CoverageSpecs.line_coverage(<<~'RUBY').should == [1, 1, nil]
      x = []
      x.concat(
        [].to_a)
    RUBY
  end

  it "counts an assignment on the line where its value starts" do
    CoverageSpecs.line_coverage(<<~'RUBY').should == [nil, 1, 1]
      x =
        [].size
      x = x
    RUBY
  end

  it "counts an attribute assignment on its first line" do
    CoverageSpecs.line_coverage(<<~'RUBY').should == [1, 1, nil]
      o = Struct.new(:b).new
      o.b =
        [].size
    RUBY
  end

  it "counts an Array literal of several lines on its first line" do
    CoverageSpecs.line_coverage(<<~'RUBY').should == [1, nil, nil]
      x = [
        1,
        2]
    RUBY
  end

  it "counts a Hash literal of several lines on its first line" do
    CoverageSpecs.line_coverage(<<~'RUBY').should == [1, nil, nil]
      y = {
        a: :b,
        c: 1.0}
    RUBY
  end

  it "counts a Hash literal on the line of the first call among its values" do
    CoverageSpecs.line_coverage(<<~'RUBY').should == [nil, 1, 1]
      z = {
        a: [].size }
      z = z
    RUBY
  end

  it "counts no line for a statement that has no effect" do
    CoverageSpecs.line_coverage(<<~'RUBY').should == [1, nil, nil, nil, nil, nil, nil, 1, 1, nil, 1]
      def void_statements(x)
        x
        1
        "str"
        @iv
        [1, :a]
        x = x
        $stdout
        x
      end
      void_statements(1)
    RUBY
  end

  it "counts a statement in a begin with an ensure clause once" do
    CoverageSpecs.line_coverage(<<~'RUBY').should == [1, 1, nil, 1, nil, 1, nil, nil, 1]
      def g
        x = 1
        begin
          [].size
        ensure
          x = 2
        end
      end
      g
    RUBY
  end

  it "counts undef on the line of its keyword" do
    skip "parse.y" if parse_y?

    CoverageSpecs.line_coverage(<<~'RUBY').should == [2, 1, 1, nil, nil, nil]
      class UndefCoverage; def a; end; def b; end; end
      class UndefCoverage
        x = 1; undef
          a,
          b
      end
    RUBY
  end

  describe "for an interpolation" do
    it "counts each line of several interpolated statements" do
      CoverageSpecs.line_coverage(<<~'RUBY').should == [1, 1, 1, nil]
        x = "#{
          a = 1
          a
        }"
      RUBY
    end

    it "counts a line with a statement before an interpolated literal" do
      CoverageSpecs.line_coverage(<<~'RUBY').should == [1, 1, 1]
        def foo(*) = nil
        foo([1].map {
          y = 1; nil }, "#{3}")
      RUBY
    end

    it "counts a heredoc on the line of its first interpolated call" do
      skip "parse.y" if parse_y?

      CoverageSpecs.line_coverage(<<~'RUBY').should == [nil, 1, nil, nil, 1]
        y = <<~EOS
          #{[].size}
          #{[].size}
        EOS
        y = y
      RUBY
    end

    it "counts the line of a call interpolated in a heredoc that ends the file" do
      skip "parse.y" if parse_y?

      CoverageSpecs.line_coverage(<<~'RUBY').should == [nil, 1, nil]
        x = <<~EOS
          #{1.to_s}
        EOS
      RUBY
    end

    ruby_version_is "3.4" do
      it "counts the line of a conditional interpolated in a heredoc" do
        skip "parse.y" if parse_y?

        CoverageSpecs.line_coverage(<<~'RUBY').should == [1, nil, 1, nil, 1]
          x = <<~EOS
            abc
            #{[].empty? ? "a" : "b"}
          EOS
          x = x
        RUBY
      end
    end
  end

  describe "for a conditional" do
    it "counts each elsif condition on its line" do
      CoverageSpecs.line_coverage(<<~'RUBY').should == [1, 2, 1, 1, 1, 0, 0, nil, nil, 1, 1]
        def elsifs(x)
          if x == 1
            :one
          elsif x == 2
            :two
          elsif x == 3
            :three
          end
        end
        elsifs(1)
        elsifs(2)
      RUBY
    end

    it "counts the condition line of an if used as a value" do
      CoverageSpecs.line_coverage(<<~'RUBY').should == [1, nil, 1, 1, nil]
        x = true
        a =
          if x
            1
          end
      RUBY
    end

    it "counts the condition line of an unless used as a value" do
      CoverageSpecs.line_coverage(<<~'RUBY').should == [1, 1, 1, 0, nil]
        x = true
        b = [1,
          unless x
            2
          end]
      RUBY
    end

    it "counts no line of an if whose condition is false" do
      CoverageSpecs.line_coverage(<<~'RUBY').should == [1, nil, nil, nil, 1]
        x = 1
        if false
          x = 2
        end
        x = 3
      RUBY
    end

    it "counts only the then arm of an if whose condition is true" do
      CoverageSpecs.line_coverage(<<~'RUBY').should == [nil, 1, nil, nil, nil]
        if true
          a = 1
        else
          b = 2
        end
      RUBY
    end

    it "counts only the else arm of an if whose condition is nil" do
      CoverageSpecs.line_coverage(<<~'RUBY').should == [nil, nil, nil, 1, nil]
        c = if nil
          3
        else
          4
        end
      RUBY
    end

    it "counts no line for a modifier unless whose condition is true" do
      CoverageSpecs.line_coverage(<<~'RUBY').should == [1, nil, 1]
        x = 1
        d = 5 unless true
        x = 2
      RUBY
    end

    it "counts the condition but not the arm of an if on a condition ending in a false literal" do
      CoverageSpecs.line_coverage(<<~'RUBY').should == [1, 1, nil, nil, 1]
        x = 1
        if x and false
          6
        end
        x = 2
      RUBY
    end

    it "counts a modifier if on the line of its condition" do
      CoverageSpecs.line_coverage(<<~'RUBY').should == [1, 1, nil, 1, 1]
        def m(*) = 1
        y = 1
        m 1,
          2 if y
        y = 2
      RUBY
    end

    it "counts a modifier unless on the line of its condition" do
      CoverageSpecs.line_coverage(<<~'RUBY').should == [1, 1, nil, nil, 1, 1]
        def m(*) = 1
        y = 1
        m(
          1) unless
            y
        y = 2
      RUBY
    end

    it "counts the line of an interpolated modifier unless" do
      CoverageSpecs.line_coverage(<<~'RUBY').should == [1, 1]
        y = 1
        x = "#{y} item#{'s' unless y == 1}"
      RUBY
    end

    it "counts the statement of an interpolated modifier if on its own line" do
      CoverageSpecs.line_coverage(<<~'RUBY').should == [1, 1, 1, nil]
        def m(*) = 1
        y = 1
        x = "#{m 1 if
          y}"
      RUBY
    end

    it "counts a when arm that runs on the line it shares with the else" do
      CoverageSpecs.line_coverage(<<~'RUBY').should == [1, 1, 1]
        x = 1
        a = [1,
          case x; when 1 then 2; else 3; end]
      RUBY
    end

    it "counts an else that runs on the line it shares with a when arm as 0" do
      CoverageSpecs.line_coverage(<<~'RUBY').should == [1, 1, 0]
        x = 3
        a = [1,
          case x; when 1 then 2; else 3; end]
      RUBY
    end

    it "counts an in arm that runs on the line it shares with the else" do
      CoverageSpecs.line_coverage(<<~'RUBY').should == [1, 1, 1]
        x = 1
        a = [1,
          case x; in 1 then 2; else 3; end]
      RUBY
    end

    it "counts an else that runs on the line it shares with an in arm as 0" do
      CoverageSpecs.line_coverage(<<~'RUBY').should == [1, 1, 0]
        x = 3
        a = [1,
          case x; in 1 then 2; else 3; end]
      RUBY
    end

    ruby_version_is "3.4" do
      it "counts the arms of a ternary on their own line" do
        skip "parse.y" if parse_y?

        CoverageSpecs.line_coverage(<<~'RUBY').should == [1, 1, 1]
          y = [1]
          x = y.size ?
            1 : 2
        RUBY
      end

      it "counts each arm of a ternary used as a condition on its own line" do
        skip "parse.y" if parse_y?

        CoverageSpecs.line_coverage(<<~'RUBY').should == [1, 1, 0, 1, 1, nil]
          y = [1]
          if y.empty? ?
               y.first :
               y.last
            z = 1
          end
        RUBY
      end

      it "counts the condition line of a ternary used as an argument" do
        skip "parse.y" if parse_y?

        CoverageSpecs.line_coverage(<<~'RUBY').should == [1, 1, 1, 1, 1]
          def value_of(v) = v
          x = true
          c = value_of(
            x ?
              3 : 4)
        RUBY
      end
    end
  end
end
