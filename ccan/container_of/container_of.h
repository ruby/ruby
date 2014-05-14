/* CC0 (Public domain) - see ccan/licenses/CC0 file for details */
#ifndef CCAN_CONTAINER_OF_H
#define CCAN_CONTAINER_OF_H
#include "ccan/check_type/check_type.h"

/**
 * container_of - get pointer to enclosing structure
 * @member_ptr: pointer to the structure member
 * @containing_type: the type this member is within
 * @member: the name of this member within the structure.
 *
 * Given a pointer to a member of a structure, this macro does pointer
 * subtraction to return the pointer to the enclosing type.
 *
 * Example:
 *	struct foo {
 *		int fielda, fieldb;
 *		// ...
 *	};
 *	struct info {
 *		int some_other_field;
 *		struct foo my_foo;
 *	};
 *
 *	static struct info *foo_to_info(struct foo *foo)
 *	{
 *		return container_of(foo, struct info, my_foo);
 *	}
 */
#define container_of(member_ptr, containing_type, member)		\
	 ((containing_type *)						\
	  ((char *)(member_ptr)						\
	   - container_off(containing_type, member))			\
	  + check_types_match(*(member_ptr), ((containing_type *)0)->member))

/**
 * container_off - get offset to enclosing structure
 * @containing_type: the type this member is within
 * @member: the name of this member within the structure.
 *
 * Given a pointer to a member of a structure, this macro does
 * typechecking and figures out the offset to the enclosing type.
 *
 * Example:
 *	struct foo {
 *		int fielda, fieldb;
 *		// ...
 *	};
 *	struct info {
 *		int some_other_field;
 *		struct foo my_foo;
 *	};
 *
 *	static struct info *foo_to_info(struct foo *foo)
 *	{
 *		size_t off = container_off(struct info, my_foo);
 *		return (void *)((char *)foo - off);
 *	}
 */
#define container_off(containing_type, member)	\
	offsetof(containing_type, member)

/**
 * container_of_var - get pointer to enclosing structure using a variable
 * @member_ptr: pointer to the structure member
 * @container_var: a pointer of same type as this member's container
 * @member: the name of this member within the structure.
 *
 * Given a pointer to a member of a structure, this macro does pointer
 * subtraction to return the pointer to the enclosing type.
 *
 * Example:
 *	static struct info *foo_to_i(struct foo *foo)
 *	{
 *		struct info *i = container_of_var(foo, i, my_foo);
 *		return i;
 *	}
 */
#if HAVE_TYPEOF
#define container_of_var(member_ptr, container_var, member) \
	container_of(member_ptr, typeof(*container_var), member)
#else
#define container_of_var(member_ptr, container_var, member)	\
	((void *)((char *)(member_ptr)	-			\
		  container_off_var(container_var, member)))
#endif

/**
 * container_off_var - get offset of a field in enclosing structure
 * @container_var: a pointer to a container structure
 * @member: the name of a member within the structure.
 *
 * Given (any) pointer to a structure and a its member name, this
 * macro does pointer subtraction to return offset of member in a
 * structure memory layout.
 *
 */
#if HAVE_TYPEOF
#define container_off_var(var, member)		\
	container_off(typeof(*var), member)
#else
#define container_off_var(var, member)			\
	((char *)&(var)->member - (char *)(var))
#endif

#endif /* CCAN_CONTAINER_OF_H */
