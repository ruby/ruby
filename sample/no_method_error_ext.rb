class RubyVM::AbstractSyntaxTree::Node
  def find(node_id)
    if node_id == self.node_id
      return self
    end

    children.compact.each do |c|
      next unless c.is_a?(RubyVM::AbstractSyntaxTree::Node)
      n = c.find(node_id)

      return n if n
    end

    return nil
  end
end

class NoMethodError
  prepend Module.new {
    def message
      if node
        super + "\n\n#{line}\n#{marker}"
      else
        super
      end
    end
  }

  private

  def line
    File.read(path).split("\n")[target_lineno - 1]
  end

  def marker
    " " * target_loc.dig(0, 1) + "^" * (target_loc.dig(1, 1) - target_loc.dig(0, 1))
  end

  def target_lineno
    target_loc.dig(0, 0)
  end

  def node
    RubyVM::AbstractSyntaxTree.parse_file(path).find(node_id)
  end

  def node_id
    backtrace_locations.first.node_id
  end

  def path
    backtrace_locations.first.absolute_path
  end

  def nd_recv
    node.children[0]
  end

  def nd_recv_last_loc
    [nd_recv.last_lineno, nd_recv.last_column]
  end

  def target_loc
    [nd_recv_last_loc, [node.last_lineno, node.last_column]]
  end
end

# Usage:
#
# * ./configure cflags=-DEXPERIMENTAL_ISEQ_NODE_ID --prefix=path/to/install && make
# * ./path/to/install/bin/ruby -r sample/no_method_error_ext.rb foo.rb
#
# $ cat err.rb
# analysis_result = { "data" => [] }
# analysis_result["data"].first["analysis"]
#
# $ ruby -r ./sample/no_method_error_ext.rb err.rb
# err.rb:2:in `<main>': undefined method `[]' for nil:NilClass (NoMethodError)
#
# analysis_result["data"].first["analysis"]
#                              ^^^^^^^^^^^^
