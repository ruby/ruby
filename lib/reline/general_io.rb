require 'timeout'

class Reline::GeneralIO
  RAW_KEYSTROKE_CONFIG = {}

  @@buf = []

  def self.input=(val)
    @@input = val
  end

  def self.getc
    unless @@buf.empty?
      return @@buf.shift
    end
    c = nil
    loop do
      result = select([@@input], [], [], 0.1)
      next if result.nil?
      c = @@input.read(1)
      break
    end
    c&.ord
  end

  def self.ungetc(c)
    @@buf.unshift(c)
  end

  def self.get_screen_size
    [1, 1]
  end

  def self.cursor_pos
    Reline::CursorPos.new(1, 1)
  end

  def self.move_cursor_column(val)
  end

  def self.move_cursor_up(val)
  end

  def self.move_cursor_down(val)
  end

  def self.erase_after_cursor
  end

  def self.scroll_down(val)
  end

  def self.clear_screen
  end

  def self.set_screen_size(rows, columns)
  end

  def self.set_winch_handler(&handler)
  end

  def self.prep
  end

  def self.deprep(otio)
  end
end
