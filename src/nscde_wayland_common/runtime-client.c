#define _POSIX_C_SOURCE 200809L

#include "runtime-client.h"

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

#define PATH_MAX_LEN 1024
#define FRAME_DELIM "\n\n"
#define FRAME_CHUNK_SIZE 4096

static bool append_bytes(struct nscde_runtime_subscription *subscription,
	const char *bytes, size_t len);
static bool append_text(char **buffer, size_t *buffer_len, size_t *buffer_cap,
	const char *text, size_t text_len);
static bool connect_runtime_socket(bool nonblock, int *out_fd);
static bool copy_text(char *dest, size_t dest_size, const char *src);
static char *extract_frame_from_buffer(struct nscde_runtime_subscription *subscription);
static const char *find_frame_delim(const char *text);
static struct nscde_runtime_topic_cache_entry *find_topic_cache(
	struct nscde_runtime_subscription *subscription, const char *topic,
	bool create_if_missing);
static void merge_topic_cache(struct nscde_runtime_subscription *subscription,
	const struct nscde_runtime_frame *frame);
static void parse_frame_metadata(const char *contents,
	struct nscde_runtime_frame *frame);
static bool topic_cache_remove_key(struct nscde_runtime_topic_cache_entry *cache,
	const char *key);
static bool topic_cache_set_key(struct nscde_runtime_topic_cache_entry *cache,
	const char *key, const char *value);
static char *read_response_frame(int fd);
static bool resolve_socket_path(char *dest, size_t dest_size);
static bool resolve_state_dir(char *dest, size_t dest_size);
static bool set_nonblock(int fd);
static bool send_frame_request(int fd, const char *request_text);
static char *string_duplicate(const char *text);
static char *split_csv_token(char **cursor);
static bool write_text(char *dest, size_t dest_size, const char *src);

bool
nscde_runtime_query_topic(const char *topic, char **out_contents)
{
	int fd = -1;
	char request[NSCDE_RUNTIME_FIELD_LEN * 2];
	char *response;
	struct nscde_runtime_frame frame = {0};

	if (!topic || !topic[0] || !out_contents) {
		return false;
	}

	*out_contents = NULL;

	if (!connect_runtime_socket(false, &fd)) {
		return false;
	}

	snprintf(request, sizeof(request), "TYPE=query\nTOPIC=%s\n\n", topic);
	if (!send_frame_request(fd, request)) {
		close(fd);
		return false;
	}

	response = read_response_frame(fd);
	close(fd);
	if (!response) {
		return false;
	}

	frame.contents = response;
	parse_frame_metadata(response, &frame);
	if (frame.type != NSCDE_RUNTIME_FRAME_STATE) {
		nscde_runtime_frame_destroy(&frame);
		return false;
	}
	if (frame.topic[0] && strcmp(frame.topic, topic) != 0) {
		nscde_runtime_frame_destroy(&frame);
		return false;
	}

	*out_contents = response;
	frame.contents = NULL;
	nscde_runtime_frame_destroy(&frame);
	return true;
}

bool
nscde_runtime_ctl_workspace_switch(const char *workspace_name)
{
	int fd = -1;
	char request[PATH_MAX_LEN];
	char *response;
	struct nscde_runtime_frame frame = {0};
	bool success = false;

	if (!workspace_name || !workspace_name[0]) {
		return false;
	}

	if (!connect_runtime_socket(false, &fd)) {
		return false;
	}

	snprintf(request, sizeof(request),
		"TYPE=command\nNAME=workspace-switch\nWORKSPACE=%s\n\n",
		workspace_name);
	if (!send_frame_request(fd, request)) {
		close(fd);
		return false;
	}

	response = read_response_frame(fd);
	close(fd);
	if (!response) {
		return false;
	}

	frame.contents = response;
	parse_frame_metadata(response, &frame);
	success = frame.type == NSCDE_RUNTIME_FRAME_ACK;
	nscde_runtime_frame_destroy(&frame);
	return success;
}

bool
nscde_runtime_publish_topic(const char *topic, const char *contents)
{
	int fd = -1;
	char *request = NULL;
	size_t request_len;
	char *response;
	struct nscde_runtime_frame frame = {0};
	bool success = false;

	if (!topic || !topic[0]) {
		return false;
	}

	if (!connect_runtime_socket(false, &fd)) {
		return false;
	}

	request_len = strlen(topic) + strlen(contents ? contents : "") + 32;
	request = malloc(request_len);
	if (!request) {
		close(fd);
		return false;
	}

	snprintf(request, request_len,
		"TYPE=command\nNAME=publish-state\nTOPIC=%s\n%s\n",
		topic, contents ? contents : "");
	if (!send_frame_request(fd, request)) {
		free(request);
		close(fd);
		return false;
	}
	free(request);

	response = read_response_frame(fd);
	close(fd);
	if (!response) {
		return false;
	}

	frame.contents = response;
	parse_frame_metadata(response, &frame);
	success = frame.type == NSCDE_RUNTIME_FRAME_ACK;
	nscde_runtime_frame_destroy(&frame);
	return success;
}

bool
nscde_runtime_publisher_open(const char *role, const char *topics,
	struct nscde_runtime_publisher *publisher)
{
	int fd = -1;
	char request[PATH_MAX_LEN];
	char *response;
	struct nscde_runtime_frame frame = {0};
	bool success = false;

	if (!role || !role[0] || !topics || !topics[0] || !publisher) {
		return false;
	}

	if (!connect_runtime_socket(false, &fd)) {
		return false;
	}

	snprintf(request, sizeof(request),
		"TYPE=publish-stream\nROLE=%s\nTOPICS=%s\n\n", role, topics);
	if (!send_frame_request(fd, request)) {
		close(fd);
		return false;
	}

	response = read_response_frame(fd);
	if (!response) {
		close(fd);
		return false;
	}

	frame.contents = response;
	parse_frame_metadata(response, &frame);
	success = frame.type == NSCDE_RUNTIME_FRAME_ACK;
	nscde_runtime_frame_destroy(&frame);
	if (!success) {
		close(fd);
		return false;
	}

	nscde_runtime_publisher_close(publisher);
	publisher->fd = fd;
	return true;
}

bool
nscde_runtime_publisher_send(struct nscde_runtime_publisher *publisher,
	const char *topic, const char *contents)
{
	char *request = NULL;
	size_t request_len;

	if (!publisher || publisher->fd < 0 || !topic || !topic[0]) {
		return false;
	}

	request_len = strlen(topic) + strlen(contents ? contents : "") + 24;
	request = malloc(request_len);
	if (!request) {
		return false;
	}

	snprintf(request, request_len, "TYPE=state\nTOPIC=%s\n%s\n",
		topic, contents ? contents : "");
	if (!send_frame_request(publisher->fd, request)) {
		free(request);
		return false;
	}
	free(request);
	return true;
}

void
nscde_runtime_publisher_close(struct nscde_runtime_publisher *publisher)
{
	if (!publisher) {
		return;
	}

	if (publisher->fd >= 0) {
		close(publisher->fd);
	}
	publisher->fd = -1;
}

bool
nscde_runtime_subscribe_topics(const char *topics,
	struct nscde_runtime_subscription *subscription)
{
	int fd = -1;
	char request[PATH_MAX_LEN];

	if (!topics || !topics[0] || !subscription) {
		return false;
	}

	if (!connect_runtime_socket(false, &fd)) {
		return false;
	}

	snprintf(request, sizeof(request),
		"TYPE=subscribe-events\nTOPICS=%s\nBOOTSTRAP=1\n\n", topics);
	if (!send_frame_request(fd, request) || !set_nonblock(fd)) {
		close(fd);
		return false;
	}

	nscde_runtime_subscription_close(subscription);
	subscription->fd = fd;
	return true;
}

enum nscde_runtime_read_result
nscde_runtime_subscription_read(struct nscde_runtime_subscription *subscription,
	struct nscde_runtime_frame *out_frame)
{
	char *contents;
	char chunk[FRAME_CHUNK_SIZE];
	ssize_t bytes_read;

	if (!subscription || subscription->fd < 0 || !out_frame) {
		return NSCDE_RUNTIME_READ_ERROR;
	}

	memset(out_frame, 0, sizeof(*out_frame));

	contents = extract_frame_from_buffer(subscription);
	if (contents) {
		out_frame->contents = contents;
		parse_frame_metadata(contents, out_frame);
		return NSCDE_RUNTIME_READ_FRAME;
	}

	for (;;) {
		bytes_read = read(subscription->fd, chunk, sizeof(chunk));
		if (bytes_read < 0 && errno == EINTR) {
			continue;
		}
		break;
	}

	if (bytes_read < 0) {
		if (errno == EAGAIN || errno == EWOULDBLOCK) {
			return NSCDE_RUNTIME_READ_NONE;
		}
		return NSCDE_RUNTIME_READ_ERROR;
	}
	if (bytes_read == 0) {
		return NSCDE_RUNTIME_READ_CLOSED;
	}
	if (!append_bytes(subscription, chunk, (size_t)bytes_read)) {
		return NSCDE_RUNTIME_READ_ERROR;
	}

	contents = extract_frame_from_buffer(subscription);
	if (!contents) {
		return NSCDE_RUNTIME_READ_NONE;
	}

	out_frame->contents = contents;
	parse_frame_metadata(contents, out_frame);
	if (out_frame->type == NSCDE_RUNTIME_FRAME_SNAPSHOT ||
		out_frame->type == NSCDE_RUNTIME_FRAME_EVENT) {
		struct nscde_runtime_topic_cache_entry *cache;

		merge_topic_cache(subscription, out_frame);
		free(out_frame->contents);
		out_frame->contents = NULL;
		cache = find_topic_cache(subscription, out_frame->topic, false);
		if (cache && cache->contents && cache->contents_len > 0) {
			out_frame->contents = malloc(cache->contents_len + 1);
			if (!out_frame->contents) {
				return NSCDE_RUNTIME_READ_ERROR;
			}
			memcpy(out_frame->contents, cache->contents,
				cache->contents_len + 1);
		}
	}
	return NSCDE_RUNTIME_READ_FRAME;
}

enum nscde_runtime_read_result
nscde_runtime_subscription_drain(struct nscde_runtime_subscription *subscription,
	nscde_runtime_frame_handler_fn handler, void *userdata,
	char *error_message, size_t error_message_size)
{
	enum nscde_runtime_read_result result;

	if (error_message && error_message_size > 0) {
		error_message[0] = '\0';
	}

	for (;;) {
		struct nscde_runtime_frame frame = {0};

		result = nscde_runtime_subscription_read(subscription, &frame);
		if (result != NSCDE_RUNTIME_READ_FRAME) {
			return result;
		}

		if (frame.type == NSCDE_RUNTIME_FRAME_ERROR) {
			if (frame.message[0]) {
				write_text(error_message, error_message_size, frame.message);
			}
			nscde_runtime_frame_destroy(&frame);
			return NSCDE_RUNTIME_READ_ERROR;
		}

		if (handler) {
			handler(&frame, userdata);
		}
		nscde_runtime_frame_destroy(&frame);
	}
}

void
nscde_runtime_subscription_init(struct nscde_runtime_subscription *subscription)
{
	if (!subscription) {
		return;
	}

	memset(subscription, 0, sizeof(*subscription));
	subscription->fd = -1;
}

void
nscde_runtime_subscription_close(struct nscde_runtime_subscription *subscription)
{
	if (!subscription) {
		return;
	}

	if (subscription->fd >= 0) {
		close(subscription->fd);
	}
	free(subscription->buffer);
	subscription->buffer = NULL;
	subscription->buffer_len = 0;
	subscription->buffer_cap = 0;
	for (size_t i = 0; i < NSCDE_RUNTIME_TOPIC_CACHE_MAX; i++) {
		free(subscription->topic_caches[i].contents);
		subscription->topic_caches[i].contents = NULL;
		subscription->topic_caches[i].contents_len = 0;
		subscription->topic_caches[i].contents_cap = 0;
		subscription->topic_caches[i].topic[0] = '\0';
		subscription->topic_caches[i].active = false;
	}
	subscription->fd = -1;
}

void
nscde_runtime_frame_destroy(struct nscde_runtime_frame *frame)
{
	if (!frame) {
		return;
	}

	free(frame->contents);
	memset(frame, 0, sizeof(*frame));
}

void
nscde_fd_reactor_init(nscde_fd_reactor *reactor)
{
	size_t i;

	if (!reactor) {
		return;
	}

	memset(reactor, 0, sizeof(*reactor));
	for (i = 0; i < NSCDE_FD_REACTOR_MAX_WATCHERS; i++) {
		reactor->watchers[i].fd = -1;
	}
}

bool
nscde_fd_reactor_add(nscde_fd_reactor *reactor, int fd, short events,
	nscde_fd_reactor_ready_fn on_ready,
	nscde_fd_reactor_ready_fn on_error, void *userdata)
{
	size_t i;

	if (!reactor || fd < 0 || !on_ready) {
		return false;
	}

	for (i = 0; i < NSCDE_FD_REACTOR_MAX_WATCHERS; i++) {
		if (!reactor->watchers[i].active) {
			reactor->watchers[i].fd = fd;
			reactor->watchers[i].events = events;
			reactor->watchers[i].on_ready = on_ready;
			reactor->watchers[i].on_error = on_error;
			reactor->watchers[i].userdata = userdata;
			reactor->watchers[i].active = true;
			return true;
		}
	}

	return false;
}

void
nscde_fd_reactor_remove(nscde_fd_reactor *reactor, int fd)
{
	size_t i;

	if (!reactor) {
		return;
	}

	for (i = 0; i < NSCDE_FD_REACTOR_MAX_WATCHERS; i++) {
		if (reactor->watchers[i].active && reactor->watchers[i].fd == fd) {
			reactor->watchers[i].active = false;
			reactor->watchers[i].fd = -1;
			reactor->watchers[i].events = 0;
			reactor->watchers[i].on_ready = NULL;
			reactor->watchers[i].on_error = NULL;
			reactor->watchers[i].userdata = NULL;
		}
	}
}

bool
nscde_fd_reactor_run_once(nscde_fd_reactor *reactor, int timeout_ms)
{
	struct pollfd pollfds[NSCDE_FD_REACTOR_MAX_WATCHERS];
	nscde_fd_reactor_watcher *watchers[NSCDE_FD_REACTOR_MAX_WATCHERS];
	size_t active_count = 0;
	size_t i;
	int ret;

	if (!reactor) {
		return false;
	}

	for (i = 0; i < NSCDE_FD_REACTOR_MAX_WATCHERS; i++) {
		if (!reactor->watchers[i].active || reactor->watchers[i].fd < 0) {
			continue;
		}

		pollfds[active_count].fd = reactor->watchers[i].fd;
		pollfds[active_count].events = reactor->watchers[i].events;
		pollfds[active_count].revents = 0;
		watchers[active_count] = &reactor->watchers[i];
		active_count++;
	}

	if (active_count == 0) {
		errno = EINVAL;
		return false;
	}

	ret = poll(pollfds, active_count, timeout_ms);
	if (ret <= 0) {
		return false;
	}

	for (i = 0; i < active_count; i++) {
		short revents = pollfds[i].revents;
		nscde_fd_reactor_watcher *watcher = watchers[i];

		if (!revents || !watcher->active) {
			continue;
		}

		if ((revents & (POLLERR | POLLHUP | POLLNVAL)) && watcher->on_error) {
			watcher->on_error(watcher->fd, revents, watcher->userdata);
			continue;
		}

		if ((revents & watcher->events) && watcher->on_ready) {
			watcher->on_ready(watcher->fd, revents, watcher->userdata);
		}
	}

	return true;
}

static bool
append_bytes(struct nscde_runtime_subscription *subscription,
	const char *bytes, size_t len)
{
	size_t required;
	size_t next_cap;
	char *grown;

	if (!len) {
		return true;
	}

	required = subscription->buffer_len + len + 1;
	if (required > subscription->buffer_cap) {
		next_cap = subscription->buffer_cap ? subscription->buffer_cap : FRAME_CHUNK_SIZE;
		while (required > next_cap) {
			next_cap *= 2;
		}
		grown = realloc(subscription->buffer, next_cap);
		if (!grown) {
			return false;
		}
		subscription->buffer = grown;
		subscription->buffer_cap = next_cap;
	}

	memcpy(subscription->buffer + subscription->buffer_len, bytes, len);
	subscription->buffer_len += len;
	subscription->buffer[subscription->buffer_len] = '\0';
	return true;
}

static bool
append_text(char **buffer, size_t *buffer_len, size_t *buffer_cap,
	const char *text, size_t text_len)
{
	size_t required;
	size_t next_cap;
	char *grown;

	if (!buffer || !buffer_len || !buffer_cap || !text) {
		return false;
	}

	required = *buffer_len + text_len + 1;
	if (required > *buffer_cap) {
		next_cap = *buffer_cap ? *buffer_cap : FRAME_CHUNK_SIZE;
		while (required > next_cap) {
			next_cap *= 2;
		}
		grown = realloc(*buffer, next_cap);
		if (!grown) {
			return false;
		}
		*buffer = grown;
		*buffer_cap = next_cap;
	}

	memcpy(*buffer + *buffer_len, text, text_len);
	*buffer_len += text_len;
	(*buffer)[*buffer_len] = '\0';
	return true;
}

static bool
connect_runtime_socket(bool nonblock, int *out_fd)
{
	int fd;
	struct sockaddr_un addr = {0};
	char socket_path[PATH_MAX_LEN];

	if (!out_fd || !resolve_socket_path(socket_path, sizeof(socket_path))) {
		return false;
	}

	fd = socket(AF_UNIX, SOCK_STREAM, 0);
	if (fd < 0) {
		return false;
	}

	addr.sun_family = AF_UNIX;
	if (!copy_text(addr.sun_path, sizeof(addr.sun_path), socket_path)) {
		close(fd);
		return false;
	}

	if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
		close(fd);
		return false;
	}
	if (nonblock && !set_nonblock(fd)) {
		close(fd);
		return false;
	}

	*out_fd = fd;
	return true;
}

static bool
copy_text(char *dest, size_t dest_size, const char *src)
{
	size_t len;

	if (!dest || !dest_size || !src) {
		return false;
	}

	len = strlen(src);
	if (len >= dest_size) {
		return false;
	}

	memcpy(dest, src, len + 1);
	return true;
}

static bool
write_text(char *dest, size_t dest_size, const char *src)
{
	if (!dest || dest_size == 0) {
		return false;
	}
	if (!src) {
		dest[0] = '\0';
		return true;
	}
	return copy_text(dest, dest_size, src);
}

static char *
extract_frame_from_buffer(struct nscde_runtime_subscription *subscription)
{
	const char *delim;
	size_t frame_len;
	size_t consumed_len;
	size_t remaining_len;
	char *frame;

	if (!subscription || !subscription->buffer || !subscription->buffer_len) {
		return NULL;
	}

	delim = find_frame_delim(subscription->buffer);
	if (!delim) {
		return NULL;
	}

	frame_len = (size_t)(delim - subscription->buffer);
	frame = malloc(frame_len + 1);
	if (!frame) {
		return NULL;
	}

	memcpy(frame, subscription->buffer, frame_len);
	frame[frame_len] = '\0';

	consumed_len = frame_len + strlen(FRAME_DELIM);
	remaining_len = subscription->buffer_len - consumed_len;
	memmove(subscription->buffer, subscription->buffer + consumed_len,
		remaining_len);
	subscription->buffer_len = remaining_len;
	subscription->buffer[remaining_len] = '\0';

	return frame;
}

static const char *
find_frame_delim(const char *text)
{
	if (!text) {
		return NULL;
	}

	return strstr(text, FRAME_DELIM);
}

static void
parse_frame_metadata(const char *contents, struct nscde_runtime_frame *frame)
{
	const char *line;

	if (!contents || !frame) {
		return;
	}

	for (line = contents; *line;) {
		const char *newline = strchr(line, '\n');
		const char *value;
		size_t line_len;
		size_t value_len;

		if (newline) {
			line_len = (size_t)(newline - line);
		} else {
			line_len = strlen(line);
		}
		if (line_len > 0 && line[line_len - 1] == '\r') {
			line_len--;
		}
		if (!line_len) {
			break;
		}

		if (line_len > 5 && !strncmp(line, "TYPE=", 5)) {
			value = line + 5;
			value_len = line_len - 5;
			if (value_len == 5 && !strncmp(value, "state", value_len)) {
				frame->type = NSCDE_RUNTIME_FRAME_STATE;
			} else if (value_len == 8 && !strncmp(value, "snapshot", value_len)) {
				frame->type = NSCDE_RUNTIME_FRAME_SNAPSHOT;
			} else if (value_len == 5 && !strncmp(value, "event", value_len)) {
				frame->type = NSCDE_RUNTIME_FRAME_EVENT;
			} else if (value_len == 3 && !strncmp(value, "ack", value_len)) {
				frame->type = NSCDE_RUNTIME_FRAME_ACK;
			} else if (value_len == 5 && !strncmp(value, "error", value_len)) {
				frame->type = NSCDE_RUNTIME_FRAME_ERROR;
			}
		} else if (line_len > 6 && !strncmp(line, "TOPIC=", 6)) {
			value = line + 6;
			value_len = line_len - 6;
			if (value_len >= sizeof(frame->topic)) {
				value_len = sizeof(frame->topic) - 1;
			}
			memcpy(frame->topic, value, value_len);
			frame->topic[value_len] = '\0';
		} else if (line_len > 8 && !strncmp(line, "MESSAGE=", 8)) {
			value = line + 8;
			value_len = line_len - 8;
			if (value_len >= sizeof(frame->message)) {
				value_len = sizeof(frame->message) - 1;
			}
			memcpy(frame->message, value, value_len);
			frame->message[value_len] = '\0';
		} else if (line_len > 6 && !strncmp(line, "EVENT=", 6)) {
			value = line + 6;
			value_len = line_len - 6;
			if (value_len >= sizeof(frame->event)) {
				value_len = sizeof(frame->event) - 1;
			}
			memcpy(frame->event, value, value_len);
			frame->event[value_len] = '\0';
		} else if (line_len > 7 && !strncmp(line, "SOURCE=", 7)) {
			value = line + 7;
			value_len = line_len - 7;
			if (value_len >= sizeof(frame->source)) {
				value_len = sizeof(frame->source) - 1;
			}
			memcpy(frame->source, value, value_len);
			frame->source[value_len] = '\0';
		} else if (line_len > 6 && !strncmp(line, "UNSET=", 6)) {
			value = line + 6;
			value_len = line_len - 6;
			if (value_len >= sizeof(frame->unset)) {
				value_len = sizeof(frame->unset) - 1;
			}
			memcpy(frame->unset, value, value_len);
			frame->unset[value_len] = '\0';
		} else if (line_len > 4 && !strncmp(line, "SEQ=", 4)) {
			frame->seq = atoll(line + 4);
		} else if (line_len > 6 && !strncmp(line, "RESET=", 6)) {
			frame->reset = line[6] == '1';
		}

		if (!newline) {
			break;
		}
		line = newline + 1;
	}
}

static void
merge_topic_cache(struct nscde_runtime_subscription *subscription,
	const struct nscde_runtime_frame *frame)
{
	struct nscde_runtime_topic_cache_entry *cache;
	char *copy = NULL;
	char *cursor = NULL;
	char *line;

	if (!subscription || !frame || !frame->contents || !frame->topic[0]) {
		return;
	}

	cache = find_topic_cache(subscription, frame->topic, true);
	if (!cache) {
		return;
	}

	if (frame->type == NSCDE_RUNTIME_FRAME_SNAPSHOT || frame->reset) {
		free(cache->contents);
		cache->contents = NULL;
		cache->contents_len = 0;
		cache->contents_cap = 0;
	}

	if (frame->unset[0]) {
		copy = string_duplicate(frame->unset);
		if (!copy) {
			return;
		}
		cursor = copy;
		for (;;) {
			char *token = split_csv_token(&cursor);
			if (!token) {
				break;
			}
			topic_cache_remove_key(cache, token);
			free(token);
		}
		free(copy);
		copy = NULL;
	}

	copy = string_duplicate(frame->contents);
	if (!copy) {
		return;
	}

	cursor = NULL;
	for (line = strtok_r(copy, "\n", &cursor);
		line;
		line = strtok_r(NULL, "\n", &cursor)) {
		char *equals = strchr(line, '=');
		if (!equals) {
			continue;
		}
		*equals = '\0';
		topic_cache_set_key(cache, line, equals + 1);
	}
	free(copy);
}

static struct nscde_runtime_topic_cache_entry *
find_topic_cache(struct nscde_runtime_subscription *subscription,
	const char *topic, bool create_if_missing)
{
	size_t i;

	if (!subscription || !topic || !topic[0]) {
		return NULL;
	}

	for (i = 0; i < NSCDE_RUNTIME_TOPIC_CACHE_MAX; i++) {
		if (subscription->topic_caches[i].active &&
			!strcmp(subscription->topic_caches[i].topic, topic)) {
			return &subscription->topic_caches[i];
		}
	}

	if (!create_if_missing) {
		return NULL;
	}

	for (i = 0; i < NSCDE_RUNTIME_TOPIC_CACHE_MAX; i++) {
		if (!subscription->topic_caches[i].active) {
			subscription->topic_caches[i].active = true;
			copy_text(subscription->topic_caches[i].topic,
				sizeof(subscription->topic_caches[i].topic), topic);
			return &subscription->topic_caches[i];
		}
	}

	return NULL;
}

static bool
topic_cache_remove_key(struct nscde_runtime_topic_cache_entry *cache,
	const char *key)
{
	char *result = NULL;
	size_t result_len = 0;
	size_t result_cap = 0;
	char *copy = NULL;
	char *cursor = NULL;
	char *line;
	size_t key_len;

	if (!cache || !key || !key[0]) {
		return false;
	}

	if (!cache->contents || !cache->contents_len) {
		return true;
	}

	key_len = strlen(key);
	copy = string_duplicate(cache->contents);
	if (!copy) {
		return false;
	}

	for (line = strtok_r(copy, "\n", &cursor);
		line;
		line = strtok_r(NULL, "\n", &cursor)) {
		if (!strncmp(line, key, key_len) && line[key_len] == '=') {
			continue;
		}
		if (!append_text(&result, &result_len, &result_cap, line, strlen(line))
			|| !append_text(&result, &result_len, &result_cap, "\n", 1)) {
			free(copy);
			free(result);
			return false;
		}
	}

	free(copy);
	free(cache->contents);
	cache->contents = result;
	cache->contents_len = result_len;
	cache->contents_cap = result_cap;
	return true;
}

static bool
topic_cache_set_key(struct nscde_runtime_topic_cache_entry *cache,
	const char *key, const char *value)
{
	size_t key_len;
	size_t value_len;

	if (!cache || !key || !value) {
		return false;
	}

	key_len = strlen(key);
	value_len = strlen(value);
	if (!topic_cache_remove_key(cache, key)) {
		return false;
	}

	if (!append_text(&cache->contents, &cache->contents_len,
		&cache->contents_cap, key, key_len) ||
		!append_text(&cache->contents, &cache->contents_len,
		&cache->contents_cap, "=", 1) ||
		!append_text(&cache->contents, &cache->contents_len,
		&cache->contents_cap, value, value_len) ||
		!append_text(&cache->contents, &cache->contents_len,
		&cache->contents_cap, "\n", 1)) {
		return false;
	}

	return true;
}

static char *
split_csv_token(char **cursor)
{
	char *token;
	char *comma;

	if (!cursor || !*cursor || !(*cursor)[0]) {
		return NULL;
	}

	token = *cursor;
	comma = strchr(token, ',');
	if (comma) {
		*comma = '\0';
		*cursor = comma + 1;
	} else {
		*cursor = token + strlen(token);
	}

	return string_duplicate(token);
}

static char *
string_duplicate(const char *text)
{
	size_t len;
	char *copy;

	if (!text) {
		return NULL;
	}

	len = strlen(text);
	copy = malloc(len + 1);
	if (!copy) {
		return NULL;
	}

	memcpy(copy, text, len + 1);
	return copy;
}

static char *
read_response_frame(int fd)
{
	size_t cap = FRAME_CHUNK_SIZE;
	size_t len = 0;
	char *buffer;

	buffer = malloc(cap);
	if (!buffer) {
		return NULL;
	}

	for (;;) {
		const char *delim;
		ssize_t bytes_read;

		if (cap - len < FRAME_CHUNK_SIZE) {
			char *grown = realloc(buffer, cap * 2);
			if (!grown) {
				free(buffer);
				return NULL;
			}
			buffer = grown;
			cap *= 2;
		}

		bytes_read = read(fd, buffer + len, cap - len - 1);
		if (bytes_read < 0 && errno == EINTR) {
			continue;
		}
		if (bytes_read < 0) {
			free(buffer);
			return NULL;
		}
		if (bytes_read == 0) {
			break;
		}

		len += (size_t)bytes_read;
		buffer[len] = '\0';
		delim = find_frame_delim(buffer);
		if (delim) {
			len = (size_t)(delim - buffer);
			buffer[len] = '\0';
			return buffer;
		}
	}

	if (!len) {
		free(buffer);
		return NULL;
	}

	buffer[len] = '\0';
	return buffer;
}

static bool
resolve_socket_path(char *dest, size_t dest_size)
{
	char state_dir[PATH_MAX_LEN];
	int wrote;

	if (!resolve_state_dir(state_dir, sizeof(state_dir))) {
		return false;
	}

	wrote = snprintf(dest, dest_size, "%s/runtime.sock", state_dir);
	return wrote >= 0 && (size_t)wrote < dest_size;
}

static bool
resolve_state_dir(char *dest, size_t dest_size)
{
	const char *state_dir;
	const char *cache_home;
	const char *home;
	char cache_fallback[PATH_MAX_LEN];
	int wrote;

	state_dir = getenv("NSCDE_STATE_DIR");
	if (state_dir && state_dir[0]) {
		return copy_text(dest, dest_size, state_dir);
	}

	cache_home = getenv("XDG_CACHE_HOME");
	if (!cache_home || !cache_home[0]) {
		home = getenv("HOME");
		if (!home || !home[0]) {
			return false;
		}
		wrote = snprintf(cache_fallback, sizeof(cache_fallback),
			"%s/.cache", home);
		if (wrote < 0 || (size_t)wrote >= sizeof(cache_fallback)) {
			return false;
		}
		cache_home = cache_fallback;
	}

	wrote = snprintf(dest, dest_size, "%s/nscde-stage1", cache_home);
	return wrote >= 0 && (size_t)wrote < dest_size;
}

static bool
set_nonblock(int fd)
{
	int flags = fcntl(fd, F_GETFL);

	if (flags < 0) {
		return false;
	}

	return fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0;
}

static bool
send_frame_request(int fd, const char *request_text)
{
	size_t remaining;
	const char *cursor;

	if (fd < 0 || !request_text) {
		return false;
	}

	remaining = strlen(request_text);
	cursor = request_text;
	while (remaining > 0) {
		ssize_t written = write(fd, cursor, remaining);
		if (written < 0 && errno == EINTR) {
			continue;
		}
		if (written <= 0) {
			return false;
		}
		cursor += written;
		remaining -= (size_t)written;
	}

	return true;
}
