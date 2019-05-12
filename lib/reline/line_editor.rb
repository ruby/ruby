require 'reline/kill_ring'
require 'reline/unicode'

require 'tempfile'
require 'pathname'

class Reline::LineEditor
  # TODO: undo
  attr_reader :line
  attr_accessor :confirm_multiline_termination_proc
  attr_accessor :completion_proc
  attr_accessor :dig_perfect_match_proc
  attr_writer :retrieve_completion_block

  ARGUMENTABLE = %i{
    ed_delete_next_char
    ed_delete_prev_char
    ed_delete_prev_word
    ed_next_char
    ed_next_history
    ed_next_line#
    ed_prev_char
    ed_prev_history
    ed_prev_line#
    ed_prev_word
    ed_quoted_insert
    vi_to_column
    vi_next_word
    vi_prev_word
    vi_end_word
    vi_next_big_word
    vi_prev_big_word
    vi_end_big_word
    vi_next_char
    vi_delete_meta
    vi_paste_prev
    vi_paste_next
    vi_replace_char
  }

  VI_OPERATORS = %i{
    vi_change_meta
    vi_delete_meta
    vi_yank
  }

  VI_MOTIONS = %i{
    ed_prev_char
    ed_next_char
    vi_zero
    ed_move_to_beg
    ed_move_to_end
    vi_to_column
    vi_next_char
    vi_prev_char
    vi_next_word
    vi_prev_word
    vi_to_next_char
    vi_to_prev_char
    vi_end_word
    vi_next_big_word
    vi_prev_big_word
    vi_end_big_word
    vi_repeat_next_char
    vi_repeat_prev_char
  }

  module CompletionState
    NORMAL = :normal
    COMPLETION = :completion
    MENU = :menu
    JOURNEY = :journey
    PERFECT_MATCH = :perfect_match
  end

  CompletionJourneyData = Struct.new('CompletionJourneyData', :preposing, :postposing, :list, :pointer)
  MenuInfo = Struct.new('MenuInfo', :target, :list)

  def initialize(config, prompt = '', encoding = Encoding.default_external)
    @config = config
    @prompt = prompt
    @prompt_width = calculate_width(@prompt)
    @cursor = 0
    @cursor_max = 0
    @byte_pointer = 0
    @encoding = encoding
    @buffer_of_lines = [String.new(encoding: @encoding)]
    @line_index = 0
    @previous_line_index = nil
    @line = @buffer_of_lines[0]
    @is_multiline = false
    @finished = false
    @cleared = false
    @rerender_all = false
    @is_confirm_multiline_termination = false
    @history_pointer = nil
    @line_backup_in_history = nil
    @kill_ring = Reline::KillRing.new
    @vi_clipboard = ''
    @vi_arg = nil
    @multibyte_buffer = String.new(encoding: 'ASCII-8BIT')
    @meta_prefix = false
    @waiting_proc = nil
    @waiting_operator_proc = nil
    @completion_journey_data = nil
    @completion_state = CompletionState::NORMAL
    @perfect_matched = nil
    @first_line_started_from = 0
    @move_up = 0
    @started_from = 0
    @highest_in_this = 1
    @highest_in_all = 1
    @menu_info = nil
  end

  def multiline_on
    @is_multiline = true
  end

  def multiline_off
    @is_multiline = false
  end

  private def insert_new_line(cursor_line, next_line)
    @line = cursor_line
    @buffer_of_lines.insert(@line_index + 1, String.new(next_line, encoding: @encoding))
    @previous_line_index = @line_index
    @line_index += 1
  end

  private def calculate_height_by_width(width)
    return 1 if width.zero?
    height = 1
    max_width = @screen_size.last
    while width > max_width * height
      height += 1
    end
    height += 1 if (width % max_width).zero?
    height
  end

  private def split_by_width(str, max_width)
    lines = [String.new(encoding: @encoding)]
    width = 0
    str.encode(Encoding::UTF_8).grapheme_clusters.each do |gc|
      mbchar_width = Reline::Unicode.get_mbchar_width(gc)
      width += mbchar_width
      if width > max_width
        width = mbchar_width
        lines << String.new(encoding: @encoding)
      end
      lines.last << gc
    end
    # The cursor moves to next line in first
    lines << String.new(encoding: @encoding) if width == max_width
    lines
  end

  private def scroll_down(val)
    if val <= @rest_height
      Reline.move_cursor_down(val)
      @rest_height -= val
    else
      Reline.move_cursor_down(@rest_height)
      Reline.scroll_down(val - @rest_height)
      @rest_height = 0
    end
  end

  private def move_cursor_up(val)
    if val > 0
      Reline.move_cursor_up(val)
      @rest_height += val
    elsif val < 0
      move_cursor_down(-val)
    end
  end

  private def move_cursor_down(val)
    if val > 0
      Reline.move_cursor_down(val)
      @rest_height -= val
      @rest_height = 0 if @rest_height < 0
    elsif val < 0
      move_cursor_up(-val)
    end
  end

  private def calculate_nearest_cursor
    @cursor_max = calculate_width(line)
    new_cursor = 0
    new_byte_pointer = 0
    height = 1
    max_width = @screen_size.last
    @line.encode(Encoding::UTF_8).grapheme_clusters.each do |gc|
      mbchar_width = Reline::Unicode.get_mbchar_width(gc)
      now = new_cursor + mbchar_width
      if now > @cursor_max or now > @cursor
        break
      end
      new_cursor += mbchar_width
      if new_cursor > max_width * height
        height += 1
      end
      new_byte_pointer += gc.bytesize
    end
    @started_from = height - 1
    @cursor = new_cursor
    @byte_pointer = new_byte_pointer
  end

  def rerender # TODO: support physical and logical lines
    @rest_height ||= (Reline.get_screen_size.first - 1) - Reline.cursor_pos.y
    @screen_size ||= Reline.get_screen_size
    if @menu_info
      puts
      @menu_info.list.each do |item|
        puts item
      end
      @menu_info = nil
    end
    return if @line.nil?
    if @vi_arg
      prompt = "(arg: #{@vi_arg}) "
      prompt_width = calculate_width(prompt)
    else
      prompt = @prompt
      prompt_width = @prompt_width
    end
    if @cleared
      Reline.clear_screen
      @cleared = false
      back = 0
      @buffer_of_lines.each_with_index do |line, index|
        line = @line if index == @line_index
        height = render_partial(prompt, prompt_width, line, false)
        if index < (@buffer_of_lines.size - 1)
          move_cursor_down(height)
          back += height
        end
      end
      move_cursor_up(back)
      move_cursor_down(@first_line_started_from + @started_from)
      Reline.move_cursor_column((prompt_width + @cursor) % @screen_size.last)
      return
    end
    # FIXME: end of logical line sometimes breaks
    if @previous_line_index
      previous_line = @line
      all_height = @buffer_of_lines.inject(0) { |result, line|
        result + calculate_height_by_width(@prompt_width + calculate_width(line))
      }
      diff = all_height - @highest_in_all
      if diff > 0
        @highest_in_all = all_height
        scroll_down(diff)
        move_cursor_up(@first_line_started_from + @started_from + diff)
        back = 0
        @buffer_of_lines.each_with_index do |line, index|
          line = @line if index == @previous_line_index
          height = render_partial(prompt, prompt_width, line, false)
          if index < (@buffer_of_lines.size - 1)
            move_cursor_down(height)
            back += height
          end
        end
        move_cursor_up(back)
      else
        render_partial(prompt, prompt_width, previous_line)
        move_cursor_up(@first_line_started_from + @started_from)
      end
      @buffer_of_lines[@previous_line_index] = @line
      @line = @buffer_of_lines[@line_index]
      @first_line_started_from =
        if @line_index.zero?
          0
        else
          @buffer_of_lines[0..(@line_index - 1)].inject(0) { |result, line|
            result + calculate_height_by_width(@prompt_width + calculate_width(line))
          }
        end
      move_cursor_down(@first_line_started_from)
      calculate_nearest_cursor
      @highest_in_this = calculate_height_by_width(@prompt_width + @cursor_max)
      @previous_line_index = nil
    elsif @rerender_all
      move_cursor_up(@first_line_started_from + @started_from)
      Reline.move_cursor_column(0)
      back = 0
      @buffer_of_lines.each do |line|
        width = prompt_width + calculate_width(line)
        height = calculate_height_by_width(width)
        back += height
      end
      if back > @highest_in_all
        scroll_down(back)
        move_cursor_up(back)
      elsif back < @highest_in_all
        scroll_down(back)
        Reline.erase_after_cursor
        (@highest_in_all - back).times do
          scroll_down(1)
          Reline.erase_after_cursor
        end
        move_cursor_up(@highest_in_all)
      end
      @buffer_of_lines.each_with_index do |line, index|
        render_partial(prompt, prompt_width, line, false)
        if index < (@buffer_of_lines.size - 1)
          move_cursor_down(1)
        end
      end
      move_cursor_up(back - 1)
      @highest_in_all = back
      @highest_in_this = calculate_height_by_width(@prompt_width + @cursor_max)
      @first_line_started_from =
        if @line_index.zero?
          0
        else
          @buffer_of_lines[0..(@line_index - 1)].inject(0) { |result, line|
            result + calculate_height_by_width(@prompt_width + calculate_width(line))
          }
        end
      move_cursor_down(@first_line_started_from)
      @rerender_all = false
    end
    render_partial(prompt, prompt_width, @line) if !@is_multiline or !finished?
    if @is_multiline and finished?
      scroll_down(1) unless @buffer_of_lines.last.empty?
      Reline.move_cursor_column(0)
      Reline.erase_after_cursor
    end
  end

  private def render_partial(prompt, prompt_width, line_to_render, with_control = true)
    whole_line = prompt + (line_to_render.nil? ? '' : line_to_render)
    visual_lines = split_by_width(whole_line, @screen_size.last)
    if with_control
      if visual_lines.size > @highest_in_this
        diff = visual_lines.size - @highest_in_this
        scroll_down(diff)
        @highest_in_all += diff
        @highest_in_this = visual_lines.size
        move_cursor_up(1)
      end
      move_cursor_up(@started_from)
      @started_from = calculate_height_by_width(prompt_width + @cursor) - 1
    end
    visual_lines.each_with_index do |line, index|
      Reline.move_cursor_column(0)
      escaped_print line
      Reline.erase_after_cursor
      move_cursor_down(1) if index < (visual_lines.size - 1)
    end
    if with_control
      if finished?
        puts
      else
        move_cursor_up((visual_lines.size - 1) - @started_from)
        Reline.move_cursor_column((prompt_width + @cursor) % @screen_size.last)
      end
    end
    visual_lines.size
  end

  def editing_mode
    @config.editing_mode
  end

  private def escaped_print(str)
    print str.chars.map { |gr|
      escaped = Reline::Unicode::EscapedPairs[gr.ord]
      if escaped
        escaped
      else
        gr
      end
    }.join
  end

  private def menu(target, list)
    @menu_info = MenuInfo.new(target, list)
  end

  private def complete_internal_proc(list, is_menu)
    preposing, target, postposing = @retrieve_completion_block.(@line, @byte_pointer)
    list = list.select { |i| i&.start_with?(target) }
    if is_menu
      menu(target, list)
      return nil
    end
    completed = list.inject { |memo, item|
      memo_mbchars = memo.unicode_normalize.grapheme_clusters
      item_mbchars = item.unicode_normalize.grapheme_clusters
      size = [memo_mbchars.size, item_mbchars.size].min
      result = ''
      size.times do |i|
        if memo_mbchars[i] == item_mbchars[i]
          result << memo_mbchars[i]
        else
          break
        end
      end
      result
    }
    [target, preposing, completed, postposing]
  end

  private def complete(list)
    case @completion_state
    when CompletionState::NORMAL, CompletionState::JOURNEY
      @completion_state = CompletionState::COMPLETION
    when CompletionState::PERFECT_MATCH
      @dig_perfect_match_proc&.(@perfect_matched)
    end
    is_menu = (@completion_state == CompletionState::MENU)
    result = complete_internal_proc(list, is_menu)
    return if result.nil?
    target, preposing, completed, postposing = result
    return if completed.nil?
    if target <= completed and (@completion_state == CompletionState::COMPLETION or @completion_state == CompletionState::PERFECT_MATCH)
      @completion_state = CompletionState::MENU
      if list.include?(completed)
        @completion_state = CompletionState::PERFECT_MATCH
        @perfect_matched = completed
      end
      if target < completed
        @line = preposing + completed + postposing
        line_to_pointer = preposing + completed
        @cursor_max = calculate_width(@line)
        @cursor = calculate_width(line_to_pointer)
        @byte_pointer = line_to_pointer.bytesize
      end
    end
  end

  private def move_completed_list(list, direction)
    case @completion_state
    when CompletionState::NORMAL, CompletionState::COMPLETION, CompletionState::MENU
      @completion_state = CompletionState::JOURNEY
      result = @retrieve_completion_block.(@line, @byte_pointer)
      return if result.nil?
      preposing, target, postposing = result
      @completion_journey_data = CompletionJourneyData.new(
        preposing, postposing,
        [target] + list.select{ |item| item.start_with?(target) }, 0)
      @completion_state = CompletionState::JOURNEY
    else
      case direction
      when :up
        @completion_journey_data.pointer -= 1
        if @completion_journey_data.pointer < 0
          @completion_journey_data.pointer = @completion_journey_data.list.size - 1
        end
      when :down
        @completion_journey_data.pointer += 1
        if @completion_journey_data.pointer >= @completion_journey_data.list.size
          @completion_journey_data.pointer = 0
        end
      end
      completed = @completion_journey_data.list[@completion_journey_data.pointer]
      @line = @completion_journey_data.preposing + completed + @completion_journey_data.postposing
      line_to_pointer = @completion_journey_data.preposing + completed
      @cursor_max = calculate_width(@line)
      @cursor = calculate_width(line_to_pointer)
      @byte_pointer = line_to_pointer.bytesize
    end
  end

  private def run_for_operators(key, method_symbol, &block)
    if @waiting_operator_proc
      if VI_MOTIONS.include?(method_symbol)
        old_cursor, old_byte_pointer = @cursor, @byte_pointer
        block.()
        unless @waiting_proc
          cursor_diff, byte_pointer_diff = @cursor - old_cursor, @byte_pointer - old_byte_pointer
          @cursor, @byte_pointer = old_cursor, old_byte_pointer
          @waiting_operator_proc.(cursor_diff, byte_pointer_diff)
        else
          old_waiting_proc = @waiting_proc
          old_waiting_operator_proc = @waiting_operator_proc
          @waiting_proc = proc { |key|
            old_cursor, old_byte_pointer = @cursor, @byte_pointer
            old_waiting_proc.(key)
            cursor_diff, byte_pointer_diff = @cursor - old_cursor, @byte_pointer - old_byte_pointer
            @cursor, @byte_pointer = old_cursor, old_byte_pointer
            @waiting_operator_proc.(cursor_diff, byte_pointer_diff)
            @waiting_operator_proc = old_waiting_operator_proc
          }
        end
      else
        # Ignores operator when not motion is given.
        block.()
      end
      @waiting_operator_proc = nil
    else
      block.()
    end
  end

  private def process_key(key, method_symbol, method_obj)
    if @vi_arg
      if key.chr =~ /[0-9]/
        ed_argument_digit(key)
      else
        if ARGUMENTABLE.include?(method_symbol) and method_obj
          run_for_operators(key, method_symbol) do
            method_obj.(key, arg: @vi_arg)
          end
        elsif @waiting_proc
          @waiting_proc.(key)
        elsif method_obj
          method_obj.(key)
        else
          ed_insert(key)
        end
        @kill_ring.process
        @vi_arg = nil
      end
    elsif @waiting_proc
      @waiting_proc.(key)
      @kill_ring.process
    elsif method_obj
      if method_symbol == :ed_argument_digit
        method_obj.(key)
      else
        run_for_operators(key, method_symbol) do
          method_obj.(key)
        end
      end
      @kill_ring.process
    else
      ed_insert(key)
    end
  end

  private def normal_char(key)
    method_symbol = method_obj = nil
    @multibyte_buffer << key
    if @multibyte_buffer.size > 1
      if @multibyte_buffer.dup.force_encoding(@encoding).valid_encoding?
        key = @multibyte_buffer.dup.force_encoding(@encoding)
        @multibyte_buffer.clear
      else
        # invalid
        return
      end
    else # single byte
      return if key >= 128 # maybe, first byte of multi byte
      if @meta_prefix
        key |= 0b10000000 if key.nobits?(0b10000000)
        @meta_prefix = false
      end
      method_symbol = @config.editing_mode.get_method(key)
      if key.allbits?(0b10000000) and method_symbol == :ed_unassigned
        return # This is unknown input
      end
      if method_symbol and respond_to?(method_symbol, true)
        method_obj = method(method_symbol)
      end
      @multibyte_buffer.clear
    end
    process_key(key, method_symbol, method_obj)
    if @config.editing_mode_is?(:vi_command) and @cursor > 0 and @cursor == @cursor_max
      byte_size = Reline::Unicode.get_prev_mbchar_size(@line, @byte_pointer)
      @byte_pointer -= byte_size
      mbchar = @line.byteslice(@byte_pointer, byte_size)
      width = Reline::Unicode.get_mbchar_width(mbchar)
      @cursor -= width
    end
  end

  def input_key(key)
    completion_occurs = false
    if @config.editing_mode_is?(:emacs, :vi_insert) and key == "\C-i".ord
      result = @completion_proc&.(@line)
      if result.is_a?(Array)
        completion_occurs = true
        complete(result)
      end
    elsif @config.editing_mode_is?(:vi_insert) and ["\C-p".ord, "\C-n".ord].include?(key)
      result = @completion_proc&.(@line)
      if result.is_a?(Array)
        completion_occurs = true
        move_completed_list(result, "\C-p".ord == key ? :up : :down)
      end
    elsif @config.editing_mode_is?(:emacs) and key == "\e".ord # meta key
      if @meta_prefix
        # escape twice
        @meta_prefix = false
        @kill_ring.process
      else
        @meta_prefix = true
      end
    elsif @config.editing_mode_is?(:vi_command) and key == "\e".ord
      # suppress ^[ when command_mode
    elsif Symbol === key and respond_to?(key, true)
      process_key(key, key, method(key))
    else
      normal_char(key)
    end
    unless completion_occurs
      @completion_state = CompletionState::NORMAL
    end
    if @is_confirm_multiline_termination and @confirm_multiline_termination_proc
      @is_confirm_multiline_termination = false
      temp_buffer = @buffer_of_lines.dup
      if @previous_line_index and @line_index == (@buffer_of_lines.size - 1)
        temp_buffer[@previous_line_index] = @line
      end
      finish if @confirm_multiline_termination_proc.(temp_buffer.join("\n"))
    end
  end

  def whole_buffer
    temp_lines = @buffer_of_lines.dup
    temp_lines[@line_index] = @line
    if @buffer_of_lines.size == 1 and @line.nil?
      nil
    else
      temp_lines.join("\n")
    end
  end

  def finished?
    @finished
  end

  def finish
    @finished = true
    @config.reset
  end

  private def byteslice!(str, byte_pointer, size)
    new_str = str.byteslice(0, byte_pointer)
    new_str << str.byteslice(byte_pointer + size, str.bytesize)
    [new_str, str.byteslice(byte_pointer, size)]
  end

  private def byteinsert(str, byte_pointer, other)
    new_str = str.byteslice(0, byte_pointer)
    new_str << other
    new_str << str.byteslice(byte_pointer, str.bytesize)
    new_str
  end

  private def calculate_width(str)
    str.encode(Encoding::UTF_8).grapheme_clusters.inject(0) { |width, gc|
      width + Reline::Unicode.get_mbchar_width(gc)
    }
  end

  private def ed_insert(key)
    if key.instance_of?(String)
      width = Reline::Unicode.get_mbchar_width(key)
      if @cursor == @cursor_max
        @line += key
      else
        @line = byteinsert(@line, @byte_pointer, key)
      end
      @byte_pointer += key.bytesize
      @cursor += width
      @cursor_max += width
    else
      if @cursor == @cursor_max
        @line += key.chr
      else
        @line = byteinsert(@line, @byte_pointer, key.chr)
      end
      width = Reline::Unicode.get_mbchar_width(key.chr)
      @byte_pointer += 1
      @cursor += width
      @cursor_max += width
    end
  end
  alias_method :ed_digit, :ed_insert

  private def ed_quoted_insert(str, arg: 1)
    @waiting_proc = proc { |key|
      arg.times do
        ed_insert(key)
      end
      @waiting_proc = nil
    }
  end

  private def ed_next_char(key, arg: 1)
    byte_size = Reline::Unicode.get_next_mbchar_size(@line, @byte_pointer)
    if (@byte_pointer < @line.bytesize)
      mbchar = @line.byteslice(@byte_pointer, byte_size)
      width = Reline::Unicode.get_mbchar_width(mbchar)
      @cursor += width if width
      @byte_pointer += byte_size
    end
    arg -= 1
    ed_next_char(key, arg: arg) if arg > 0
  end

  private def ed_prev_char(key, arg: 1)
    if @cursor > 0
      byte_size = Reline::Unicode.get_prev_mbchar_size(@line, @byte_pointer)
      @byte_pointer -= byte_size
      mbchar = @line.byteslice(@byte_pointer, byte_size)
      width = Reline::Unicode.get_mbchar_width(mbchar)
      @cursor -= width
    end
    arg -= 1
    ed_prev_char(key, arg: arg) if arg > 0
  end

  private def ed_move_to_beg(key)
    @byte_pointer, @cursor = Reline::Unicode.ed_move_to_begin(@line)
  end

  private def ed_move_to_end(key)
    @byte_pointer = 0
    @cursor = 0
    byte_size = 0
    while @byte_pointer < @line.bytesize
      byte_size = Reline::Unicode.get_next_mbchar_size(@line, @byte_pointer)
      if byte_size > 0
        mbchar = @line.byteslice(@byte_pointer, byte_size)
        @cursor += Reline::Unicode.get_mbchar_width(mbchar)
      end
      @byte_pointer += byte_size
    end
  end

  private def ed_prev_history(key, arg: 1)
    if @is_multiline and @line_index > 0
      @previous_line_index = @line_index
      @line_index -= 1
      return
    end
    if Reline::HISTORY.empty?
      return
    end
    if @history_pointer.nil?
      @history_pointer = Reline::HISTORY.size - 1
      if @is_multiline
        @line_backup_in_history = whole_buffer
        @buffer_of_lines = Reline::HISTORY[@history_pointer].split("\n")
        @line_index = @buffer_of_lines.size - 1
        @line = @buffer_of_lines.last
        @rerender_all = true
      else
        @line_backup_in_history = @line
        @line = Reline::HISTORY[@history_pointer]
      end
    elsif @history_pointer.zero?
      return
    else
      if @is_multiline
        Reline::HISTORY[@history_pointer] = whole_buffer
        @history_pointer -= 1
        @buffer_of_lines = Reline::HISTORY[@history_pointer].split("\n")
        @line_index = @buffer_of_lines.size - 1
        @line = @buffer_of_lines.last
        @rerender_all = true
      else
        Reline::HISTORY[@history_pointer] = @line
        @history_pointer -= 1
        @line = Reline::HISTORY[@history_pointer]
      end
    end
    if @config.editing_mode_is?(:emacs)
      @cursor_max = @cursor = calculate_width(@line)
      @byte_pointer = @line.bytesize
    elsif @config.editing_mode_is?(:vi_command)
      @byte_pointer = @cursor = 0
      @cursor_max = calculate_width(@line)
    end
    arg -= 1
    ed_prev_history(key, arg: arg) if arg > 0
  end

  private def ed_next_history(key, arg: 1)
    if @is_multiline and @line_index < (@buffer_of_lines.size - 1)
      @previous_line_index = @line_index
      @line_index += 1
      return
    end
    if @history_pointer.nil?
      return
    elsif @history_pointer == (Reline::HISTORY.size - 1)
      if @is_multiline
        @history_pointer = nil
        @buffer_of_lines = @line_backup_in_history.split("\n")
        @buffer_of_lines = [String.new(encoding: @encoding)] if @buffer_of_lines.empty?
        @line_index = 0
        @line = @buffer_of_lines.first
        @rerender_all = true
      else
        @history_pointer = nil
        @line = @line_backup_in_history
      end
    else
      if @is_multiline
        Reline::HISTORY[@history_pointer] = whole_buffer
        @history_pointer += 1
        @buffer_of_lines = Reline::HISTORY[@history_pointer].split("\n")
        @line_index = 0
        @line = @buffer_of_lines.first
        @rerender_all = true
      else
        Reline::HISTORY[@history_pointer] = @line
        @history_pointer += 1
        @line = Reline::HISTORY[@history_pointer]
      end
    end
    @line = '' unless @line
    if @config.editing_mode_is?(:emacs)
      @cursor_max = @cursor = calculate_width(@line)
      @byte_pointer = @line.bytesize
    elsif @config.editing_mode_is?(:vi_command)
      @byte_pointer = @cursor = 0
      @cursor_max = calculate_width(@line)
    end
    arg -= 1
    ed_next_history(key, arg: arg) if arg > 0
  end

  private def ed_newline(key)
    if @is_multiline
      if @config.editing_mode_is?(:vi_command)
        if @line_index < (@buffer_of_lines.size - 1)
          ed_next_history(key)
        else
          @is_confirm_multiline_termination = true
        end
      else
        next_line = @line.byteslice(@byte_pointer, @line.bytesize - @byte_pointer)
        cursor_line = @line.byteslice(0, @byte_pointer)
        insert_new_line(cursor_line, next_line)
        if @line_index == (@buffer_of_lines.size - 1)
          @is_confirm_multiline_termination = true
        end
      end
      return
    end
    if @history_pointer
      Reline::HISTORY[@history_pointer] = @line
      @history_pointer = nil
    end
    finish
  end

  private def em_delete_prev_char(key)
    if @is_multiline and @cursor == 0 and @line_index > 0
      @buffer_of_lines[@line_index] = @line
      @cursor = calculate_width(@buffer_of_lines[@line_index - 1])
      @byte_pointer = @buffer_of_lines[@line_index - 1].bytesize
      @buffer_of_lines[@line_index - 1] += @buffer_of_lines.delete_at(@line_index)
      @line_index -= 1
      @line = @buffer_of_lines[@line_index]
      @cursor_max = calculate_width(@line)
      @rerender_all = true
    elsif @cursor > 0
      byte_size = Reline::Unicode.get_prev_mbchar_size(@line, @byte_pointer)
      @byte_pointer -= byte_size
      @line, mbchar = byteslice!(@line, @byte_pointer, byte_size)
      width = Reline::Unicode.get_mbchar_width(mbchar)
      @cursor -= width
      @cursor_max -= width
    end
  end

  private def ed_kill_line(key)
    if @line.bytesize > @byte_pointer
      @line, deleted = byteslice!(@line, @byte_pointer, @line.bytesize - @byte_pointer)
      @byte_pointer = @line.bytesize
      @cursor = @cursor_max = calculate_width(@line)
      @kill_ring.append(deleted)
    end
  end

  private def em_kill_line(key)
    if @byte_pointer > 0
      @line, deleted = byteslice!(@line, 0, @byte_pointer)
      @byte_pointer = 0
      @kill_ring.append(deleted, true)
      @cursor_max = calculate_width(@line)
      @cursor = 0
    end
  end

  private def em_delete_or_list(key)
    if @line.empty?
      @line = nil
      finish
    elsif @byte_pointer < @line.bytesize
      splitted_last = @line.byteslice(@byte_pointer, @line.bytesize)
      mbchar = splitted_last.grapheme_clusters.first
      width = Reline::Unicode.get_mbchar_width(mbchar)
      @cursor_max -= width
      @line, = byteslice!(@line, @byte_pointer, mbchar.bytesize)
    end
  end

  private def em_yank(key)
    yanked = @kill_ring.yank
    if yanked
      @line = byteinsert(@line, @byte_pointer, yanked)
      yanked_width = calculate_width(yanked)
      @cursor += yanked_width
      @cursor_max += yanked_width
      @byte_pointer += yanked.bytesize
    end
  end

  private def em_yank_pop(key)
    yanked, prev_yank = @kill_ring.yank_pop
    if yanked
      prev_yank_width = calculate_width(prev_yank)
      @cursor -= prev_yank_width
      @cursor_max -= prev_yank_width
      @byte_pointer -= prev_yank.bytesize
      @line, = byteslice!(@line, @byte_pointer, prev_yank.bytesize)
      @line = byteinsert(@line, @byte_pointer, yanked)
      yanked_width = calculate_width(yanked)
      @cursor += yanked_width
      @cursor_max += yanked_width
      @byte_pointer += yanked.bytesize
    end
  end

  private def ed_clear_screen(key)
    @cleared = true
  end

  private def em_next_word(key)
    if @line.bytesize > @byte_pointer
      byte_size, width = Reline::Unicode.em_forward_word(@line, @byte_pointer)
      @byte_pointer += byte_size
      @cursor += width
    end
  end

  private def ed_prev_word(key)
    if @byte_pointer > 0
      byte_size, width = Reline::Unicode.em_backward_word(@line, @byte_pointer)
      @byte_pointer -= byte_size
      @cursor -= width
    end
  end

  private def em_delete_next_word(key)
    if @line.bytesize > @byte_pointer
      byte_size, width = Reline::Unicode.em_forward_word(@line, @byte_pointer)
      @line, word = byteslice!(@line, @byte_pointer, byte_size)
      @kill_ring.append(word)
      @cursor_max -= width
    end
  end

  private def ed_delete_prev_word(key)
    if @byte_pointer > 0
      byte_size, width = Reline::Unicode.em_backward_word(@line, @byte_pointer)
      @line, word = byteslice!(@line, @byte_pointer - byte_size, byte_size)
      @kill_ring.append(word, true)
      @byte_pointer -= byte_size
      @cursor -= width
      @cursor_max -= width
    end
  end

  private def ed_transpose_chars(key)
    if @byte_pointer > 0
      if @cursor_max > @cursor
        byte_size = Reline::Unicode.get_next_mbchar_size(@line, @byte_pointer)
        mbchar = @line.byteslice(@byte_pointer, byte_size)
        width = Reline::Unicode.get_mbchar_width(mbchar)
        @cursor += width
        @byte_pointer += byte_size
      end
      back1_byte_size = Reline::Unicode.get_prev_mbchar_size(@line, @byte_pointer)
      if (@byte_pointer - back1_byte_size) > 0
        back2_byte_size = Reline::Unicode.get_prev_mbchar_size(@line, @byte_pointer - back1_byte_size)
        back2_pointer = @byte_pointer - back1_byte_size - back2_byte_size
        @line, back2_mbchar = byteslice!(@line, back2_pointer, back2_byte_size)
        @line = byteinsert(@line, @byte_pointer - back2_byte_size, back2_mbchar)
      end
    end
  end

  private def em_capitol_case(key)
    if @line.bytesize > @byte_pointer
      byte_size, _, new_str = Reline::Unicode.em_forward_word_with_capitalization(@line, @byte_pointer)
      before = @line.byteslice(0, @byte_pointer)
      after = @line.byteslice((@byte_pointer + byte_size)..-1)
      @line = before + new_str + after
      @byte_pointer += new_str.bytesize
      @cursor += calculate_width(new_str)
    end
  end

  private def em_lower_case(key)
    if @line.bytesize > @byte_pointer
      byte_size, = Reline::Unicode.em_forward_word(@line, @byte_pointer)
      part = @line.byteslice(@byte_pointer, byte_size).grapheme_clusters.map { |mbchar|
        mbchar =~ /[A-Z]/ ? mbchar.downcase : mbchar
      }.join
      rest = @line.byteslice((@byte_pointer + byte_size)..-1)
      @line = @line.byteslice(0, @byte_pointer) + part
      @byte_pointer = @line.bytesize
      @cursor = calculate_width(@line)
      @cursor_max = @cursor + calculate_width(rest)
      @line += rest
    end
  end

  private def em_upper_case(key)
    if @line.bytesize > @byte_pointer
      byte_size, = Reline::Unicode.em_forward_word(@line, @byte_pointer)
      part = @line.byteslice(@byte_pointer, byte_size).grapheme_clusters.map { |mbchar|
        mbchar =~ /[a-z]/ ? mbchar.upcase : mbchar
      }.join
      rest = @line.byteslice((@byte_pointer + byte_size)..-1)
      @line = @line.byteslice(0, @byte_pointer) + part
      @byte_pointer = @line.bytesize
      @cursor = calculate_width(@line)
      @cursor_max = @cursor + calculate_width(rest)
      @line += rest
    end
  end

  private def em_kill_region(key)
    if @byte_pointer > 0
      byte_size, width = Reline::Unicode.em_big_backward_word(@line, @byte_pointer)
      @line, deleted = byteslice!(@line, @byte_pointer - byte_size, byte_size)
      @byte_pointer -= byte_size
      @cursor -= width
      @cursor_max -= width
      @kill_ring.append(deleted)
    end
  end

  private def copy_for_vi(text)
    if @config.editing_mode_is?(:vi_insert) or @config.editing_mode_is?(:vi_command)
      @vi_clipboard = text
    end
  end

  private def vi_insert(key)
    @config.editing_mode = :vi_insert
  end

  private def vi_add(key)
    @config.editing_mode = :vi_insert
    ed_next_char(key)
  end

  private def vi_command_mode(key)
    ed_prev_char(key)
    @config.editing_mode = :vi_command
  end

  private def vi_next_word(key, arg: 1)
    if @line.bytesize > @byte_pointer
      byte_size, width = Reline::Unicode.vi_forward_word(@line, @byte_pointer)
      @byte_pointer += byte_size
      @cursor += width
    end
    arg -= 1
    vi_next_word(key, arg: arg) if arg > 0
  end

  private def vi_prev_word(key, arg: 1)
    if @byte_pointer > 0
      byte_size, width = Reline::Unicode.vi_backward_word(@line, @byte_pointer)
      @byte_pointer -= byte_size
      @cursor -= width
    end
    arg -= 1
    vi_prev_word(key, arg: arg) if arg > 0
  end

  private def vi_end_word(key, arg: 1)
    if @line.bytesize > @byte_pointer
      byte_size, width = Reline::Unicode.vi_forward_end_word(@line, @byte_pointer)
      @byte_pointer += byte_size
      @cursor += width
    end
    arg -= 1
    vi_end_word(key, arg: arg) if arg > 0
  end

  private def vi_next_big_word(key, arg: 1)
    if @line.bytesize > @byte_pointer
      byte_size, width = Reline::Unicode.vi_big_forward_word(@line, @byte_pointer)
      @byte_pointer += byte_size
      @cursor += width
    end
    arg -= 1
    vi_next_big_word(key, arg: arg) if arg > 0
  end

  private def vi_prev_big_word(key, arg: 1)
    if @byte_pointer > 0
      byte_size, width = Reline::Unicode.vi_big_backward_word(@line, @byte_pointer)
      @byte_pointer -= byte_size
      @cursor -= width
    end
    arg -= 1
    vi_prev_big_word(key, arg: arg) if arg > 0
  end

  private def vi_end_big_word(key, arg: 1)
    if @line.bytesize > @byte_pointer
      byte_size, width = Reline::Unicode.vi_big_forward_end_word(@line, @byte_pointer)
      @byte_pointer += byte_size
      @cursor += width
    end
    arg -= 1
    vi_end_big_word(key, arg: arg) if arg > 0
  end

  private def vi_delete_prev_char(key)
    if @is_multiline and @cursor == 0 and @line_index > 0
      @buffer_of_lines[@line_index] = @line
      @cursor = calculate_width(@buffer_of_lines[@line_index - 1])
      @byte_pointer = @buffer_of_lines[@line_index - 1].bytesize
      @buffer_of_lines[@line_index - 1] += @buffer_of_lines.delete_at(@line_index)
      @line_index -= 1
      @line = @buffer_of_lines[@line_index]
      @cursor_max = calculate_width(@line)
      @rerender_all = true
    elsif @cursor > 0
      byte_size = Reline::Unicode.get_prev_mbchar_size(@line, @byte_pointer)
      @byte_pointer -= byte_size
      @line, mbchar = byteslice!(@line, @byte_pointer, byte_size)
      width = Reline::Unicode.get_mbchar_width(mbchar)
      @cursor -= width
      @cursor_max -= width
    end
  end

  private def ed_delete_prev_char(key, arg: 1)
    deleted = ''
    arg.times do
      if @cursor > 0
        byte_size = Reline::Unicode.get_prev_mbchar_size(@line, @byte_pointer)
        @byte_pointer -= byte_size
        @line, mbchar = byteslice!(@line, @byte_pointer, byte_size)
        deleted.prepend(mbchar)
        width = Reline::Unicode.get_mbchar_width(mbchar)
        @cursor -= width
        @cursor_max -= width
      end
    end
    copy_for_vi(deleted)
  end

  private def vi_zero(key)
    @byte_pointer = 0
    @cursor = 0
  end

  private def vi_change_meta(key)
  end

  private def vi_delete_meta(key)
    @waiting_operator_proc = proc { |cursor_diff, byte_pointer_diff|
      if byte_pointer_diff > 0
        @line, cut = byteslice!(@line, @byte_pointer, byte_pointer_diff)
      elsif byte_pointer_diff < 0
        @line, cut = byteslice!(@line, @byte_pointer + byte_pointer_diff, -byte_pointer_diff)
      end
      copy_for_vi(cut)
      @cursor += cursor_diff if cursor_diff < 0
      @cursor_max -= cursor_diff.abs
      @byte_pointer += byte_pointer_diff if byte_pointer_diff < 0
    }
  end

  private def vi_yank(key)
  end

  private def vi_end_of_transmission(key)
    if @line.empty?
      @line = nil
      finish
    end
  end

  private def vi_list_or_eof(key)
    if @line.empty?
      @line = nil
      finish
    else
      # TODO: list
    end
  end

  private def ed_delete_next_char(key, arg: 1)
    unless @line.empty?
      byte_size = Reline::Unicode.get_next_mbchar_size(@line, @byte_pointer)
      @line, mbchar = byteslice!(@line, @byte_pointer, byte_size)
      copy_for_vi(mbchar)
      width = Reline::Unicode.get_mbchar_width(mbchar)
      @cursor_max -= width
      if @cursor > 0 and @cursor >= @cursor_max
        @byte_pointer -= byte_size
        @cursor -= width
      end
    end
    arg -= 1
    ed_delete_next_char(key, arg: arg) if arg > 0
  end

  private def vi_to_history_line(key)
    if Reline::HISTORY.empty?
      return
    end
    if @history_pointer.nil?
      @history_pointer = 0
      @line_backup_in_history = @line
      @line = Reline::HISTORY[@history_pointer]
      @cursor_max = calculate_width(@line)
      @cursor = 0
      @byte_pointer = 0
    elsif @history_pointer.zero?
      return
    else
      Reline::HISTORY[@history_pointer] = @line
      @history_pointer = 0
      @line = Reline::HISTORY[@history_pointer]
      @cursor_max = calculate_width(@line)
      @cursor = 0
      @byte_pointer = 0
    end
  end

  private def vi_histedit(key)
    path = Tempfile.open { |fp|
      fp.write @line
      fp.path
    }
    system("#{ENV['EDITOR']} #{path}")
    @line = Pathname.new(path).read
    finish
  end

  private def vi_paste_prev(key, arg: 1)
    if @vi_clipboard.size > 0
      @line = byteinsert(@line, @byte_pointer, @vi_clipboard)
      @cursor_max += calculate_width(@vi_clipboard)
      cursor_point = @vi_clipboard.grapheme_clusters[0..-2].join
      @cursor += calculate_width(cursor_point)
      @byte_pointer += cursor_point.bytesize
    end
    arg -= 1
    vi_paste_prev(key, arg: arg) if arg > 0
  end

  private def vi_paste_next(key, arg: 1)
    if @vi_clipboard.size > 0
      byte_size = Reline::Unicode.get_next_mbchar_size(@line, @byte_pointer)
      @line = byteinsert(@line, @byte_pointer + byte_size, @vi_clipboard)
      @cursor_max += calculate_width(@vi_clipboard)
      @cursor += calculate_width(@vi_clipboard)
      @byte_pointer += @vi_clipboard.bytesize
    end
    arg -= 1
    vi_paste_next(key, arg: arg) if arg > 0
  end

  private def ed_argument_digit(key)
    if @vi_arg.nil?
      unless key.chr.to_i.zero?
        @vi_arg = key.chr.to_i
      end
    else
      @vi_arg = @vi_arg * 10 + key.chr.to_i
    end
  end

  private def vi_to_column(key, arg: 0)
    @byte_pointer, @cursor = @line.grapheme_clusters.inject([0, 0]) { |total, gc|
      # total has [byte_size, cursor]
      mbchar_width = Reline::Unicode.get_mbchar_width(gc)
      if (total.last + mbchar_width) >= arg
        break total
      elsif (total.last + mbchar_width) >= @cursor_max
        break total
      else
        total = [total.first + gc.bytesize, total.last + mbchar_width]
        total
      end
    }
  end

  private def vi_replace_char(key, arg: 1)
    @waiting_proc = ->(key) {
      if arg == 1
        byte_size = Reline::Unicode.get_next_mbchar_size(@line, @byte_pointer)
        before = @line.byteslice(0, @byte_pointer)
        remaining_point = @byte_pointer + byte_size
        after = @line.byteslice(remaining_point, @line.size - remaining_point)
        @line = before + key.chr + after
        @cursor_max = calculate_width(@line)
        @waiting_proc = nil
      elsif arg > 1
        byte_size = 0
        arg.times do
          byte_size += Reline::Unicode.get_next_mbchar_size(@line, @byte_pointer + byte_size)
        end
        before = @line.byteslice(0, @byte_pointer)
        remaining_point = @byte_pointer + byte_size
        after = @line.byteslice(remaining_point, @line.size - remaining_point)
        replaced = key.chr * arg
        @line = before + replaced + after
        @byte_pointer += replaced.bytesize
        @cursor += calculate_width(replaced)
        @cursor_max = calculate_width(@line)
        @waiting_proc = nil
      end
    }
  end

  private def vi_next_char(key, arg: 1)
    @waiting_proc = ->(key_for_proc) { search_next_char(key_for_proc, arg) }
  end

  private def search_next_char(key, arg)
    if key.instance_of?(String)
      inputed_char = key
    else
      inputed_char = key.chr
    end
    total = nil
    found = false
    @line.byteslice(@byte_pointer..-1).grapheme_clusters.each do |mbchar|
      # total has [byte_size, cursor]
      unless total
        # skip cursor point
        width = Reline::Unicode.get_mbchar_width(mbchar)
        total = [mbchar.bytesize, width]
      else
        if inputed_char == mbchar
          arg -= 1
          if arg.zero?
            found = true
            break
          end
        end
        width = Reline::Unicode.get_mbchar_width(mbchar)
        total = [total.first + mbchar.bytesize, total.last + width]
      end
    end
    if found and total
      byte_size, width = total
      @byte_pointer += byte_size
      @cursor += width
    end
    @waiting_proc = nil
  end
end
