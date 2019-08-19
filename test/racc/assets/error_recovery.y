# Regression test case for the bug discussed here:
# https://github.com/whitequark/parser/issues/93
# In short, a Racc-generated parser could go into an infinite loop when
# attempting error recovery at EOF

class InfiniteLoop

rule

  stmts: stmt
       | error stmt

  stmt: '%' stmt

end

---- inner

  def parse
    @errors = []
    do_parse
  end

  def next_token
    nil
  end

  def on_error(error_token, error_value, value_stack)
    # oh my, an error
    @errors << [error_token, error_value]
  end

---- footer

InfiniteLoop.new.parse
