#
#   finalizer.rb - 
#   	$Release Version: 0.2$
#   	$Revision: 1.3 $
#   	$Date: 1998/01/09 08:09:49 $
#   	by Keiju ISHITSUKA
#
# --
#
#   Usage:
#
#   add(obj, dependant, method = :finalize, *opt)
#   add_dependency(obj, dependant, method = :finalize, *opt)
#	依存関係 R_method(obj, dependant) の追加
#
#   delete(obj_or_id, dependant, method = :finalize)
#   delete_dependency(obj_or_id, dependant, method = :finalize)
#	依存関係 R_method(obj, dependant) の削除
#   delete_all_dependency(obj_or_id, dependant)
#	依存関係 R_*(obj, dependant) の削除
#   delete_by_dependant(dependant, method = :finalize)
#	依存関係 R_method(*, dependant) の削除
#   delete_all_by_dependant(dependant)
#	依存関係 R_*(*, dependant) の削除
#   delete_all
#	全ての依存関係の削除.
#
#   finalize(obj_or_id, dependant, method = :finalize)
#   finalize_dependency(obj_or_id, dependant, method = :finalize)
#	依存関連 R_method(obj, dependtant) で結ばれるdependantを
#	finalizeする.
#   finalize_all_dependency(obj_or_id, dependant)
#	依存関連 R_*(obj, dependtant) で結ばれるdependantをfinalizeする.
#   finalize_by_dependant(dependant, method = :finalize)
#	依存関連 R_method(*, dependtant) で結ばれるdependantをfinalizeする.
#   fainalize_all_by_dependant(dependant)
#	依存関連 R_*(*, dependtant) で結ばれるdependantをfinalizeする.
#   finalize_all
#	Finalizerに登録される全てのdependantをfinalizeする
#
#   safe{..}
#	gc時にFinalizerが起動するのを止める.
#
#

module Finalizer
  RCS_ID='-$Header: /home/keiju/var/src/var.lib/ruby/RCS/finalize.rb,v 1.3 1998/01/09 08:09:49 keiju Exp keiju $-'
  
  # @dependency: {id => [[dependant, method, *opt], ...], ...}
  
  # 依存関係 R_method(obj, dependant) の追加
  def add_dependency(obj, dependant, method = :finalize, *opt)
    ObjectSpace.call_finalizer(obj)
    method = method.intern unless method.kind_of?(Integer)
    assoc = [dependant, method].concat(opt)
    if dep = @dependency[obj.id]
      dep.push assoc
    else
      @dependency[obj.id] = [assoc]
    end
  end
  alias add add_dependency
  
  # 依存関係 R_method(obj, dependant) の削除
  def delete_dependency(id, dependant, method = :finalize)
    id = id.id unless id.kind_of?(Integer)
    method = method.intern unless method.kind_of?(Integer)
    for assoc in @dependency[id]
      assoc.delete_if do
	|d, m, *o|
	d == dependant && m == method
      end
      @dependency.delete(id) if assoc.empty?
    end
  end
  alias delete delete_dependency
  
  # 依存関係 R_*(obj, dependant) の削除
  def delete_all_dependency(id, dependant)
    id = id.id unless id.kind_of?(Integer)
    method = method.intern unless method.kind_of?(Integer)
    for assoc in @dependency[id]
      assoc.delete_if do
	|d, m, *o|
	d == dependant
      end
      @dependency.delete(id) if assoc.empty?
    end
  end
  
  # 依存関係 R_method(*, dependant) の削除
  def delete_by_dependant(dependant, method = :finalize)
    method = method.intern unless method.kind_of?(Integer)
    for id in Dependency.keys
      delete(id, dependant, method)
    end
  end
  
  # 依存関係 R_*(*, dependant) の削除
  def delete_all_by_dependant(dependant)
    for id in @dependency.keys
      delete_all_dependency(id, dependant)
    end
  end
  
  # 依存関連 R_method(obj, dependtant) で結ばれるdependantをfinalizeす
  # る.
  def finalize_dependency(id, dependant, method = :finalize)
    id = id.id unless id.kind_of?(Integer)
    method = method.intern unless method.kind_of?(Integer)
    for assocs in @dependency[id]
      assocs.delete_if do
	|d, m, *o|
	d.send(m, *o) if ret = d == dependant && m == method
	ret
      end
      @dependency.delete(id) if assoc.empty?
    end
  end
  alias finalize finalize_dependency
  
  # 依存関連 R_*(obj, dependtant) で結ばれるdependantをfinalizeする.
  def finalize_all_dependency(id, dependant)
    id = id.id unless id.kind_of?(Integer)
    method = method.intern unless method.kind_of?(Integer)
    for assoc in @dependency[id]
      assoc.delete_if do
	|d, m, *o|
	d.send(m, *o) if ret = d == dependant
      end
      @dependency.delete(id) if assoc.empty?
    end
  end
  
  # 依存関連 R_method(*, dependtant) で結ばれるdependantをfinalizeする.
  def finalize_by_dependant(dependant, method = :finalize)
    method = method.intern unless method.kind_of?(Integer)
    for id in @dependency.keys
      finalize(id, dependant, method)
    end
  end
  
  # 依存関連 R_*(*, dependtant) で結ばれるdependantをfinalizeする.
  def fainalize_all_by_dependant(dependant)
    for id in @dependency.keys
      finalize_all_dependency(id, dependant)
    end
  end
  
  # Finalizerに登録されている全てのdependantをfinalizeする
  def finalize_all
    for id, assocs in @dependency
      for dependant, method, *opt in assocs
	dependant.send(method, id, *opt)
      end
      assocs.clear
    end
  end
  
  # finalize_* を安全に呼び出すためのイテレータ
  def safe
    old_status = Thread.critical
    Thread.critical = TRUE
    ObjectSpace.remove_finalizer(@proc)
    yield
    ObjectSpace.add_finalizer(@proc)
    Thread.critical = old_status
  end
  
  # ObjectSpace#add_finalizerへの登録関数
  def final_of(id)
    if assocs = @dependency.delete(id)
      for dependant, method, *opt in assocs
	dependant.send(method, id, *opt)
      end
    end
  end
  
  @dependency = Hash.new
  @proc = proc{|id| final_of(id)}
  ObjectSpace.add_finalizer(@proc)

  module_function :add
  module_function :add_dependency
  
  module_function :delete
  module_function :delete_dependency
  module_function :delete_all_dependency
  module_function :delete_by_dependant
  module_function :delete_all_by_dependant
  
  module_function :finalize
  module_function :finalize_dependency
  module_function :finalize_all_dependency
  module_function :finalize_by_dependant
  module_function :fainalize_all_by_dependant
  module_function :finalize_all

  module_function :safe
  
  module_function :final_of
  private_class_method :final_of
  
end

