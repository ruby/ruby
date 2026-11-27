require_relative '../../spec_helper'
require_relative '../../fixtures/source_range_helpers'
require_relative 'fixtures/classes'
require 'coverage'

describe "Coverage.line_stub" do
  it "returns 0 for each line that line coverage counts and nil for the other lines" do
    CoverageSpecs.line_stub(<<~'RUBY').should == [nil, nil, 0, 0, 0, nil, 0, 0, nil]
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

  it "returns 0 only for the first line of a call chain that spans several lines" do
    CoverageSpecs.line_stub(<<~'RUBY').should == [0, 0, nil, nil, nil]
      def show
        @product = base_scope
                   .includes(colors_products: :color)
                   .find(params[:id])
      end
    RUBY
  end

  it "returns nil for a statement that has no effect" do
    CoverageSpecs.line_stub(<<~'RUBY').should == [0, nil, nil, nil, nil, nil, nil, 0, 0, nil, 0]
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

  it "returns 0 for each elsif condition" do
    CoverageSpecs.line_stub(<<~'RUBY').should == [0, 0, 0, 0, 0, 0, 0, nil, nil]
      def elsifs(x)
        if x == 1
          :one
        elsif x == 2
          :two
        elsif x == 3
          :three
        end
      end
    RUBY
  end

  it "returns 0 for the condition line of an if used as a value" do
    CoverageSpecs.line_stub(<<~'RUBY').should == [0, nil, 0, 0, nil]
      x = true
      a =
        if x
          1
        end
    RUBY
  end

  it "returns 0 for the condition line of an unless used as a value" do
    CoverageSpecs.line_stub(<<~'RUBY').should == [0, 0, 0, 0, nil]
      x = true
      b = [1,
        unless x
          2
        end]
    RUBY
  end

  it "returns nil for each line of an if whose condition is false" do
    CoverageSpecs.line_stub(<<~'RUBY').should == [0, nil, nil, nil, 0]
      x = 1
      if false
        x = 2
      end
      x = 3
    RUBY
  end

  it "returns 0 only for the then arm of an if whose condition is true" do
    CoverageSpecs.line_stub(<<~'RUBY').should == [nil, 0, nil, nil, nil]
      if true
        a = 1
      else
        b = 2
      end
    RUBY
  end

  it "returns nil for a modifier unless whose condition is true" do
    CoverageSpecs.line_stub(<<~'RUBY').should == [0, nil, 0]
      x = 1
      d = 5 unless true
      x = 2
    RUBY
  end

  it "returns 0 for the condition line of a modifier if" do
    CoverageSpecs.line_stub(<<~'RUBY').should == [0, 0, nil, 0, 0]
      def m(*) = 1
      y = 1
      m 1,
        2 if y
      y = 2
    RUBY
  end

  it "returns 0 for the condition line of a modifier unless" do
    CoverageSpecs.line_stub(<<~'RUBY').should == [0, 0, nil, nil, 0, 0]
      def m(*) = 1
      y = 1
      m(
        1) unless
          y
      y = 2
    RUBY
  end

  it "returns 0 for the statement of an interpolated modifier if" do
    CoverageSpecs.line_stub(<<~'RUBY').should == [0, 0, 0, nil]
      def m(*) = 1
      y = 1
      x = "#{m 1 if
        y}"
    RUBY
  end

  it "returns an entry for a last line without a newline" do
    CoverageSpecs.line_stub("x = 1\ny = 2").should == [0, 0]
  end

  it "returns an entry for each trailing blank line" do
    CoverageSpecs.line_stub("x = 1\n\n\n\n").should == [0, nil, nil, nil]
  end

  it "returns an empty Array for an empty file" do
    CoverageSpecs.line_stub("").should == []
  end

  it "does not start the coverage measurement" do
    CoverageSpecs.line_stub("x = 1\n")
    Coverage.running?.should == false
  end

  ruby_version_is "3.4" do
    it "returns 0 for the condition line of a ternary used as an argument" do
      skip "parse.y" if parse_y?

      CoverageSpecs.line_stub(<<~'RUBY').should == [0, 0, 0, 0, 0]
        def value_of(v) = v
        x = true
        c = value_of(
          x ?
            3 : 4)
      RUBY
    end
  end
end
