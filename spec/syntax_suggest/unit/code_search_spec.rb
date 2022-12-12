# frozen_string_literal: true

require_relative "../spec_helper"

module SyntaxSuggest
  RSpec.describe CodeSearch do
    it "rexe regression" do
      lines = fixtures_dir.join("rexe.rb.txt").read.lines
      lines.delete_at(148 - 1)
      source = lines.join

      search = CodeSearch.new(source)
      search.call

      expect(search.invalid_blocks.join.strip).to eq(<<~'EOM'.strip)
        class Lookups
      EOM
    end

    it "squished do regression" do
      source = <<~'EOM'
        def call
          trydo

            @options = CommandLineParser.new.parse

            options.requires.each { |r| require!(r) }
            load_global_config_if_exists
            options.loads.each { |file| load(file) }

            @user_source_code = ARGV.join(' ')
            @user_source_code = 'self' if @user_source_code == ''

            @callable = create_callable

            init_rexe_context
            init_parser_and_formatters

            # This is where the user's source code will be executed; the action will in turn call `execute`.
            lookup_action(options.input_mode).call unless options.noop

            output_log_entry
          end # one
        end # two
      EOM

      search = CodeSearch.new(source)
      search.call

      expect(search.invalid_blocks.join).to eq(<<~'EOM'.indent(2))
        trydo
        end # one
      EOM
    end

    it "regression test ambiguous end" do
      source = <<~'EOM'
        def call          # 0
            print "lol"   # 1
          end # one       # 2
        end # two         # 3
      EOM

      search = CodeSearch.new(source)
      search.call

      expect(search.invalid_blocks.join).to eq(<<~'EOM')
        end # two         # 3
      EOM
    end

    it "regression dog test" do
      source = <<~'EOM'
        class Dog
          def bark
            puts "woof"
        end
      EOM
      search = CodeSearch.new(source)
      search.call

      expect(search.invalid_blocks.join).to eq(<<~'EOM')
        class Dog
      EOM
      expect(search.invalid_blocks.first.lines.length).to eq(4)
    end

    it "handles mismatched |" do
      source = <<~EOM
        class Blerg
          Foo.call do |a
          end # one

          puts lol
          class Foo
          end # two
        end # three
      EOM
      search = CodeSearch.new(source)
      search.call

      expect(search.invalid_blocks.join).to eq(<<~'EOM'.indent(2))
        Foo.call do |a
        end # one
      EOM
    end

    it "handles mismatched }" do
      source = <<~EOM
        class Blerg
          Foo.call do {

          puts lol
          class Foo
          end # two
        end # three
      EOM
      search = CodeSearch.new(source)
      search.call

      expect(search.invalid_blocks.join).to eq(<<~'EOM'.indent(2))
        Foo.call do {
      EOM
    end

    it "handles no spaces between blocks and trailing slash" do
      source = <<~'EOM'
        require "rails_helper"
        RSpec.describe Foo, type: :model do
          describe "#bar" do
            context "context" do
              it "foos the bar with a foo and then bazes the foo with a bar to"\
                "fooify the barred bar" do
                travel_to DateTime.new(2020, 10, 1, 10, 0, 0) do
                  foo = build(:foo)
                end
              end
            end
          end
          describe "#baz?" do
            context "baz has barred the foo" do
              it "returns true" do # <== HERE
            end
          end
        end
      EOM

      search = CodeSearch.new(source)
      search.call

      expect(search.invalid_blocks.join.strip).to eq('it "returns true" do # <== HERE')
    end

    it "handles no spaces between blocks" do
      source = <<~'EOM'
        context "foo bar" do
          it "bars the foo" do
            travel_to DateTime.new(2020, 10, 1, 10, 0, 0) do
            end
          end
        end
        context "test" do
          it "should" do
        end
      EOM
      search = CodeSearch.new(source)
      search.call

      expect(search.invalid_blocks.join.strip).to eq('it "should" do')
    end

    it "records debugging steps to a directory" do
      Dir.mktmpdir do |dir|
        dir = Pathname(dir)
        search = CodeSearch.new(<<~'EOM', record_dir: dir)
          class OH
            def hello
            def hai
            end
          end
        EOM
        search.call

        expect(search.record_dir.entries.map(&:to_s)).to include("1-add-1-(3__4).txt")
        expect(search.record_dir.join("1-add-1-(3__4).txt").read).to include(<<~EOM)
            1  class OH
            2    def hello
          > 3    def hai
          > 4    end
            5  end
        EOM
      end
    end

    it "def with missing end" do
      search = CodeSearch.new(<<~'EOM')
        class OH
          def hello

          def hai
            puts "lol"
          end
        end
      EOM
      search.call

      expect(search.invalid_blocks.join.strip).to eq("def hello")

      search = CodeSearch.new(<<~'EOM')
        class OH
          def hello

          def hai
          end
        end
      EOM
      search.call

      expect(search.invalid_blocks.join.strip).to eq("def hello")

      search = CodeSearch.new(<<~'EOM')
        class OH
          def hello
          def hai
          end
        end
      EOM
      search.call

      expect(search.invalid_blocks.join).to eq(<<~'EOM'.indent(2))
        def hello
      EOM
    end

    describe "real world cases" do
      it "finds hanging def in this project" do
        source_string = fixtures_dir.join("this_project_extra_def.rb.txt").read
        search = CodeSearch.new(source_string)
        search.call

        document = DisplayCodeWithLineNumbers.new(
          lines: search.code_lines.select(&:visible?),
          terminal: false,
          highlight_lines: search.invalid_blocks.flat_map(&:lines)
        ).call

        expect(document).to include(<<~'EOM')
          > 36      def filename
        EOM
      end

      it "Format Code blocks real world example" do
        search = CodeSearch.new(<<~'EOM')
          require 'rails_helper'

          RSpec.describe AclassNameHere, type: :worker do
            describe "thing" do
              context "when" do
                let(:thing) { stuff }
                let(:another_thing) { moarstuff }
                subject { foo.new.perform(foo.id, true) }

                it "stuff" do
                  subject

                  expect(foo.foo.foo).to eq(true)
                end
              end
            end # line 16 accidental end, but valid block

              context "stuff" do
                let(:thing) { create(:foo, foo: stuff) }
                let(:another_thing) { create(:stuff) }

                subject { described_class.new.perform(foo.id, false) }

                it "more stuff" do
                  subject

                  expect(foo.foo.foo).to eq(false)
                end
              end
            end # mismatched due to 16
          end
        EOM
        search.call

        document = DisplayCodeWithLineNumbers.new(
          lines: search.code_lines.select(&:visible?),
          terminal: false,
          highlight_lines: search.invalid_blocks.flat_map(&:lines)
        ).call

        expect(document).to include(<<~'EOM')
             1  require 'rails_helper'
             2
             3  RSpec.describe AclassNameHere, type: :worker do
          >  4    describe "thing" do
          > 16    end # line 16 accidental end, but valid block
          > 30    end # mismatched due to 16
            31  end
        EOM
      end
    end

    # For code that's not perfectly formatted, we ideally want to do our best
    # These examples represent the results that exist today, but I would like to improve upon them
    describe "needs improvement" do
      describe "mis-matched-indentation" do
        it "extra space before end" do
          search = CodeSearch.new(<<~'EOM')
            Foo.call
              def foo
                puts "lol"
                puts "lol"
               end # one
            end # two
          EOM
          search.call

          expect(search.invalid_blocks.join).to eq(<<~'EOM')
            Foo.call
            end # two
          EOM
        end

        it "stacked ends 2" do
          search = CodeSearch.new(<<~'EOM')
            def cat
              blerg
            end

            Foo.call do
            end # one
            end # two

            def dog
            end
          EOM
          search.call

          expect(search.invalid_blocks.join).to eq(<<~'EOM')
            Foo.call do
            end # one
            end # two

          EOM
        end

        it "stacked ends " do
          search = CodeSearch.new(<<~'EOM')
            Foo.call
              def foo
                puts "lol"
                puts "lol"
            end
            end
          EOM
          search.call

          expect(search.invalid_blocks.join).to eq(<<~'EOM')
            Foo.call
            end
          EOM
        end

        it "missing space before end" do
          search = CodeSearch.new(<<~'EOM')
            Foo.call

              def foo
                puts "lol"
                puts "lol"
             end
            end
          EOM
          search.call

          # expand-1 and expand-2 seem to be broken?
          expect(search.invalid_blocks.join).to eq(<<~'EOM')
            Foo.call
            end
          EOM
        end
      end
    end

    it "returns syntax error in outer block without inner block" do
      search = CodeSearch.new(<<~'EOM')
        Foo.call
          def foo
            puts "lol"
            puts "lol"
          end # one
        end # two
      EOM
      search.call

      expect(search.invalid_blocks.join).to eq(<<~'EOM')
        Foo.call
        end # two
      EOM
    end

    it "doesn't just return an empty `end`" do
      search = CodeSearch.new(<<~'EOM')
        Foo.call
        end
      EOM
      search.call

      expect(search.invalid_blocks.join).to eq(<<~'EOM')
        Foo.call
        end
      EOM
    end

    it "finds multiple syntax errors" do
      search = CodeSearch.new(<<~'EOM')
        describe "hi" do
          Foo.call
          end
        end

        it "blerg" do
          Bar.call
          end
        end
      EOM
      search.call

      expect(search.invalid_blocks.join).to eq(<<~'EOM'.indent(2))
        Foo.call
        end
        Bar.call
        end
      EOM
    end

    it "finds a typo def" do
      search = CodeSearch.new(<<~'EOM')
        defzfoo
          puts "lol"
        end
      EOM
      search.call

      expect(search.invalid_blocks.join).to eq(<<~'EOM')
        defzfoo
        end
      EOM
    end

    it "finds a mis-matched def" do
      search = CodeSearch.new(<<~'EOM')
        def foo
          def blerg
        end
      EOM
      search.call

      expect(search.invalid_blocks.join).to eq(<<~'EOM'.indent(2))
        def blerg
      EOM
    end

    it "finds a naked end" do
      search = CodeSearch.new(<<~'EOM')
        def foo
          end # one
        end # two
      EOM
      search.call

      expect(search.invalid_blocks.join).to eq(<<~'EOM'.indent(2))
        end # one
      EOM
    end

    it "returns when no invalid blocks are found" do
      search = CodeSearch.new(<<~'EOM')
        def foo
          puts 'lol'
        end
      EOM
      search.call

      expect(search.invalid_blocks).to eq([])
    end

    it "expands frontier by eliminating valid lines" do
      search = CodeSearch.new(<<~'EOM')
        def foo
          puts 'lol'
        end
      EOM
      search.create_blocks_from_untracked_lines

      expect(search.code_lines.join).to eq(<<~'EOM')
        def foo
        end
      EOM
    end
  end
end
