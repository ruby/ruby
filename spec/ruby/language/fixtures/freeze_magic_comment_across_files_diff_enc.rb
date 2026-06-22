# frozen_string_literal: true

require_relative 'freeze_magic_comment_required_diff_enc'

p !"abc".equal?($second_literal)
$second_literal = nil
