#include "yarp/include/yarp/util/yp_list.h"

// Allocate a new list.
yp_list_t *
yp_list_alloc(void) {
  return malloc(sizeof(yp_list_t));
}

// Initializes a new list.
__attribute__((__visibility__("default"))) extern void
yp_list_init(yp_list_t *list) {
  *list = (yp_list_t) { .head = NULL, .tail = NULL };
}

// Returns true if the given list is empty.
__attribute__((__visibility__("default"))) extern bool
yp_list_empty_p(yp_list_t *list) {
  return list->head == NULL;
}

// Append a node to the given list.
void
yp_list_append(yp_list_t *list, yp_list_node_t *node) {
  if (list->head == NULL) {
    list->head = node;
  } else {
    list->tail->next = node;
  }
  list->tail = node;
}

// Deallocate the internal state of the given list.
__attribute__((__visibility__("default"))) extern void
yp_list_free(yp_list_t *list) {
  yp_list_node_t *node = list->head;
  yp_list_node_t *next;

  while (node != NULL) {
    next = node->next;
    free(node);
    node = next;
  }
}
