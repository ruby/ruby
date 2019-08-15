# frozen_string_literal: true
#
# $Id$
#
# Copyright (c) 2004,2005 Minero Aoki
#
# This program is free software.
# You can distribute and/or modify this program under the Ruby License.
# For details of Ruby License, see ruby/COPYING.
#

require 'ripper/core'

class Ripper

  # Tokenizes the Ruby program and returns an array of strings.
  #
  #   p Ripper.tokenize("def m(a) nil end")
  #      # => ["def", " ", "m", "(", "a", ")", " ", "nil", " ", "end"]
  #
  def Ripper.tokenize(src, filename = '-', lineno = 1)
    Lexer.new(src, filename, lineno).tokenize
  end

  # Tokenizes the Ruby program and returns an array of an array,
  # which is formatted like
  # <code>[[lineno, column], type, token, state]</code>.
  #
  #   require 'ripper'
  #   require 'pp'
  #
  #   pp Ripper.lex("def m(a) nil end")
  #   #=> [[[1,  0], :on_kw,     "def", Ripper::EXPR_FNAME                   ],
  #        [[1,  3], :on_sp,     " ",   Ripper::EXPR_FNAME                   ],
  #        [[1,  4], :on_ident,  "m",   Ripper::EXPR_ENDFN                   ],
  #        [[1,  5], :on_lparen, "(",   Ripper::EXPR_LABEL | Ripper::EXPR_BEG],
  #        [[1,  6], :on_ident,  "a",   Ripper::EXPR_ARG                     ],
  #        [[1,  7], :on_rparen, ")",   Ripper::EXPR_ENDFN                   ],
  #        [[1,  8], :on_sp,     " ",   Ripper::EXPR_BEG                     ],
  #        [[1,  9], :on_kw,     "nil", Ripper::EXPR_END                     ],
  #        [[1, 12], :on_sp,     " ",   Ripper::EXPR_END                     ],
  #        [[1, 13], :on_kw,     "end", Ripper::EXPR_END                     ]]
  #
  def Ripper.lex(src, filename = '-', lineno = 1)
    Lexer.new(src, filename, lineno).lex
  end

  class Lexer < ::Ripper   #:nodoc: internal use only
    State = Struct.new(:to_int, :to_s) do
      alias to_i to_int
      def initialize(i) super(i, Ripper.lex_state_name(i)).freeze end
      # def inspect; "#<#{self.class}: #{self}>" end
      alias inspect to_s
      def pretty_print(q) q.text(to_s) end
      def ==(i) super or to_int == i end
      def &(i) self.class.new(to_int & i) end
      def |(i) self.class.new(to_int | i) end
      def allbits?(i) to_int.allbits?(i) end
      def anybits?(i) to_int.anybits?(i) end
      def nobits?(i) to_int.nobits?(i) end
    end

    Elem = Struct.new(:pos, :event, :tok, :state, :message) do
      def initialize(pos, event, tok, state, message = nil)
        super(pos, event, tok, State.new(state), message)
      end

      def inspect
        "#<#{self.class}: #{event}@#{pos[0]}:#{pos[1]}:#{state}: #{tok.inspect}#{": " if message}#{message}>"
      end

      def pretty_print(q)
        q.group(2, "#<#{self.class}:", ">") {
          q.breakable
          q.text("#{event}@#{pos[0]}:#{pos[1]}")
          q.breakable
          q.text(state)
          q.breakable
          q.text("token: ")
          tok.pretty_print(q)
          if message
            q.breakable
            q.text("message: ")
            q.text(message)
          end
        }
      end

      def to_a
        a = super
        a.pop unless a.last
        a
      end
    end

    attr_reader :errors

    def tokenize
      parse().sort_by(&:pos).map(&:tok)
    end

    def lex
      parse().sort_by(&:pos).map(&:to_a)
    end

    # parse the code and returns elements including errors.
    def scan
      result = (parse() + errors + @stack.flatten).uniq.sort_by {|e| [*e.pos, (e.message ? -1 : 0)]}
      result.each_with_index do |e, i|
        if e.event == :on_parse_error and e.tok.empty? and (pre = result[i-1]) and
          pre.pos[0] == e.pos[0] and (pre.pos[1] + pre.tok.size) == e.pos[1]
          e.tok = pre.tok
          e.pos[1] = pre.pos[1]
          result[i-1] = e
          result[i] = pre
        end
      end
      result
    end

    def parse
      @errors = []
      @buf = []
      @stack = []
      super
      @buf.flatten!
      @buf
    end

    private

    unless SCANNER_EVENT_TABLE.key?(:ignored_sp)
      SCANNER_EVENT_TABLE[:ignored_sp] = 1
      SCANNER_EVENTS << :ignored_sp
      EVENTS << :ignored_sp
    end

    def on_heredoc_dedent(v, w)
      ignored_sp = []
      heredoc = @buf.last
      heredoc.each_with_index do |e, i|
        if Elem === e and e.event == :on_tstring_content and e.pos[1].zero?
          tok = e.tok.dup if w > 0 and /\A\s/ =~ e.tok
          if (n = dedent_string(e.tok, w)) > 0
            if e.tok.empty?
              e.tok = tok[0, n]
              e.event = :on_ignored_sp
              next
            end
            ignored_sp << [i, Elem.new(e.pos.dup, :on_ignored_sp, tok[0, n], e.state)]
            e.pos[1] += n
          end
        end
      end
      ignored_sp.reverse_each do |i, e|
        heredoc[i, 0] = [e]
      end
      v
    end

    def on_heredoc_beg(tok)
      @stack.push @buf
      buf = []
      @buf.push buf
      @buf = buf
      @buf.push Elem.new([lineno(), column()], __callee__, tok, state())
    end

    def on_heredoc_end(tok)
      @buf.push Elem.new([lineno(), column()], __callee__, tok, state())
      @buf = @stack.pop
    end

    def _push_token(tok)
      @buf.push Elem.new([lineno(), column()], __callee__, tok, state())
    end

    def on_error(mesg)
      @errors.push Elem.new([lineno(), column()], __callee__, token(), state(), mesg)
    end
    alias on_parse_error on_error
    alias compile_error on_error

    (SCANNER_EVENTS.map {|event|:"on_#{event}"} - private_instance_methods(false)).each do |event|
      alias_method event, :_push_token
    end
  end

  # [EXPERIMENTAL]
  # Parses +src+ and return a string which was matched to +pattern+.
  # +pattern+ should be described as Regexp.
  #
  #   require 'ripper'
  #
  #   p Ripper.slice('def m(a) nil end', 'ident')                   #=> "m"
  #   p Ripper.slice('def m(a) nil end', '[ident lparen rparen]+')  #=> "m(a)"
  #   p Ripper.slice("<<EOS\nstring\nEOS",
  #                  'heredoc_beg nl $(tstring_content*) heredoc_end', 1)
  #       #=> "string\n"
  #
  def Ripper.slice(src, pattern, n = 0)
    if m = token_match(src, pattern)
    then m.string(n)
    else nil
    end
  end

  def Ripper.token_match(src, pattern)   #:nodoc:
    TokenPattern.compile(pattern).match(src)
  end

  class TokenPattern   #:nodoc:

    class Error < ::StandardError # :nodoc:
    end
    class CompileError < Error # :nodoc:
    end
    class MatchError < Error # :nodoc:
    end

    class << self
      alias compile new
    end

    def initialize(pattern)
      @source = pattern
      @re = compile(pattern)
    end

    def match(str)
      match_list(::Ripper.lex(str))
    end

    def match_list(tokens)
      if m = @re.match(map_tokens(tokens))
      then MatchData.new(tokens, m)
      else nil
      end
    end

    private

    def compile(pattern)
      if m = /[^\w\s$()\[\]{}?*+\.]/.match(pattern)
        raise CompileError, "invalid char in pattern: #{m[0].inspect}"
      end
      buf = +''
      pattern.scan(/(?:\w+|\$\(|[()\[\]\{\}?*+\.]+)/) do |tok|
        case tok
        when /\w/
          buf.concat map_token(tok)
        when '$('
          buf.concat '('
        when '('
          buf.concat '(?:'
        when /[?*\[\])\.]/
          buf.concat tok
        else
          raise 'must not happen'
        end
      end
      Regexp.compile(buf)
    rescue RegexpError => err
      raise CompileError, err.message
    end

    def map_tokens(tokens)
      tokens.map {|pos,type,str| map_token(type.to_s.delete_prefix('on_')) }.join
    end

    MAP = {}
    seed = ('a'..'z').to_a + ('A'..'Z').to_a + ('0'..'9').to_a
    SCANNER_EVENT_TABLE.each do |ev, |
      raise CompileError, "[RIPPER FATAL] too many system token" if seed.empty?
      MAP[ev.to_s.delete_prefix('on_')] = seed.shift
    end

    def map_token(tok)
      MAP[tok]  or raise CompileError, "unknown token: #{tok}"
    end

    class MatchData # :nodoc:
      def initialize(tokens, match)
        @tokens = tokens
        @match = match
      end

      def string(n = 0)
        return nil unless @match
        match(n).join
      end

      private

      def match(n = 0)
        return [] unless @match
        @tokens[@match.begin(n)...@match.end(n)].map {|pos,type,str| str }
      end
    end

  end

end
