require_relative '../../../spec_helper'
require_relative '../../../fixtures/source_range_helpers'
require_relative '../fixtures/classes'
require 'coverage'

describe "Coverage.result with branches: true" do
  before :all do
    @file = fixture __dir__, 'sign.rb'
  end

  after :each do
    Coverage.result if Coverage.running?
  end

  it "returns only the branches of each file" do
    Coverage.start(branches: true)
    load @file
    result = Coverage.result

    result[@file].keys.should == [:branches]
  end

  it "starts the counts over when a file is loaded again" do
    Coverage.start(branches: true)
    load @file
    CoverageSpecs.sign(1)
    load @file
    CoverageSpecs.sign(-1)
    result = Coverage.result

    result[@file][:branches].should == {
      [:if, 0, 3, 4, 3, 33] => {
        [:then, 1, 3, 12, 3, 21] => 1,
        [:else, 2, 3, 24, 3, 33] => 0
      }
    }
  end

  it "returns the counts so far when passed clear: true" do
    Coverage.start(branches: true)
    load @file
    CoverageSpecs.sign(1)
    result = Coverage.result(stop: false, clear: true)

    result[@file][:branches].should == {
      [:if, 0, 3, 4, 3, 33] => {
        [:then, 1, 3, 12, 3, 21] => 0,
        [:else, 2, 3, 24, 3, 33] => 1
      }
    }
  end

  it "sets the counts to 0 when passed clear: true" do
    Coverage.start(branches: true)
    load @file
    CoverageSpecs.sign(1)
    Coverage.result(stop: false, clear: true)

    Coverage.peek_result[@file][:branches].should == {
      [:if, 0, 3, 4, 3, 33] => {
        [:then, 1, 3, 12, 3, 21] => 0,
        [:else, 2, 3, 24, 3, 33] => 0
      }
    }
  end

  it "reports the arms of an if with how many times each ran" do
    result = CoverageSpecs.branch_coverage(<<~'RUBY')
      [1, 2, -3].each do |x|
        if x > 0
          :positive
        else
          :negative
        end
      end
    RUBY

    result.should == {
      [:if, 0, 2, 2, 6, 5] => {
        [:then, 1, 3, 4, 3, 13] => 2,
        [:else, 2, 5, 4, 5, 13] => 1
      }
    }
  end

  it "reports an else arm that spans the whole if when it has none" do
    result = CoverageSpecs.branch_coverage(<<~'RUBY')
      x = 1
      if x > 0
        :positive
      end
    RUBY

    result.should == {
      [:if, 0, 2, 0, 4, 3] => {
        [:then, 1, 3, 2, 3, 11] => 1,
        [:else, 2, 2, 0, 4, 3] => 0
      }
    }
  end

  it "reports the arms of a ternary" do
    result = CoverageSpecs.branch_coverage(<<~'RUBY')
      x = 1
      x.zero? ? :zero : :nonzero
    RUBY

    result.should == {
      [:if, 0, 2, 0, 2, 26] => {
        [:then, 1, 2, 10, 2, 15] => 0,
        [:else, 2, 2, 18, 2, 26] => 1
      }
    }
  end

  it "reports a modifier if with an else arm that spans the whole statement" do
    result = CoverageSpecs.branch_coverage(<<~'RUBY')
      x = 1
      x = 2 if x > 0
    RUBY

    result.should == {
      [:if, 0, 2, 0, 2, 14] => {
        [:then, 1, 2, 0, 2, 5] => 1,
        [:else, 2, 2, 0, 2, 14] => 0
      }
    }
  end

  it "reports the arms of an unless, the else first" do
    result = CoverageSpecs.branch_coverage(<<~'RUBY')
      x = 1
      unless x > 0
        :a
      else
        :b
      end
    RUBY

    result.should == {
      [:unless, 0, 2, 0, 6, 3] => {
        [:else, 1, 5, 2, 5, 4] => 1,
        [:then, 2, 3, 2, 3, 4] => 0
      }
    }
  end

  it "reports a modifier unless with an else arm that spans the whole statement" do
    result = CoverageSpecs.branch_coverage(<<~'RUBY')
      x = 1
      x = 2 unless x < 100
    RUBY

    result.should == {
      [:unless, 0, 2, 0, 2, 20] => {
        [:else, 1, 2, 0, 2, 20] => 1,
        [:then, 2, 2, 0, 2, 5] => 0
      }
    }
  end

  it "reports the when and else arms of a case" do
    result = CoverageSpecs.branch_coverage(<<~'RUBY')
      [0, 1, 2, 3].each do |x|
        case x
        when 0 then :none
        when 1, 2
          :few
        else
          :many
        end
      end
    RUBY

    result.should == {
      [:case, 0, 2, 2, 8, 5] => {
        [:when, 1, 3, 14, 3, 19] => 1,
        [:when, 2, 5, 4, 5, 8] => 2,
        [:else, 3, 7, 4, 7, 9] => 1
      }
    }
  end

  it "reports an else arm that spans the whole case when its when arms have none" do
    result = CoverageSpecs.branch_coverage(<<~'RUBY')
      x = 1
      case x
      when 0 then :none
      end
    RUBY

    result.should == {
      [:case, 0, 2, 0, 4, 3] => {
        [:when, 1, 3, 12, 3, 17] => 0,
        [:else, 2, 2, 0, 4, 3] => 1
      }
    }
  end

  it "reports the in and else arms of a case" do
    result = CoverageSpecs.branch_coverage(<<~'RUBY')
      x = 1
      case x
      in String then :string
      else
        :other
      end
    RUBY

    result.should == {
      [:case, 0, 2, 0, 6, 3] => {
        [:in, 1, 3, 15, 3, 22] => 0,
        [:else, 2, 5, 2, 5, 8] => 1
      }
    }
  end

  it "reports an else arm that spans the whole case when its in arms have none" do
    result = CoverageSpecs.branch_coverage(<<~'RUBY')
      [20, 3, 4].each do |x|
        case x
        in Integer => n if n > 10 then :large
        in Integer
          :small
        end
      end
    RUBY

    result.should == {
      [:case, 0, 2, 2, 6, 5] => {
        [:in, 1, 3, 33, 3, 39] => 1,
        [:in, 2, 5, 4, 5, 10] => 2,
        [:else, 3, 2, 2, 6, 5] => 0
      }
    }
  end

  it "reports the body of a while" do
    result = CoverageSpecs.branch_coverage(<<~'RUBY')
      x = 3
      while x > 0
        x -= 1
      end
    RUBY

    result.should == {
      [:while, 0, 2, 0, 4, 3] => {
        [:body, 1, 3, 2, 3, 8] => 3
      }
    }
  end

  it "reports the body of a modifier while" do
    result = CoverageSpecs.branch_coverage(<<~'RUBY')
      x = 3
      x -= 1 while x > 0
    RUBY

    result.should == {
      [:while, 0, 2, 0, 2, 18] => {
        [:body, 1, 2, 0, 2, 6] => 3
      }
    }
  end

  it "reports the body of an until" do
    result = CoverageSpecs.branch_coverage(<<~'RUBY')
      x = 0
      until x > 2
        x += 1
      end
    RUBY

    result.should == {
      [:until, 0, 2, 0, 4, 3] => {
        [:body, 1, 3, 2, 3, 8] => 3
      }
    }
  end

  it "reports the body of a modifier until" do
    result = CoverageSpecs.branch_coverage(<<~'RUBY')
      x = 0
      x += 1 until x > 2
    RUBY

    result.should == {
      [:until, 0, 2, 0, 2, 18] => {
        [:body, 1, 2, 0, 2, 6] => 3
      }
    }
  end

  it "reports a safe navigation with both arms spanning the call" do
    result = CoverageSpecs.branch_coverage(<<~'RUBY')
      [nil, -2, 3].each do |x|
        x&.abs
      end
    RUBY

    result.should == {
      [:"&.", 0, 2, 2, 2, 8] => {
        [:then, 1, 2, 2, 2, 8] => 2,
        [:else, 2, 2, 2, 2, 8] => 1
      }
    }
  end

  it "ends a safe navigation with arguments after its closing parenthesis" do
    result = CoverageSpecs.branch_coverage(<<~'RUBY')
      o = b = nil
      o&.foo(1, &b)
    RUBY

    result.should == {
      [:"&.", 0, 2, 0, 2, 13] => {
        [:then, 1, 2, 0, 2, 13] => 0,
        [:else, 2, 2, 0, 2, 13] => 1
      }
    }
  end

  it "ends a safe navigation before its brace block" do
    result = CoverageSpecs.branch_coverage(<<~'RUBY')
      o = nil
      o&.foo { 1 }
    RUBY

    result.should == {
      [:"&.", 0, 2, 0, 2, 6] => {
        [:then, 1, 2, 0, 2, 6] => 0,
        [:else, 2, 2, 0, 2, 6] => 1
      }
    }
  end

  it "ends a safe navigation before its do block" do
    result = CoverageSpecs.branch_coverage(<<~'RUBY')
      o = nil
      o&.foo(1) do 1 end
    RUBY

    result.should == {
      [:"&.", 0, 2, 0, 2, 9] => {
        [:then, 1, 2, 0, 2, 9] => 0,
        [:else, 2, 2, 0, 2, 9] => 1
      }
    }
  end

  it "ends an arm that is a call with a brace block after the block" do
    result = CoverageSpecs.branch_coverage(<<~'RUBY')
      x = true
      x ? [1].map { |v| v } : 0
    RUBY

    result.should == {
      [:if, 0, 2, 0, 2, 25] => {
        [:then, 1, 2, 4, 2, 21] => 1,
        [:else, 2, 2, 24, 2, 25] => 0
      }
    }
  end

  it "ends an arm that is a call with a do block after the block" do
    result = CoverageSpecs.branch_coverage(<<~'RUBY')
      x = true
      x ? [1].each do |v| v end : 0
    RUBY

    result.should == {
      [:if, 0, 2, 0, 2, 29] => {
        [:then, 1, 2, 4, 2, 25] => 1,
        [:else, 2, 2, 28, 2, 29] => 0
      }
    }
  end

  it "ends an arm that is a chain of calls after the block of the last call" do
    result = CoverageSpecs.branch_coverage(<<~'RUBY')
      x = true
      x ? [1].each_slice(1).map { _1 } : 0
    RUBY

    result.should == {
      [:if, 0, 2, 0, 2, 36] => {
        [:then, 1, 2, 4, 2, 32] => 1,
        [:else, 2, 2, 35, 2, 36] => 0
      }
    }
  end

  it "reports an arm that is a lambda literal from its arrow to the end of its body" do
    result = CoverageSpecs.branch_coverage(<<~'RUBY')
      x = true
      x ? -> { 1 } : 2
    RUBY

    result.should == {
      [:if, 0, 2, 0, 2, 16] => {
        [:then, 1, 2, 4, 2, 12] => 1,
        [:else, 2, 2, 15, 2, 16] => 0
      }
    }
  end

  it "reports an arm that is a character literal" do
    result = CoverageSpecs.branch_coverage(<<~'RUBY')
      x = true
      x ? ?a : ?b
    RUBY

    result.should == {
      [:if, 0, 2, 0, 2, 11] => {
        [:then, 1, 2, 4, 2, 6] => 1,
        [:else, 2, 2, 9, 2, 11] => 0
      }
    }
  end

  it "reports an arm that is a heredoc as its opening" do
    result = CoverageSpecs.branch_coverage(<<~'RUBY')
      x = true
      y = x ? <<~A : 2
        a
      A
    RUBY

    result.should == {
      [:if, 0, 2, 4, 2, 16] => {
        [:then, 1, 2, 8, 2, 12] => 1,
        [:else, 2, 2, 15, 2, 16] => 0
      }
    }
  end

  it "reports an arm that is an END block" do
    result = CoverageSpecs.branch_coverage(<<~'RUBY')
      x = true
      if x
        END { }
      end
    RUBY

    result.should == {
      [:if, 0, 2, 0, 4, 3] => {
        [:then, 1, 3, 2, 3, 9] => 1,
        [:else, 2, 2, 0, 4, 3] => 0
      }
    }
  end

  it "reports no branch for a conditional on a literal" do
    result = CoverageSpecs.branch_coverage(<<~'RUBY')
      :a if true
      :b if false
      :c if nil
      :d if 1
      :e unless true
      true ? 1 : 2
    RUBY

    result.should == {}
  end

  it "reports no branch of the code that a literal condition leaves unreachable" do
    result = CoverageSpecs.branch_coverage(<<~'RUBY')
      if false
        x = 1
        x ? 1 : 2
      end
    RUBY

    result.should == {}
  end

  ruby_version_is "3.4" do
    it "reports an elsif as an if that is the else arm of the one before" do
      skip "parse.y" if parse_y?

      result = CoverageSpecs.branch_coverage(<<~'RUBY')
        [1, -1, -2].each do |x|
          if x > 0
            :positive
          elsif x < 0
            :negative
          else
            :zero
          end
        end
      RUBY

      result.should == {
        [:if, 0, 2, 2, 8, 5] => {
          [:then, 1, 3, 4, 3, 13] => 1,
          [:else, 2, 4, 2, 8, 5] => 2
        },
        [:if, 3, 4, 2, 8, 5] => {
          [:then, 4, 5, 4, 5, 13] => 2,
          [:else, 5, 7, 4, 7, 9] => 0
        }
      }
    end

    it "ends a safe navigation before its empty parentheses" do
      skip "parse.y" if parse_y?

      result = CoverageSpecs.branch_coverage(<<~'RUBY')
        o = nil
        o&.foo()
      RUBY

      ruby_version_is ""..."4.1" do
        result.should == {
          [:"&.", 0, 2, 0, 2, 6] => {
            [:then, 1, 2, 0, 2, 6] => 0,
            [:else, 2, 2, 0, 2, 6] => 1
          }
        }
      end
      ruby_version_is "4.1" do
        result.should == {
          [:"&.", 0, 2, 0, 2, 8] => {
            [:then, 1, 2, 0, 2, 8] => 0,
            [:else, 2, 2, 0, 2, 8] => 1
          }
        }
      end
    end

    it "ends a safe navigation before a block argument that is its only argument" do
      skip "parse.y" if parse_y?

      result = CoverageSpecs.branch_coverage(<<~'RUBY')
        o = b = nil
        o&.foo(&b)
      RUBY

      ruby_version_is ""..."4.1" do
        result.should == {
          [:"&.", 0, 2, 0, 2, 6] => {
            [:then, 1, 2, 0, 2, 6] => 0,
            [:else, 2, 2, 0, 2, 6] => 1
          }
        }
      end
      ruby_version_is "4.1" do
        result.should == {
          [:"&.", 0, 2, 0, 2, 10] => {
            [:then, 1, 2, 0, 2, 10] => 0,
            [:else, 2, 2, 0, 2, 10] => 1
          }
        }
      end
    end

    it "ends a safe navigation without parentheses before its block argument" do
      skip "parse.y" if parse_y?

      result = CoverageSpecs.branch_coverage(<<~'RUBY')
        o = b = nil
        o&.foo 1, &b
      RUBY

      result.should == {
        [:"&.", 0, 2, 0, 2, 8] => {
          [:then, 1, 2, 0, 2, 8] => 0,
          [:else, 2, 2, 0, 2, 8] => 1
        }
      }
    end

    it "reports no branch for a pattern match outside a case" do
      skip "parse.y" if parse_y?

      result = CoverageSpecs.branch_coverage(<<~'RUBY')
        a = 1
        a => Integer
        a in String
      RUBY

      result.should == {}
    end
  end
end
