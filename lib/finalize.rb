#
#   finalizer.rb - 
#   	$Release Version: 0.2$
#   	$Revision: 1.1.1.2.2.2 $
#   	$Date: 1998/01/19 05:08:24 $
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
#   delete(obj, dependant, method = :finalize)
#   delete_dependency(obj, dependant, method = :finalize)
#	依存関係 R_method(obj, dependant) の削除
#   delete_all_dependency(obj, dependant)
#	依存関係 R_*(obj, dependant) の削除
#   delete_by_dependant(dependant, method = :finalize)
#	依存関係 R_method(*, dependant) の削除
#   delete_all_by_dependant(dependant)
#	依存関係 R_*(*, dependant) の削除
#   delete_all
#	全ての依存関係の削除.
#
#   finalize(obj, dependant, method = :finalize)
#   finalize_dependency(obj, dependant, method = :finalize)
#	依存関連 R_method(obj, dependtant) で結ばれるdependantを
#	finalizeする.
#   finalize_all_dependency(obj, dependant)
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
  RCS_ID='-$Header: /home/cvsroot/ruby/lib/finalize.rb,v 1.1.1.2.2.2 1998/01/19 05:08:24 matz Exp $-'

  # Dependency: {id => [[dependant, method, opt], ...], ...}
  Dependency = {}

  # 依存関係 R_method(obj, dependant) の追加
  def add_dependency(obj, dependant, method = :finalize, *opt)
    ObjectSpace.call_finalizer(obj)
    assoc = [dependant, method, opt]
    if dep = Dependency[obj.id]
      dep.push assoc
    else
      Dependency[obj.id] = [assoc]
    end
  end
  alias add add_dependency

  # 依存関係 R_method(obj, dependant) の削除
  def delete_dependency(obj, dependant, method = :finalize)
    id = obj.id
    for assoc in Dependency[id]
      assoc.delete_if do |d,m,*o|
	d == dependant && m == method
      end
      Dependency.delete(id) if assoc.empty?
    end
  end
  alias delete delete_dependency

  # 依存関係 R_*(obj, dependant) の削除
  def delete_all_dependency(obj, dependant)
    id = obj.id
    for assoc in Dependency[id]
      assoc.delete_if do |d,m,*o|
	d == dependant
      end
      Dependency.delete(id) if assoc.empty?
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
    for id in Dependency.keys
      delete_all_dependency(id, dependant)
    end
  end

  # 依存関連 R_method(id, dependtant) で結ばれるdependantをfinalizeす
  # る.
  def finalize_dependency(id, dependant, method = :finalize)
    for assocs in Dependency[id]
      assocs.delete_if do |d, m, *o|
	if d == dependant && m == method
	  d.send(m, *o)
	  true
	else
	  false
	end
      end
      Dependency.delete(id) if assoc.empty?
    end
  end
  alias finalize finalize_dependency

  # 依存関連 R_*(id, dependtant) で結ばれるdependantをfinalizeする.
  def finalize_all_dependency(id, dependant)
    for assoc in Dependency[id]
      assoc.delete_if do |d, m, *o|
	if d == dependant
	  d.send(m, *o)
	  true
	else
	  false
	end
      end
      Dependency.delete(id) if assoc.empty?
    end
  end

  # 依存関連 R_method(*, dependtant) で結ばれるdependantをfinalizeする.
  def finalize_by_dependant(dependant, method = :finalize)
    for id in Dependency.keys
      finalize(id, dependant, method)
    end
  end

  # 依存関連 R_*(*, dependtant) で結ばれるdependantをfinalizeする.
  def fainalize_all_by_dependant(dependant)
    for id in Dependency.keys
      finalize_all_dependency(id, dependant)
    end
  end

  # Finalizerに登録されている全てのdependantをfinalizeする
  def finalize_all
    for id, assocs in Dependency
      for dependant, method, *opt in assocs
	dependant.send(method, id, *opt)
      end
      assocs.clear
    end
  end

  # finalize_* を安全に呼び出すためのイテレータ
  def safe
    old_status, Thread.critical = Thread.critical, true
    ObjectSpace.remove_finalizer(Proc)
    begin
      yield
    ensure
      ObjectSpace.add_finalizer(Proc)
      Thread.critical = old_status
    end
  end

  # ObjectSpace#add_finalizerへの登録関数
  def final_of(id)
    if assocs = Dependency.delete(id)
      for dependant, method, *opt in assocs
	dependant.send(method, id, *opt)
      end
    end
  end

  Proc = proc{|id| final_of(id)}
  ObjectSpace.add_finalizer(Proc)

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
