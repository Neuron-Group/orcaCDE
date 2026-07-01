#ifndef NSCDE_RUNTIME_CLIENT_H
#define NSCDE_RUNTIME_CLIENT_H

#include <stdbool.h>
#include <stddef.h>
#include <poll.h>

#define NSCDE_RUNTIME_FIELD_LEN 256
#define NSCDE_FD_REACTOR_MAX_WATCHERS 16

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

struct nscde_runtime_publisher {
	int fd;
};

typedef void (*nscde_fd_reactor_ready_fn)(
	int fd, short revents, void *userdata);

typedef struct nscde_fd_reactor_watcher {
	int fd;
	short events;
	nscde_fd_reactor_ready_fn on_ready;
	nscde_fd_reactor_ready_fn on_error;
	void *userdata;
	bool active;
} nscde_fd_reactor_watcher;

typedef struct nscde_fd_reactor {
	nscde_fd_reactor_watcher watchers[NSCDE_FD_REACTOR_MAX_WATCHERS];
} nscde_fd_reactor;

typedef void (*nscde_runtime_frame_handler_fn)(
	const struct nscde_runtime_frame *frame, void *userdata);

bool
nscde_runtime_query_topic(const char *topic, char **out_contents);

bool
nscde_runtime_ctl_workspace_switch(const char *workspace_name);

bool
nscde_runtime_publish_topic(const char *topic, const char *contents);

bool
nscde_runtime_publisher_open(const char *role, const char *topics,
	struct nscde_runtime_publisher *publisher);

bool
nscde_runtime_publisher_send(struct nscde_runtime_publisher *publisher,
	const char *topic, const char *contents);

void
nscde_runtime_publisher_close(struct nscde_runtime_publisher *publisher);

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

void
nscde_fd_reactor_init(nscde_fd_reactor *reactor);

bool
nscde_fd_reactor_add(nscde_fd_reactor *reactor, int fd, short events,
	nscde_fd_reactor_ready_fn on_ready,
	nscde_fd_reactor_ready_fn on_error, void *userdata);

void
nscde_fd_reactor_remove(nscde_fd_reactor *reactor, int fd);

bool
nscde_fd_reactor_run_once(nscde_fd_reactor *reactor, int timeout_ms);

#endif
