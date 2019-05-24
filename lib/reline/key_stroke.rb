class Reline::KeyStroke
  using Module.new {
    refine Array do
      def start_with?(other)
        other.size <= size && other == self.take(other.size)
      end

      def bytes
        self
      end
    end
  }

  def initialize(config)
    @config = config
  end

  # Keystrokes of GNU Readline will timeout it with the specification of
  # "keyseq-timeout" when waiting for the 2nd character after the 1st one.
  # If the 2nd character comes after 1st ESC without timeout it has a
  # meta-property of meta-key to discriminate modified key with meta-key
  # from multibyte characters that come with 8th bit on.
  #
  # GNU Readline will wait for the 2nd character with "keyseq-timeout"
  # milli-seconds but wait forever after 3rd characters.
  def read_io(keyseq_timeout, &block)
    buffer = []
    loop do
      c = Reline::IOGate.getc
      buffer << c
      result = match_status(buffer)
      case result
      when :matched
        block.(expand(buffer).map{ |c| Reline::Key.new(c, c, false) })
        break
      when :matching
        if buffer.size == 1
          begin
            succ_c = nil
            Timeout.timeout(keyseq_timeout / 1000.0) {
              succ_c = Reline::IOGate.getc
            }
          rescue Timeout::Error # cancel matching only when first byte
            block.([Reline::Key.new(c, c, false)])
            break
          else
            if match_status(buffer.dup.push(succ_c)) == :unmatched
              if c == "\e".ord
                block.([Reline::Key.new(succ_c, succ_c | 0b10000000, true)])
              else
                block.([Reline::Key.new(c, c, false), Reline::Key.new(succ_c, succ_c, false)])
              end
              break
            else
              Reline::IOGate.ungetc(succ_c)
            end
          end
        end
      when :unmatched
        if buffer.size == 1 and c == "\e".ord
          read_escaped_key(keyseq_timeout, buffer, block)
        else
          block.(buffer.map{ |c| Reline::Key.new(c, c, false) })
        end
        break
      end
    end
  end

  def read_escaped_key(keyseq_timeout, buffer, block)
    begin
      escaped_c = nil
      Timeout.timeout(keyseq_timeout / 1000.0) {
        escaped_c = Reline::IOGate.getc
      }
    rescue Timeout::Error # independent ESC
      block.([Reline::Key.new(c, c, false)])
    else
      if escaped_c.nil?
        block.([Reline::Key.new(c, c, false)])
      elsif escaped_c >= 128 # maybe, first byte of multi byte
        block.([Reline::Key.new(c, c, false), Reline::Key.new(escaped_c, escaped_c, false)])
      elsif escaped_c == "\e".ord # escape twice
        block.([Reline::Key.new(c, c, false), Reline::Key.new(c, c, false)])
      else
        block.([Reline::Key.new(escaped_c, escaped_c | 0b10000000, true)])
      end
    end
  end

  def match_status(input)
    key_mapping.keys.select { |lhs|
      lhs.start_with? input
    }.tap { |it|
      return :matched  if it.size == 1 && (it.max_by(&:size)&.size&.== input.size)
      return :matching if it.size == 1 && (it.max_by(&:size)&.size&.!= input.size)
      return :matched  if it.max_by(&:size)&.size&.< input.size
      return :matching if it.size > 1
    }
    key_mapping.keys.select { |lhs|
      input.start_with? lhs
    }.tap { |it|
      return it.size > 0 ? :matched : :unmatched
    }
  end

  private

  def expand(input)
    lhs = key_mapping.keys.select { |lhs| input.start_with? lhs }.sort_by(&:size).reverse.first
    return input unless lhs
    rhs = key_mapping[lhs]

    case rhs
    when String
      rhs_bytes = rhs.bytes
      expand(expand(rhs_bytes) + expand(input.drop(lhs.size)))
    when Symbol
      [rhs] + expand(input.drop(lhs.size))
    end
  end

  def key_mapping
    @config[:key_mapping].transform_keys(&:bytes)
  end
end
