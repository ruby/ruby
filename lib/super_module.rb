# = super_module -- allows a module to define and invoke class methods the same way a superclass does
#
# Documentation by Annas Al Maleh (a.k.a. Andy Maleh)

##
# SuperModule allows defining and invoking class methods just like a superclass by doing so in the 
# module definition body. This removes the need to delay the definition and invocation of class methods
# via self.included(base)
#
# Using SuperModule therefore facilitates writing correct mixin code that is easily and productively 
# maintainable by following the same familiar semantics of superclass code definition. 
#
# SuperModule does support module dependencies by allowing a module to include other modules, even if
# they depend on base class methods. This achieves better visibility and maintainability of module 
# dependencies.
#
# To use, simply include SuperModule at the top of a module definition body, and then follow it by 
# including other module dependencies if needed, base class method invocations, base class method
# definitions, and instance method definitions.
#
# The following serves as a nice example for the use of SuperModule:
#
#   require 'super_module'
#   
#   module UserIdentifiable
#     include SuperModule
#  
#     belongs_to :user
#     validates :user_id, presence: true
#  
#     def self.most_active_user
#       User.find_by_id(select('count(id) as head_count, user_id').group('user_id').order('count(id) desc').first.user_id)
#     end
#  
#     def slug
#       "#{self.class.name}_#{id}_user_#{user_id}"
#     end
#   end
#
#   class ClubParticipation < ActiveRecord::Base
#     include UserIdentifiable
#   end
#  
#   class CourseEnrollment < ActiveRecord::Base
#     include UserIdentifiable
#   end
#  
#   module Accountable
#     include SuperModule
#     include UserIdentifiable
#   end
#  
#   class Activity < ActiveRecord::Base
#     include Accountable
#   end
#  
#   CourseEnrollment.most_active_user
#   ClubParticipation.most_active_user
#   Activity.last.slug
#   ClubParticipation.create(club_id: club.id, user_id: user.id).slug
#   CourseEnrollment.new(course_id: course.id).valid?
#  
# == Notes
#
# SuperModule was designed to be used in the code definition of a module and must be included
# at the very top of the body definition before including any other modules
#
# As with regular module inclusion in a base class, make sure any methods that the "super module"
# (module enhanced with SuperModule) depends on have been defined in the class or superclass
# above (before) the inclusion of the "super module".
# 
#

module SuperModule
  EXCLUDED_SINGLETON_METHODS = [
    :__super_module_class_methods,
    :__invoke_super_module_class_method_calls,
    :__define_super_module_class_methods,
    :__restore_original_method_missing,
    :included, :method_missing,
    :singleton_method_added
  ]
  def self.included(base)
    class << base
      def include(base, &block)
        method_missing('include', base, &block)
      end
      
      def __super_module_class_method_calls
        @__super_module_class_method_calls ||= []
      end
      
      def __super_module_class_methods
        @__super_module_class_methods ||= []
      end
      
      def singleton_method_added(method_name)
        __super_module_class_methods << [method_name, method(method_name)] unless EXCLUDED_SINGLETON_METHODS.include?(method_name)
        super
      end
      
      def method_missing(method_name, *args, &block)
        __super_module_class_method_calls << [method_name, args, block]
      end
      
      def __invoke_super_module_class_method_calls(base)
        __super_module_class_method_calls.each do |method_name, args, block|
          base.class_eval do
            send(method_name, *args, &block)
          end
        end
      end
      
      def __define_super_module_class_methods(base)
        __super_module_class_methods.each do |method_name, method|
          base.class_eval do
            self.class.send(:define_method, method_name, &method)
          end
        end
      end
      
      def included(base)
        __invoke_super_module_class_method_calls(base)
        __define_super_module_class_methods(base)
      end
    end
  end
end
