class Reline::KeyStroke
  ESC_BYTE = 27
  CSI_PARAMETER_BYTES_RANGE = 0x30..0x3f
  CSI_INTERMEDIATE_BYTES_RANGE = (0x20..0x2f)

  def initialize(config)
    @config = config
  end

  def match_status(input)
    if key_mapping.matching?(input)
      :matching
    elsif key_mapping.get(input)
      :matched
    elsif input[0] == ESC_BYTE
      match_unknown_escape_sequence(input, vi_mode: @config.editing_mode_is?(:vi_insert, :vi_command))
    elsif input.size == 1
      :matched
    else
      :unmatched
    end
  end

  def expand(input)
    matched_bytes = nil
    (1..input.size).each do |i|
      bytes = input.take(i)
      matched_bytes = bytes if match_status(bytes) != :unmatched
    end
    return [[], []] unless matched_bytes

    func = key_mapping.get(matched_bytes)
    if func.is_a?(Array)
      keys = func.map { |c| Reline::Key.new(c, c, false) }
    elsif func
      keys = [Reline::Key.new(func, func, false)]
    elsif matched_bytes.size == 1
      keys = [Reline::Key.new(matched_bytes.first, matched_bytes.first, false)]
    elsif matched_bytes.size == 2 && matched_bytes[0] == ESC_BYTE
      keys = [Reline::Key.new(matched_bytes[1], matched_bytes[1] | 0b10000000, true)]
    else
      keys = []
    end

    [keys, input.drop(matched_bytes.size)]
  end

  private

  # returns match status of CSI/SS3 sequence and matched length
  def match_unknown_escape_sequence(input, vi_mode: false)
    idx = 0
    return :unmatched unless input[idx] == ESC_BYTE
    idx += 1
    idx += 1 if input[idx] == ESC_BYTE

    case input[idx]
    when nil
      return :matching
    when 91 # == '['.ord
      # CSI sequence `ESC [ ... char`
      idx += 1
      idx += 1 while idx < input.size && CSI_PARAMETER_BYTES_RANGE.cover?(input[idx])
      idx += 1 while idx < input.size && CSI_INTERMEDIATE_BYTES_RANGE.cover?(input[idx])
    when 79 # == 'O'.ord
      # SS3 sequence `ESC O char`
      idx += 1
    else
      # `ESC char` or `ESC ESC char`
      return :unmatched if vi_mode
    end
    input[idx + 1] ? :unmatched : input[idx] ? :matched : :matching
  end

  def key_mapping
    @config.key_bindings
  end
end
