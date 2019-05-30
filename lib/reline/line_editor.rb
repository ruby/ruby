require 'reline/kill_ring'
require 'reline/unicode'

require 'tempfile'
require 'pathname'

class Reline::LineEditor
  # TODO: undo
  attr_reader :line
  attr_reader :byte_pointer
  attr_accessor :confirm_multiline_termination_proc
  attr_accessor :completion_proc
  attr_accessor :output_modifier_proc
  attr_accessor :pre_input_hook
  attr_accessor :dig_perfect_match_proc
  attr_writer :output

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
    vi_join_lines
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

  CSI_REGEXP = /\e\[[\d;]*[ABCDEFGHJKSTfminsuhl]/
  OSC_REGEXP = /\e\]\d+(?:;[^;]+)*\a/
  NON_PRINTING_START = "\1"
  NON_PRINTING_END = "\2"

  def initialize(config)
    @config = config
    reset_variables
  end

  def reset(prompt = '', encoding = Encoding.default_external)
    @rest_height = (Reline::IOGate.get_screen_size.first - 1) - Reline::IOGate.cursor_pos.y
    @screen_size = Reline::IOGate.get_screen_size
    reset_variables(prompt, encoding)
    @old_trap = Signal.trap('SIGINT') {
      scroll_down(@highest_in_all - @first_line_started_from)
      Reline::IOGate.move_cursor_column(0)
      @old_trap.()
    }
  end

  def finalize
    Signal.trap('SIGINT', @old_trap)
  end

  def eof?
    @eof
  end

  def reset_variables(prompt = '', encoding = Encoding.default_external)
    @prompt = prompt
    @encoding = encoding
    @prompt_width = calculate_width(@prompt, true)
    @is_multiline = false
    @finished = false
    @cleared = false
    @rerender_all = false
    @history_pointer = nil
    @kill_ring = Reline::KillRing.new
    @vi_clipboard = ''
    @vi_arg = nil
    @waiting_proc = nil
    @waiting_operator_proc = nil
    @completion_journey_data = nil
    @completion_state = CompletionState::NORMAL
    @perfect_matched = nil
    @menu_info = nil
    @first_prompt = true
    @searching_prompt = nil
    @first_char = true
    @eof = false
    reset_line
  end

  def reset_line
    @cursor = 0
    @cursor_max = 0
    @byte_pointer = 0
    @buffer_of_lines = [String.new(encoding: @encoding)]
    @line_index = 0
    @previous_line_index = nil
    @line = @buffer_of_lines[0]
    @first_line_started_from = 0
    @move_up = 0
    @started_from = 0
    @highest_in_this = 1
    @highest_in_all = 1
    @line_backup_in_history = nil
    @multibyte_buffer = String.new(encoding: 'ASCII-8BIT')
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

  private def split_by_width(prompt, str, max_width)
    lines = [String.new(encoding: @encoding)]
    height = 1
    width = 0
    rest = "#{prompt}#{str}".encode(Encoding::UTF_8)
    in_zero_width = false
    loop do
      break if rest.empty?
      if rest.start_with?(NON_PRINTING_START)
        rest.delete_prefix!(NON_PRINTING_START)
        in_zero_width = true
      elsif rest.start_with?(NON_PRINTING_END)
        rest.delete_prefix!(NON_PRINTING_END)
        in_zero_width = false
      elsif rest.start_with?(CSI_REGEXP)
        lines.last << $&
        rest = $'
      elsif rest.start_with?(OSC_REGEXP)
        lines.last << $&
        rest = $'
      else
        gcs = rest.grapheme_clusters
        gc = gcs.first
        rest = gcs[1..-1].join
        if in_zero_width
          mbchar_width = 0
        else
          mbchar_width = Reline::Unicode.get_mbchar_width(gc)
        end
        width += mbchar_width
        if width > max_width
          width = mbchar_width
          lines << nil
          lines << String.new(encoding: @encoding)
          height += 1
        end
        lines.last << gc
      end
    end
    # The cursor moves to next line in first
    if width == max_width
      lines << nil
      lines << String.new(encoding: @encoding)
      height += 1
    end
    [lines, height]
  end

  private def scroll_down(val)
    if val <= @rest_height
      Reline::IOGate.move_cursor_down(val)
      @rest_height -= val
    else
      Reline::IOGate.move_cursor_down(@rest_height)
      Reline::IOGate.scroll_down(val - @rest_height)
      @rest_height = 0
    end
  end

  private def move_cursor_up(val)
    if val > 0
      Reline::IOGate.move_cursor_up(val)
      @rest_height += val
    elsif val < 0
      move_cursor_down(-val)
    end
  end

  private def move_cursor_down(val)
    if val > 0
      Reline::IOGate.move_cursor_down(val)
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
    if @config.editing_mode_is?(:vi_command)
      last_byte_size = Reline::Unicode.get_prev_mbchar_size(@line, @line.bytesize)
      if last_byte_size > 0
        last_mbchar = @line.byteslice(@line.bytesize - last_byte_size, last_byte_size)
        last_width = Reline::Unicode.get_mbchar_width(last_mbchar)
        cursor_max = @cursor_max - last_width
      else
        cursor_max = @cursor_max
      end
    else
      cursor_max = @cursor_max
    end
    @line.encode(Encoding::UTF_8).grapheme_clusters.each do |gc|
      mbchar_width = Reline::Unicode.get_mbchar_width(gc)
      now = new_cursor + mbchar_width
      if now > cursor_max or now > @cursor
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
    return if @line.nil?
    if @menu_info
      scroll_down(@highest_in_all - @first_line_started_from)
      @rerender_all = true
      @menu_info.list.each do |item|
        Reline::IOGate.move_cursor_column(0)
        @output.print item
        scroll_down(1)
      end
      scroll_down(@highest_in_all - 1)
      move_cursor_up(@highest_in_all - 1 - @first_line_started_from)
      @menu_info = nil
    end
    if @vi_arg
      prompt = "(arg: #{@vi_arg}) "
      prompt_width = calculate_width(prompt)
    elsif @searching_prompt
      prompt = @searching_prompt
      prompt_width = calculate_width(prompt)
    else
      prompt = @prompt
      prompt_width = @prompt_width
    end
    if @cleared
      Reline::IOGate.clear_screen
      @cleared = false
      back = 0
      modify_lines(whole_lines).each_with_index do |line, index|
        height = render_partial(prompt, prompt_width, line, false)
        if index < (@buffer_of_lines.size - 1)
          move_cursor_down(height)
          back += height
        end
      end
      move_cursor_up(back)
      move_cursor_down(@first_line_started_from + @started_from)
      Reline::IOGate.move_cursor_column((prompt_width + @cursor) % @screen_size.last)
      return
    end
    new_highest_in_this = calculate_height_by_width(@prompt_width + calculate_width(@line.nil? ? '' : @line))
    # FIXME: end of logical line sometimes breaks
    if @previous_line_index or new_highest_in_this != @highest_in_this
      if @previous_line_index
        new_lines = whole_lines(index: @previous_line_index, line: @line)
      else
        new_lines = whole_lines
      end
      all_height = new_lines.inject(0) { |result, line|
        result + calculate_height_by_width(@prompt_width + calculate_width(line))
      }
      diff = all_height - @highest_in_all
      move_cursor_down(@highest_in_all - @first_line_started_from - @started_from - 1)
      if diff > 0
        scroll_down(diff)
        move_cursor_up(all_height - 1)
      elsif diff < 0
        (-diff).times do
          Reline::IOGate.move_cursor_column(0)
          Reline::IOGate.erase_after_cursor
          move_cursor_up(1)
        end
        move_cursor_up(all_height - 1)
      else
        move_cursor_up(all_height - 1)
      end
      @highest_in_all = all_height
      back = 0
      modify_lines(new_lines).each_with_index do |line, index|
        height = render_partial(prompt, prompt_width, line, false)
        if index < (new_lines.size - 1)
          scroll_down(1)
          back += height
        else
          back += height - 1
        end
      end
      move_cursor_up(back)
      if @previous_line_index
        @buffer_of_lines[@previous_line_index] = @line
        @line = @buffer_of_lines[@line_index]
      end
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
      @started_from = calculate_height_by_width(@prompt_width + @cursor) - 1
      move_cursor_down(@started_from)
      Reline::IOGate.move_cursor_column((prompt_width + @cursor) % @screen_size.last)
      @highest_in_this = calculate_height_by_width(@prompt_width + @cursor_max)
      @previous_line_index = nil
      rendered = true
    elsif @rerender_all
      move_cursor_up(@first_line_started_from + @started_from)
      Reline::IOGate.move_cursor_column(0)
      back = 0
      new_buffer = whole_lines
      new_buffer.each do |line|
        width = prompt_width + calculate_width(line)
        height = calculate_height_by_width(width)
        back += height
      end
      if back > @highest_in_all
        scroll_down(back - 1)
        move_cursor_up(back - 1)
      elsif back < @highest_in_all
        scroll_down(back)
        Reline::IOGate.erase_after_cursor
        (@highest_in_all - back - 1).times do
          scroll_down(1)
          Reline::IOGate.erase_after_cursor
        end
        move_cursor_up(@highest_in_all - 1)
      end
      modify_lines(new_buffer).each_with_index do |line, index|
        render_partial(prompt, prompt_width, line, false)
        if index < (new_buffer.size - 1)
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
          new_buffer[0..(@line_index - 1)].inject(0) { |result, line|
            result + calculate_height_by_width(@prompt_width + calculate_width(line))
          }
        end
      @started_from = calculate_height_by_width(@prompt_width + @cursor) - 1
      move_cursor_down(@first_line_started_from + @started_from)
      Reline::IOGate.move_cursor_column((prompt_width + @cursor) % @screen_size.last)
      @rerender_all = false
      rendered = true
    end
    line = modify_lines(whole_lines)[@line_index]
    if @is_multiline
      if finished?
        scroll_down(1)
        Reline::IOGate.move_cursor_column(0)
        Reline::IOGate.erase_after_cursor
      elsif not rendered
        render_partial(prompt, prompt_width, line)
      end
    else
      render_partial(prompt, prompt_width, line)
      if finished?
        scroll_down(1)
        Reline::IOGate.move_cursor_column(0)
        Reline::IOGate.erase_after_cursor
      end
    end
  end

  private def render_partial(prompt, prompt_width, line_to_render, with_control = true)
    visual_lines, height = split_by_width(prompt, line_to_render.nil? ? '' : line_to_render, @screen_size.last)
    if with_control
      if height > @highest_in_this
        diff = height - @highest_in_this
        scroll_down(diff)
        @highest_in_all += diff
        @highest_in_this = height
        move_cursor_up(diff)
      elsif height < @highest_in_this
        diff = @highest_in_this - height
        @highest_in_all -= diff
        @highest_in_this = height
      end
      move_cursor_up(@started_from)
      @started_from = calculate_height_by_width(prompt_width + @cursor) - 1
    end
    Reline::IOGate.move_cursor_column(0)
    visual_lines.each_with_index do |line, index|
      if line.nil?
        Reline::IOGate.erase_after_cursor
        move_cursor_down(1)
        Reline::IOGate.move_cursor_column(0)
        next
      end
      @output.print line
      if @first_prompt
        @first_prompt = false
        @pre_input_hook&.call
      end
    end
    Reline::IOGate.erase_after_cursor
    if with_control
      move_cursor_up(height - 1)
      if finished?
        move_cursor_down(@started_from)
      end
      move_cursor_down(@started_from)
      Reline::IOGate.move_cursor_column((prompt_width + @cursor) % @screen_size.last)
    end
    height
  end

  private def modify_lines(before)
    return before if before.nil? || before.empty?

    if after = @output_modifier_proc&.call("#{before.join("\n")}\n")
      after.lines(chomp: true)
    else
      before
    end
  end

  def editing_mode
    @config.editing_mode
  end

  private def menu(target, list)
    @menu_info = MenuInfo.new(target, list)
  end

  private def complete_internal_proc(list, is_menu)
    preposing, target, postposing = retrieve_completion_block
    list = list.select { |i|
      if i and i.encoding != Encoding::US_ASCII and i.encoding != @encoding
        raise Encoding::CompatibilityError
      end
      i&.start_with?(target)
    }
    if is_menu
      menu(target, list)
      return nil
    end
    completed = list.inject { |memo, item|
      begin
        memo_mbchars = memo.unicode_normalize.grapheme_clusters
        item_mbchars = item.unicode_normalize.grapheme_clusters
      rescue Encoding::CompatibilityError
        memo_mbchars = memo.grapheme_clusters
        item_mbchars = item.grapheme_clusters
      end
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
      result = retrieve_completion_block
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
    @multibyte_buffer << key.combined_char
    if @multibyte_buffer.size > 1
      if @multibyte_buffer.dup.force_encoding(@encoding).valid_encoding?
        process_key(@multibyte_buffer.dup.force_encoding(@encoding), nil, nil)
        @multibyte_buffer.clear
      else
        # invalid
        return
      end
    else # single byte
      return if key.char >= 128 # maybe, first byte of multi byte
      method_symbol = @config.editing_mode.get_method(key.combined_char)
      if key.with_meta and method_symbol == :ed_unassigned
        # split ESC + key
        method_symbol = @config.editing_mode.get_method("\e".ord)
        if method_symbol and respond_to?(method_symbol, true)
          method_obj = method(method_symbol)
        end
        process_key("\e".ord, method_symbol, method_obj)
        method_symbol = @config.editing_mode.get_method(key.char)
        if method_symbol and respond_to?(method_symbol, true)
          method_obj = method(method_symbol)
        end
        process_key(key.char, method_symbol, method_obj)
      else
        if method_symbol and respond_to?(method_symbol, true)
          method_obj = method(method_symbol)
        end
        process_key(key.combined_char, method_symbol, method_obj)
      end
      @multibyte_buffer.clear
    end
    if @config.editing_mode_is?(:vi_command) and @cursor > 0 and @cursor == @cursor_max
      byte_size = Reline::Unicode.get_prev_mbchar_size(@line, @byte_pointer)
      @byte_pointer -= byte_size
      mbchar = @line.byteslice(@byte_pointer, byte_size)
      width = Reline::Unicode.get_mbchar_width(mbchar)
      @cursor -= width
    end
  end

  def input_key(key)
    if key.nil? or key.char.nil?
      if @first_char
        @line = nil
      end
      finish
      return
    end
    @first_char = false
    completion_occurs = false
    if @config.editing_mode_is?(:emacs, :vi_insert) and key.char == "\C-i".ord
      result = retrieve_completion_block
      slice = result[1]
      result = @completion_proc.(slice) if @completion_proc and slice
      if result.is_a?(Array)
        completion_occurs = true
        complete(result)
      end
    elsif @config.editing_mode_is?(:vi_insert) and ["\C-p".ord, "\C-n".ord].include?(key.char)
      result = retrieve_completion_block
      slice = result[1]
      result = @completion_proc.(slice) if @completion_proc and slice
      if result.is_a?(Array)
        completion_occurs = true
        move_completed_list(result, "\C-p".ord == key.char ? :up : :down)
      end
    elsif Symbol === key.char and respond_to?(key.char, true)
      process_key(key.char, key.char, method(key.char))
    else
      normal_char(key)
    end
    unless completion_occurs
      @completion_state = CompletionState::NORMAL
    end
  end

  def retrieve_completion_block
    word_break_regexp = /\A[#{Regexp.escape(Reline.completer_word_break_characters)}]/
    quote_characters_regexp = /\A[#{Regexp.escape(Reline.completer_quote_characters)}]/
    before = @line.byteslice(0, @byte_pointer)
    rest = nil
    break_pointer = nil
    quote = nil
    i = 0
    while i < @byte_pointer do
      slice = @line.byteslice(i, @byte_pointer - i)
      if quote and slice.start_with?(/(?!\\)#{Regexp.escape(quote)}/) # closing "
        quote = nil
        i += 1
      elsif quote and slice.start_with?(/\\#{Regexp.escape(quote)}/) # escaped \"
        # skip
        i += 2
      elsif slice =~ quote_characters_regexp # find new "
        quote = $&
        i += 1
      elsif not quote and slice =~ word_break_regexp
        rest = $'
        i += 1
        break_pointer = i
      else
        i += 1
      end
    end
    if rest
      preposing = @line.byteslice(0, break_pointer)
      target = rest
    else
      preposing = ''
      target = before
    end
    postposing = @line.byteslice(@byte_pointer, @line.bytesize - @byte_pointer)
    [preposing, target, postposing]
  end

  def confirm_multiline_termination
    temp_buffer = @buffer_of_lines.dup
    if @previous_line_index and @line_index == (@buffer_of_lines.size - 1)
      temp_buffer[@previous_line_index] = @line
    else
      temp_buffer[@line_index] = @line
    end
    if temp_buffer.any?{ |l| l.chomp != '' }
      @confirm_multiline_termination_proc.(temp_buffer.join("\n") + "\n")
    else
      false
    end
  end

  def insert_text(text)
    width = calculate_width(text)
    if @cursor == @cursor_max
      @line += text
    else
      @line = byteinsert(@line, @byte_pointer, text)
    end
    @byte_pointer += text.bytesize
    @cursor += width
    @cursor_max += width
  end

  def delete_text(start = nil, length = nil)
    if start.nil? and length.nil?
      @line&.clear
      @byte_pointer = 0
      @cursor = 0
      @cursor_max = 0
    elsif not start.nil? and not length.nil?
      if @line
        before = @line.byteslice(0, start)
        after = @line.byteslice(start + length, @line.bytesize)
        @line = before + after
        @byte_pointer = @line.bytesize if @byte_pointer > @line.bytesize
        str = @line.byteslice(0, @byte_pointer)
        @cursor = calculate_width(str)
        @cursor_max = calculate_width(@line)
      end
    elsif start.is_a?(Range)
      range = start
      first = range.first
      last = range.last
      last = @line.bytesize - 1 if last > @line.bytesize
      last += @line.bytesize if last < 0
      first += @line.bytesize if first < 0
      range = range.exclude_end? ? first...last : first..last
      @line = @line.bytes.reject.with_index{ |c, i| range.include?(i) }.map{ |c| c.chr(Encoding::ASCII_8BIT) }.join.force_encoding(@encoding)
      @byte_pointer = @line.bytesize if @byte_pointer > @line.bytesize
      str = @line.byteslice(0, @byte_pointer)
      @cursor = calculate_width(str)
      @cursor_max = calculate_width(@line)
    else
      @line = @line.byteslice(0, start)
      @byte_pointer = @line.bytesize if @byte_pointer > @line.bytesize
      str = @line.byteslice(0, @byte_pointer)
      @cursor = calculate_width(str)
      @cursor_max = calculate_width(@line)
    end
  end

  def byte_pointer=(val)
    @byte_pointer = val
    str = @line.byteslice(0, @byte_pointer)
    @cursor = calculate_width(str)
    @cursor_max = calculate_width(@line)
  end

  def whole_lines(index: @line_index, line: @line)
    temp_lines = @buffer_of_lines.dup
    temp_lines[index] = line
    temp_lines
  end

  def whole_buffer
    if @buffer_of_lines.size == 1 and @line.nil?
      nil
    else
      whole_lines.join("\n")
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

  private def calculate_width(str, allow_escape_code = false)
    if allow_escape_code
      width = 0
      rest = str.encode(Encoding::UTF_8)
      in_zero_width = false
      loop do
        break if rest.empty?
        if rest.start_with?(NON_PRINTING_START)
          rest.delete_prefix!(NON_PRINTING_START)
          in_zero_width = true
        elsif rest.start_with?(NON_PRINTING_END)
          rest.delete_prefix!(NON_PRINTING_END)
          in_zero_width = false
        elsif rest.start_with?(CSI_REGEXP)
          rest = $'
        elsif rest.start_with?(OSC_REGEXP)
          rest = $'
        else
          gcs = rest.grapheme_clusters
          gc = gcs.first
          rest = gcs[1..-1].join
          if in_zero_width
            mbchar_width = 0
          else
            mbchar_width = Reline::Unicode.get_mbchar_width(gc)
          end
          width += mbchar_width
        end
      end
      width
    else
      str.encode(Encoding::UTF_8).grapheme_clusters.inject(0) { |width, gc|
        width + Reline::Unicode.get_mbchar_width(gc)
      }
    end
  end

  private def key_delete(key)
    if @config.editing_mode_is?(:vi_insert, :emacs)
      ed_delete_next_char(key)
    end
  end

  private def key_newline(key)
    if @is_multiline
      next_line = @line.byteslice(@byte_pointer, @line.bytesize - @byte_pointer)
      cursor_line = @line.byteslice(0, @byte_pointer)
      insert_new_line(cursor_line, next_line)
      @cursor = 0
    end
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
        if key == "\C-j".ord or key == "\C-m".ord
          key_newline(key)
        else
          ed_insert(key)
        end
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
    elsif @is_multiline and @config.editing_mode_is?(:emacs) and @byte_pointer == @line.bytesize and @line_index < @buffer_of_lines.size - 1
      next_line = @buffer_of_lines[@line_index + 1]
      @cursor = 0
      @byte_pointer = 0
      @cursor_max = calculate_width(next_line)
      @previous_line_index = @line_index
      @line_index += 1
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
    elsif @is_multiline and @config.editing_mode_is?(:emacs) and @byte_pointer == 0 and @line_index > 0
      prev_line = @buffer_of_lines[@line_index - 1]
      @cursor = calculate_width(prev_line)
      @byte_pointer = prev_line.bytesize
      @cursor_max = calculate_width(prev_line)
      @previous_line_index = @line_index
      @line_index -= 1
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

  private def ed_search_prev_history(key)
    @line_backup_in_history = @line
    searcher = Fiber.new do
      search_word = String.new(encoding: @encoding)
      multibyte_buf = String.new(encoding: 'ASCII-8BIT')
      last_hit = nil
      loop do
        key = Fiber.yield(search_word)
        case key
        when "\C-h".ord, 127
          grapheme_clusters = search_word.grapheme_clusters
          if grapheme_clusters.size > 0
            grapheme_clusters.pop
            search_word = grapheme_clusters.join
          end
        else
          multibyte_buf << key
          if multibyte_buf.dup.force_encoding(@encoding).valid_encoding?
            search_word << multibyte_buf.dup.force_encoding(@encoding)
            multibyte_buf.clear
          end
        end
        hit = nil
        if @line_backup_in_history.include?(search_word)
          @history_pointer = nil
          hit = @line_backup_in_history
        else
          hit_index = Reline::HISTORY.rindex { |item|
            item.include?(search_word)
          }
          if hit_index
            @history_pointer = hit_index
            hit = Reline::HISTORY[@history_pointer]
          end
        end
        if hit
          @searching_prompt = "(reverse-i-search)`%s': %s" % [search_word, hit]
          @line = hit
          last_hit = hit
        else
          @searching_prompt = "(failed reverse-i-search)`%s': %s" % [search_word, last_hit]
        end
      end
    end
    searcher.resume
    @searching_prompt = "(reverse-i-search)`': "
    @waiting_proc = ->(key) {
      case key
      when "\C-j".ord, "\C-?".ord
        if @history_pointer
          @line = Reline::HISTORY[@history_pointer]
        else
          @line = @line_backup_in_history
        end
        @searching_prompt = nil
        @waiting_proc = nil
        @cursor_max = calculate_width(@line)
        @cursor = @byte_pointer = 0
      when "\C-g".ord
        @line = @line_backup_in_history
        @history_pointer = nil
        @searching_prompt = nil
        @waiting_proc = nil
        @line_backup_in_history = nil
        @cursor_max = calculate_width(@line)
        @cursor = @byte_pointer = 0
      else
        chr = key.is_a?(String) ? key : key.chr(Encoding::ASCII_8BIT)
        if chr.match?(/[[:print:]]/)
          searcher.resume(key)
        else
          if @history_pointer
            @line = Reline::HISTORY[@history_pointer]
          else
            @line = @line_backup_in_history
          end
          @searching_prompt = nil
          @waiting_proc = nil
          @cursor_max = calculate_width(@line)
          @cursor = @byte_pointer = 0
        end
      end
    }
  end

  private def ed_search_next_history(key)
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
        @buffer_of_lines = [String.new(encoding: @encoding)] if @buffer_of_lines.empty?
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
        @buffer_of_lines = [String.new(encoding: @encoding)] if @buffer_of_lines.empty?
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
        @buffer_of_lines = [String.new(encoding: @encoding)] if @buffer_of_lines.empty?
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
          ed_next_history(key) # means cursor down
        else
          # should check confirm_multiline_termination to finish?
          finish
        end
      else
        if @line_index == (@buffer_of_lines.size - 1)
          if confirm_multiline_termination
            finish
          else
            key_newline(key)
          end
        else
          # should check confirm_multiline_termination to finish?
          @previous_line_index = @line_index
          @line_index = @buffer_of_lines.size - 1
          finish
        end
      end
    else
      if @history_pointer
        Reline::HISTORY[@history_pointer] = @line
        @history_pointer = nil
      end
      finish
    end
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
    if (not @is_multiline and @line.empty?) or (@is_multiline and @line.empty? and @buffer_of_lines.size == 1)
      @line = nil
      if @buffer_of_lines.size > 1
        scroll_down(@highest_in_all - @first_line_started_from)
      end
      Reline::IOGate.move_cursor_column(0)
      @eof = true
      finish
    elsif @byte_pointer < @line.bytesize
      splitted_last = @line.byteslice(@byte_pointer, @line.bytesize)
      mbchar = splitted_last.grapheme_clusters.first
      width = Reline::Unicode.get_mbchar_width(mbchar)
      @cursor_max -= width
      @line, = byteslice!(@line, @byte_pointer, mbchar.bytesize)
    elsif @is_multiline and @byte_pointer == @line.bytesize and @buffer_of_lines.size > @line_index + 1
      @cursor = calculate_width(@line)
      @byte_pointer = @line.bytesize
      @line += @buffer_of_lines.delete_at(@line_index + 1)
      @cursor_max = calculate_width(@line)
      @buffer_of_lines[@line_index] = @line
      @rerender_all = true
      @rest_height += 1
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
      if @buffer_of_lines.size > 1
        scroll_down(@highest_in_all - @first_line_started_from)
      end
      Reline::IOGate.move_cursor_column(0)
      @eof = true
      finish
    end
  end

  private def vi_list_or_eof(key)
    if @line.empty?
      @line = nil
      if @buffer_of_lines.size > 1
        scroll_down(@highest_in_all - @first_line_started_from)
      end
      Reline::IOGate.move_cursor_column(0)
      @eof = true
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

  private def vi_join_lines(key, arg: 1)
    if @is_multiline and @buffer_of_lines.size > @line_index + 1
      @cursor = calculate_width(@line)
      @byte_pointer = @line.bytesize
      @line += ' ' + @buffer_of_lines.delete_at(@line_index + 1).gsub(/\A +/, '')
      @cursor_max = calculate_width(@line)
      @buffer_of_lines[@line_index] = @line
      @rerender_all = true
      @rest_height += 1
    end
    arg -= 1
    vi_join_lines(key, arg: arg) if arg > 0
  end
end
