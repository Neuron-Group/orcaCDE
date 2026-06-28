#ifndef NSCDE_RUNTIME_CLIENT_H
#define NSCDE_RUNTIME_CLIENT_H

#include <stdbool.h>
#include <stddef.h>

#define NSCDE_RUNTIME_FIELD_LEN 256

enum nscde_runtime_frame_type {
	NSCDE_RUNTIME_FRAME_NONE = 0,
	NSCDE_RUNTIME_FRAME_STATE,
	NSCDE_RUNTIME_FRAME_ACK,
	NSCDE_RUNTIME_FRAME_ERROR,
};

enum nscde_runtime_read_result {
	NSCDE_RUNTIME_READ_ERROR = -1,
	NSCDE_RUNTIME_READ_NONE = 0,
	NSCDE_RUNTIME_READ_FRAME = 1,
	NSCDE_RUNTIME_READ_CLOSED = 2,
};

struct nscde_runtime_frame {
	enum nscde_runtime_frame_type type;
	char topic[NSCDE_RUNTIME_FIELD_LEN];
	char message[NSCDE_RUNTIME_FIELD_LEN];
	char *contents;
};

struct nscde_runtime_subscription {
	int fd;
	char *buffer;
	size_t buffer_len;
	size_t buffer_cap;
};

typedef void (*nscde_runtime_frame_handler_fn)(
	const struct nscde_runtime_frame *frame, void *userdata);

bool
nscde_runtime_query_topic(const char *topic, char **out_contents);

bool
nscde_runtime_ctl_workspace_switch(const char *workspace_name);

bool
nscde_runtime_publish_topic(const char *topic, const char *contents);

bool
nscde_runtime_subscribe_topics(const char *topics,
	struct nscde_runtime_subscription *subscription);

enum nscde_runtime_read_result
nscde_runtime_subscription_read(struct nscde_runtime_subscription *subscription,
	struct nscde_runtime_frame *out_frame);

enum nscde_runtime_read_result
nscde_runtime_subscription_drain(struct nscde_runtime_subscription *subscription,
	nscde_runtime_frame_handler_fn handler, void *userdata,
	char *error_message, size_t error_message_size);

void
nscde_runtime_subscription_init(struct nscde_runtime_subscription *subscription);

void
nscde_runtime_subscription_close(struct nscde_runtime_subscription *subscription);

void
nscde_runtime_frame_destroy(struct nscde_runtime_frame *frame);

#endif
