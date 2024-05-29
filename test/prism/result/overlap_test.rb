# frozen_string_literal: true

require_relative "../test_helper"

module Prism
  class OverlapTest < TestCase
    Fixture.each do |fixture|
      define_method(fixture.test_name) { assert_overlap(fixture) }
    end

    private

    # Check that the location ranges of each node in the tree are a superset of
    # their respective child nodes.
    def assert_overlap(fixture)
      queue = [Prism.parse_file(fixture.full_path).value]

      while (current = queue.shift)
        # We only want to compare parent/child location overlap in the case that
        # we are not looking at a heredoc. That's because heredoc locations are
        # special in that they only use the declaration of the heredoc.
        compare = !(current.is_a?(StringNode) ||
                    current.is_a?(XStringNode) ||
                    current.is_a?(InterpolatedStringNode) ||
                    current.is_a?(InterpolatedXStringNode)) ||
        !current.opening&.start_with?("<<")

        current.child_nodes.each do |child|
          # child_nodes can return nil values, so we need to skip those.
          next unless child

          # Now that we know we have a child node, add that to the queue.
          queue << child

          if compare
            assert_operator current.location.start_offset, :<=, child.location.start_offset
            assert_operator current.location.end_offset, :>=, child.location.end_offset
          end
        end
      end
    end
  end
end
