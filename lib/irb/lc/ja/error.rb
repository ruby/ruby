#
#   irb/lc/ja/error.rb - 
#   	$Release Version: 0.7.3$
#   	$Revision$
#   	$Date$
#   	by Keiju ISHITSUKA(keiju@ishitsuka.com)
#
# --
#
#   
#
require "e2mmap"

module IRB
  # exceptions (JP: 例外定義)
  extend Exception2MessageMapper
  def_exception :UnrecognizedSwitch, 'スイッチ(%s)が分りません'
  def_exception :NotImplementError, '`%s\'の定義が必要です'
  def_exception :CantRetuenNormalMode, 'Normalモードに戻れません.'
  def_exception :IllegalParameter, 'パラメータ(%s)が間違っています.'
  def_exception :IrbAlreadyDead, 'Irbは既に死んでいます.'
  def_exception :IrbSwitchToCurrentThread, 'Change to current thread.'
  def_exception :NoSuchJob, 'そのようなジョブ(%s)はありません.'
  def_exception :CanNotGoMultiIrbMode, 'multi-irb modeに移れません.'
  def_exception :CanNotChangeBinding, 'バインディング(%s)に変更できません.'
  def_exception :UndefinedPromptMode, 'プロンプトモード(%s)は定義されていません.'
end


