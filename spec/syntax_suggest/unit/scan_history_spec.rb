# frozen_string_literal: true

require_relative "../spec_helper"

module SyntaxSuggest
  RSpec.describe ScanHistory do
    it "retains commits" do
      source = <<~EOM
        class OH         #  0
          def lol        #  1
            print 'lol   #  2
          end            #  3

          def hello      #  5
            it "foo" do  #  6
          end            #  7

          def yolo       #  8
            print 'haha' #  9
          end            # 10
        end
      EOM

      code_lines = CleanDocument.new(source: source).call.lines
      block = CodeBlock.new(lines: code_lines[6])

      scanner = ScanHistory.new(code_lines: code_lines, block: block)
      scanner.scan(up: ->(_, _, _) { true }, down: ->(_, _, _) { true })

      expect(scanner.changed?).to be_truthy
      scanner.commit_if_changed
      expect(scanner.changed?).to be_falsey

      expect(scanner.lines).to eq(code_lines)

      scanner.stash_changes # Assert does nothing if changes are already committed
      expect(scanner.lines).to eq(code_lines)

      scanner.revert_last_commit

      expect(scanner.lines.join).to eq(code_lines[6].to_s)
    end

    it "is stashable" do
      source = <<~EOM
        class OH         #  0
          def lol        #  1
            print 'lol   #  2
          end            #  3

          def hello      #  5
            it "foo" do  #  6
          end            #  7

          def yolo       #  8
            print 'haha' #  9
          end            # 10
        end
      EOM

      code_lines = CleanDocument.new(source: source).call.lines
      block = CodeBlock.new(lines: code_lines[6])

      scanner = ScanHistory.new(code_lines: code_lines, block: block)
      scanner.scan(up: ->(_, _, _) { true }, down: ->(_, _, _) { true })

      expect(scanner.lines).to eq(code_lines)
      expect(scanner.changed?).to be_truthy
      expect(scanner.next_up).to be_falsey
      expect(scanner.next_down).to be_falsey

      scanner.stash_changes

      expect(scanner.changed?).to be_falsey

      expect(scanner.next_up).to eq(code_lines[5])
      expect(scanner.lines.join).to eq(code_lines[6].to_s)
      expect(scanner.next_down).to eq(code_lines[7])
    end

    it "doesnt change if you dont't change it" do
      source = <<~EOM
        class OH         #  0
          def lol        #  1
            print 'lol   #  2
          end            #  3

          def hello      #  5
            it "foo" do  #  6
          end            #  7

          def yolo       #  8
            print 'haha' #  9
          end            # 10
        end
      EOM

      code_lines = CleanDocument.new(source: source).call.lines
      block = CodeBlock.new(lines: code_lines[6])

      scanner = ScanHistory.new(code_lines: code_lines, block: block)

      lines = scanner.lines
      expect(scanner.changed?).to be_falsey
      expect(scanner.next_up).to eq(code_lines[5])
      expect(scanner.next_down).to eq(code_lines[7])

      expect(scanner.stash_changes.lines).to eq(lines)
      expect(scanner.revert_last_commit.lines).to eq(lines)

      expect(scanner.scan(up: ->(_, _, _) { false }, down: ->(_, _, _) { false }).lines).to eq(lines)
    end
  end
end
