module RDoc; end

##
# A TokenStream is a list of tokens, gathered during the parse of some entity
# (say a method). Entities populate these streams by being registered with the
# lexer. Any class can collect tokens by including TokenStream. From the
# outside, you use such an object by calling the start_collecting_tokens
# method, followed by calls to add_token and pop_token.

module RDoc::TokenStream

  def token_stream
    @token_stream
  end

  def start_collecting_tokens
    @token_stream = []
  end

  def add_token(tk)
    @token_stream << tk
  end

  def add_tokens(tks)
    tks.each  {|tk| add_token(tk)}
  end

  def pop_token
    @token_stream.pop
  end

end

