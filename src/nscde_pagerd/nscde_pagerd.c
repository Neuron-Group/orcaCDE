/*
 * NsCDE workspace pager daemon for labwc backend.
 *
 * This is a Wayland client that uses ext-workspace-v1 protocol to track
 * workspace state and provide workspace switching. It now publishes live
 * snapshots through the runtime producer stream and waits on Wayland/FIFO
 * readiness through the shared fd reactor.
 *
 * Writes state to pager.env for shell UI consumption.
 * Reads workspace switch requests from the session command FIFO.
 *
 * This file is a part of NsCDE - Not so Common Desktop Environment
 * Author: Hegel3DReloaded
 * Licence: GPLv3
 */

#define _GNU_SOURCE
#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>
#include <wayland-client.h>

#include "../nscde_wayland_common/runtime-client.h"

/* Forward declarations for protocol-generated types */
struct ext_workspace_manager_v1;
struct ext_workspace_group_handle_v1;
struct ext_workspace_handle_v1;

/* Include generated protocol headers */
#include "ext-workspace-v1-client-protocol.h"

#define MAX_WORKSPACES 32
#define MAX_NAME_LEN 256
#define STATE_LINE_LEN 512
#define PATH_MAX_LEN 1024

/* Workspace state */
struct workspace {
	struct ext_workspace_handle_v1 *handle;
	char name[MAX_NAME_LEN];
	bool active;
	bool valid;
};

/* Pager state */
static struct {
	struct wl_display *display;
	struct wl_registry *registry;
	struct ext_workspace_manager_v1 *manager;
	struct nscde_runtime_publisher runtime_publisher;

	struct workspace workspaces[MAX_WORKSPACES];
	int workspace_count;
	char current_workspace[MAX_NAME_LEN];

	char state_dir[PATH_MAX_LEN];
	char pager_fifo_path[PATH_MAX_LEN];

	/* Session FIFO for receiving commands */
	int session_fifo_fd;

	/* Running state */
	bool running;
	bool dirty;
	bool wayland_read_armed;
	bool wayland_events_read;
} pager = {
	.workspace_count = 0,
	.current_workspace = "",
	.session_fifo_fd = -1,
	.runtime_publisher = {.fd = -1},
	.running = true,
	.dirty = true,
};

/* Find workspace by handle */
static struct workspace *
find_workspace_by_handle(struct ext_workspace_handle_v1 *handle)
{
	for (int i = 0; i < pager.workspace_count; i++) {
		if (pager.workspaces[i].handle == handle &&
		    pager.workspaces[i].valid) {
			return &pager.workspaces[i];
		}
	}
	return NULL;
}

/* Find workspace by name */
static struct workspace *
find_workspace_by_name(const char *name)
{
	for (int i = 0; i < pager.workspace_count; i++) {
		if (pager.workspaces[i].valid &&
		    strcmp(pager.workspaces[i].name, name) == 0) {
			return &pager.workspaces[i];
		}
	}
	return NULL;
}

static void
process_fifo_commands(void);

/* Add a new workspace */
static struct workspace *
add_workspace(struct ext_workspace_handle_v1 *handle)
{
	if (pager.workspace_count >= MAX_WORKSPACES) {
		fprintf(stderr, "nscde_pagerd: max workspaces reached\n");
		return NULL;
	}

	struct workspace *ws = &pager.workspaces[pager.workspace_count];
	ws->handle = handle;
	ws->name[0] = '\0';
	ws->active = false;
	ws->valid = true;
	pager.workspace_count++;
	return ws;
}

/* Remove a workspace */
static void
remove_workspace(struct ext_workspace_handle_v1 *handle)
{
	for (int i = 0; i < pager.workspace_count; i++) {
		if (pager.workspaces[i].handle == handle) {
			pager.workspaces[i].valid = false;
			/* Shift remaining workspaces */
			for (int j = i; j < pager.workspace_count - 1; j++) {
				pager.workspaces[j] = pager.workspaces[j + 1];
			}
			pager.workspace_count--;
			pager.dirty = true;
			return;
		}
	}
}

static void
write_workspace_names(FILE *stream, const char *key)
{
	fprintf(stream, "%s=", key);
	for (int i = 0; i < pager.workspace_count; i++) {
		if (pager.workspaces[i].valid) {
			if (i > 0) {
				fprintf(stream, ",");
			}
			fprintf(stream, "%s", pager.workspaces[i].name);
		}
	}
	fprintf(stream, "\n");
}

static int
current_workspace_index(void)
{
	int current_index = 0;

	for (int i = 0; i < pager.workspace_count; i++) {
		if (pager.workspaces[i].valid &&
		    strcmp(pager.workspaces[i].name, pager.current_workspace) == 0) {
			current_index = i + 1;
			break;
		}
	}
	return current_index;
}

static void
write_pager_state(FILE *stream)
{
	write_workspace_names(stream, "NSCDE_PAGER_WORKSPACES");
	fprintf(stream, "NSCDE_PAGER_CURRENT=%s\n", pager.current_workspace);
	fprintf(stream, "NSCDE_PAGER_COUNT=%d\n", pager.workspace_count);
	fprintf(stream, "NSCDE_PAGER_INDEX=%d\n", current_workspace_index());
	fprintf(stream, "NSCDE_PAGER_COMMAND_FIFO=%s\n", pager.pager_fifo_path);
}

static void
write_workspaces_state(FILE *stream)
{
	write_workspace_names(stream, "NSCDE_WORKSPACES");
	fprintf(stream, "NSCDE_WORKSPACE_COUNT=%d\n", pager.workspace_count);
	fprintf(stream, "NSCDE_CURRENT_WORKSPACE=%s\n", pager.current_workspace);
	fprintf(stream, "NSCDE_PAGER_COMMAND_FIFO=%s\n", pager.pager_fifo_path);
}

typedef void (*state_writer_fn)(FILE *stream);

static bool
publish_runtime_topic(const char *topic, state_writer_fn writer)
{
	FILE *stream;
	char *contents = NULL;
	size_t contents_size = 0;
	bool success;

	if (!topic || !writer) {
		return false;
	}

	stream = open_memstream(&contents, &contents_size);
	if (!stream) {
		fprintf(stderr,
		    "nscde_pagerd: cannot allocate publish buffer for %s: %s\n",
		    topic, strerror(errno));
		return false;
	}

	writer(stream);
	fclose(stream);

	if (pager.runtime_publisher.fd >= 0) {
		success =
			nscde_runtime_publisher_send(&pager.runtime_publisher, topic,
				contents ? contents : "");
	} else {
		success = nscde_runtime_publish_topic(topic, contents ? contents : "");
	}
	if (!success) {
		fprintf(stderr,
		    "nscde_pagerd: failed to publish runtime %s state\n",
		    topic);
	}
	free(contents);
	return success;
}

static void
update_state(void)
{
	if (pager.runtime_publisher.fd < 0) {
		nscde_runtime_publisher_open("pagerd", "workspaces,pager",
			&pager.runtime_publisher);
	}
	publish_runtime_topic("workspaces", write_workspaces_state);
	publish_runtime_topic("pager", write_pager_state);
	pager.dirty = false;
}

static bool
prepare_wayland_wait(void)
{
	while (wl_display_prepare_read(pager.display) != 0) {
		if (wl_display_dispatch_pending(pager.display) < 0) {
			fprintf(stderr, "nscde_pagerd: dispatch pending failed\n");
			pager.running = false;
			return false;
		}
	}

	if (wl_display_flush(pager.display) < 0) {
		fprintf(stderr, "nscde_pagerd: flush failed\n");
		pager.running = false;
		return false;
	}

	pager.wayland_read_armed = true;
	pager.wayland_events_read = false;
	return true;
}

static void
finish_wayland_wait(void)
{
	if (pager.wayland_read_armed && !pager.wayland_events_read) {
		wl_display_cancel_read(pager.display);
	}
	pager.wayland_read_armed = false;
}

static void
handle_wayland_ready(int fd, short revents, void *userdata)
{
	(void)fd;
	(void)revents;
	(void)userdata;

	if (wl_display_read_events(pager.display) < 0) {
		fprintf(stderr, "nscde_pagerd: read events failed\n");
		pager.running = false;
		return;
	}
	pager.wayland_events_read = true;
	pager.wayland_read_armed = false;

	if (wl_display_dispatch_pending(pager.display) < 0) {
		fprintf(stderr, "nscde_pagerd: dispatch failed\n");
		pager.running = false;
		return;
	}
	if (pager.dirty) {
		update_state();
	}
}

static void
handle_wayland_error(int fd, short revents, void *userdata)
{
	(void)fd;
	(void)revents;
	(void)userdata;
	fprintf(stderr, "nscde_pagerd: wayland fd error\n");
	pager.running = false;
}

static void
handle_fifo_ready(int fd, short revents, void *userdata)
{
	(void)fd;
	(void)revents;
	(void)userdata;
	process_fifo_commands();
}

static void
handle_fifo_error(int fd, short revents, void *userdata)
{
	(void)fd;
	(void)revents;
	(void)userdata;
	fprintf(stderr, "nscde_pagerd: session fifo watcher error\n");
	pager.running = false;
}

/* Protocol callbacks */
static void
workspace_handle_name(void *data, struct ext_workspace_handle_v1 *handle,
    const char *name)
{
	struct workspace *ws = data;
	if (ws && name) {
		strncpy(ws->name, name, MAX_NAME_LEN - 1);
		ws->name[MAX_NAME_LEN - 1] = '\0';
		pager.dirty = true;
	}
}

static void
workspace_handle_state(void *data, struct ext_workspace_handle_v1 *handle,
    uint32_t state)
{
	struct workspace *ws = data;
	if (!ws) {
		return;
	}

	ws->active = (state & EXT_WORKSPACE_HANDLE_V1_STATE_ACTIVE) != 0;
	if (ws->active && ws->name[0] != '\0') {
		strncpy(pager.current_workspace, ws->name,
		    MAX_NAME_LEN - 1);
		pager.current_workspace[MAX_NAME_LEN - 1] = '\0';
	}
	pager.dirty = true;
}

static void
workspace_handle_capabilities(void *data,
    struct ext_workspace_handle_v1 *handle, uint32_t capabilities)
{
	/* We only need to know about activate capability */
	(void)data;
	(void)handle;
	(void)capabilities;
}

static void
workspace_handle_removed(void *data, struct ext_workspace_handle_v1 *handle)
{
	struct workspace *ws = data;
	if (ws) {
		remove_workspace(handle);
	}
}

static void
workspace_handle_id(void *data, struct ext_workspace_handle_v1 *handle,
    const char *id)
{
	/* We don't use workspace IDs, but we need the callback */
	(void)data;
	(void)handle;
	(void)id;
}

static void
workspace_handle_coordinates(void *data,
    struct ext_workspace_handle_v1 *handle, struct wl_array *coordinates)
{
	/* We don't use coordinates, but we need the callback */
	(void)data;
	(void)handle;
	(void)coordinates;
}

static const struct ext_workspace_handle_v1_listener workspace_listener = {
	.id = workspace_handle_id,
	.name = workspace_handle_name,
	.coordinates = workspace_handle_coordinates,
	.state = workspace_handle_state,
	.capabilities = workspace_handle_capabilities,
	.removed = workspace_handle_removed,
};

static void
manager_handle_workspace(void *data,
    struct ext_workspace_manager_v1 *manager,
    struct ext_workspace_handle_v1 *handle)
{
	struct workspace *ws = add_workspace(handle);
	if (ws) {
		ext_workspace_handle_v1_add_listener(handle,
		    &workspace_listener, ws);
	}
}

static void
manager_handle_workspace_group(void *data,
    struct ext_workspace_manager_v1 *manager,
    struct ext_workspace_group_handle_v1 *group)
{
	/* We don't need to track groups, but we need the callback */
	(void)data;
	(void)manager;
	(void)group;
}

static void
manager_handle_done(void *data,
    struct ext_workspace_manager_v1 *manager)
{
	(void)data;
	(void)manager;

	if (pager.dirty) {
		update_state();
	}
}

static void
manager_handle_finished(void *data,
    struct ext_workspace_manager_v1 *manager)
{
	(void)data;
	(void)manager;

	pager.running = false;
}

static const struct ext_workspace_manager_v1_listener manager_listener = {
	.workspace = manager_handle_workspace,
	.workspace_group = manager_handle_workspace_group,
	.done = manager_handle_done,
	.finished = manager_handle_finished,
};

/* Registry callbacks */
static void
registry_global(void *data, struct wl_registry *registry, uint32_t name,
    const char *interface, uint32_t version)
{
	(void)data;

	if (strcmp(interface, ext_workspace_manager_v1_interface.name) == 0) {
		pager.manager = wl_registry_bind(registry, name,
		    &ext_workspace_manager_v1_interface, 1);
		ext_workspace_manager_v1_add_listener(pager.manager,
		    &manager_listener, NULL);
	}
}

static void
registry_global_remove(void *data, struct wl_registry *registry,
    uint32_t name)
{
	/* We don't need to handle global removal */
	(void)data;
	(void)registry;
	(void)name;
}

static const struct wl_registry_listener registry_listener = {
	.global = registry_global,
	.global_remove = registry_global_remove,
};

/* Handle workspace switch command from FIFO */
static void
handle_switch_workspace(const char *workspace_name)
{
	struct workspace *ws = find_workspace_by_name(workspace_name);
	if (ws && ws->handle) {
		ext_workspace_handle_v1_activate(ws->handle);
		/* Send commit to make the request atomic */
		if (pager.manager) {
			ext_workspace_manager_v1_commit(pager.manager);
		}
	} else {
		fprintf(stderr, "nscde_pagerd: workspace '%s' not found\n",
		    workspace_name);
	}
}

/* Process commands from session FIFO */
static void
process_fifo_commands(void)
{
	char buf[512];
	ssize_t n;

	/* Non-blocking read from FIFO */
	n = read(pager.session_fifo_fd, buf, sizeof(buf) - 1);
	if (n <= 0) {
		if (n < 0 && errno != EAGAIN && errno != EWOULDBLOCK) {
			fprintf(stderr, "nscde_pagerd: FIFO read error: %s\n",
			    strerror(errno));
		}
		return;
	}

	buf[n] = '\0';

	/* Process each line */
	char *line = buf;
	char *next_line;

	while (line && *line) {
		next_line = strchr(line, '\n');
		if (next_line) {
			*next_line = '\0';
			next_line++;
		}

		/* Parse command */
		if (strncmp(line, "switch_workspace:", 17) == 0) {
			handle_switch_workspace(line + 17);
		}

		line = next_line;
	}
}

/* Initialize state directory paths */
static void
init_paths(void)
{
	const char *state_dir = getenv("NSCDE_STATE_DIR");
	const char *xdg_cache = getenv("XDG_CACHE_HOME");
	char cache_dir[512];

	if (state_dir && state_dir[0]) {
		snprintf(pager.state_dir, sizeof(pager.state_dir), "%s",
		    state_dir);
		pager.state_dir[sizeof(pager.state_dir) - 1] = '\0';
	} else if (xdg_cache) {
		snprintf(cache_dir, sizeof(cache_dir), "%s", xdg_cache);
		snprintf(pager.state_dir, sizeof(pager.state_dir),
		    "%s/nscde-stage1", cache_dir);
	} else {
		const char *home = getenv("HOME");
		if (!home) {
			home = "/tmp";
		}
		snprintf(cache_dir, sizeof(cache_dir), "%s/.cache", home);
		snprintf(pager.state_dir, sizeof(pager.state_dir),
		    "%s/nscde-stage1", cache_dir);
	}

	snprintf(pager.pager_fifo_path, sizeof(pager.pager_fifo_path),
	    "%s/pagerd.fifo", pager.state_dir);
}

/* Ensure state directory exists */
static int
ensure_state_dir(void)
{
	struct stat st;

	if (stat(pager.state_dir, &st) == 0) {
		return 0;
	}

	if (mkdir(pager.state_dir, 0755) != 0) {
		fprintf(stderr, "nscde_pagerd: cannot create %s: %s\n",
		    pager.state_dir, strerror(errno));
		return -1;
	}

	return 0;
}

/* Ensure pager command FIFO exists */
static int
ensure_command_fifo(void)
{
	struct stat st;

	if (stat(pager.pager_fifo_path, &st) == 0) {
		if (S_ISFIFO(st.st_mode)) {
			return 0;
		}
		if (unlink(pager.pager_fifo_path) != 0) {
			fprintf(stderr, "nscde_pagerd: cannot remove %s: %s\n",
			    pager.pager_fifo_path, strerror(errno));
			return -1;
		}
	} else if (errno != ENOENT) {
		fprintf(stderr, "nscde_pagerd: cannot stat %s: %s\n",
		    pager.pager_fifo_path, strerror(errno));
		return -1;
	}

	if (mkfifo(pager.pager_fifo_path, 0600) != 0 && errno != EEXIST) {
		fprintf(stderr, "nscde_pagerd: cannot create FIFO %s: %s\n",
		    pager.pager_fifo_path, strerror(errno));
		return -1;
	}

	return 0;
}

/* Open session FIFO for reading (non-blocking) */
static int
open_session_fifo(void)
{
	int fd;

	if (ensure_command_fifo() != 0) {
		return -1;
	}

	/* Open FIFO in non-blocking mode */
	fd = open(pager.pager_fifo_path, O_RDONLY | O_NONBLOCK);
	if (fd < 0) {
		fprintf(stderr, "nscde_pagerd: cannot open FIFO %s: %s\n",
		    pager.pager_fifo_path, strerror(errno));
		return -1;
	}

	return fd;
}

/* Signal handler */
static volatile sig_atomic_t caught_signal = 0;

static void
signal_handler(int sig)
{
	caught_signal = sig;
}

/* Setup signal handlers */
static void
setup_signals(void)
{
	struct sigaction sa;

	memset(&sa, 0, sizeof(sa));
	sa.sa_handler = signal_handler;
	sigemptyset(&sa.sa_mask);
	sa.sa_flags = SA_RESTART;

	sigaction(SIGINT, &sa, NULL);
	sigaction(SIGTERM, &sa, NULL);
	sigaction(SIGHUP, &sa, NULL);
}

/* Print usage */
static void
usage(const char *prog)
{
	fprintf(stderr, "Usage: %s [options]\n", prog);
	fprintf(stderr, "Options:\n");
	fprintf(stderr, "  -h    Show this help\n");
	fprintf(stderr, "  -v    Show version\n");
}

int
main(int argc, char *argv[])
{
	int opt;
	nscde_fd_reactor reactor;

	/* Parse arguments */
	while ((opt = getopt(argc, argv, "hv")) != -1) {
		switch (opt) {
		case 'h':
			usage(argv[0]);
			return 0;
		case 'v':
			printf("nscde_pagerd (NsCDE) 1.0\n");
			return 0;
		default:
			usage(argv[0]);
			return 1;
		}
	}

	/* Initialize paths */
	init_paths();

	/* Ensure state directory exists */
	if (ensure_state_dir() != 0) {
		return 1;
	}

	/* Setup signal handlers */
	setup_signals();
	nscde_fd_reactor_init(&reactor);

	/* Connect to Wayland display */
	pager.display = wl_display_connect(NULL);
	if (!pager.display) {
		fprintf(stderr, "nscde_pagerd: cannot connect to Wayland display\n");
		return 1;
	}

	/* Get registry and bind to ext-workspace-manager */
	pager.registry = wl_display_get_registry(pager.display);
	if (!pager.registry) {
		fprintf(stderr, "nscde_pagerd: cannot get registry\n");
		wl_display_disconnect(pager.display);
		return 1;
	}

	wl_registry_add_listener(pager.registry, &registry_listener, NULL);

	/* Initial roundtrip to get globals */
	if (wl_display_roundtrip(pager.display) < 0) {
		fprintf(stderr, "nscde_pagerd: roundtrip failed\n");
		wl_display_disconnect(pager.display);
		return 1;
	}

	if (!pager.manager) {
		fprintf(stderr, "nscde_pagerd: ext-workspace-manager not available\n");
		wl_display_disconnect(pager.display);
		return 1;
	}

	/* Second roundtrip to get initial workspace state */
	if (wl_display_roundtrip(pager.display) < 0) {
		fprintf(stderr, "nscde_pagerd: roundtrip failed\n");
		wl_display_disconnect(pager.display);
		return 1;
	}

	/* Open session FIFO */
	pager.session_fifo_fd = open_session_fifo();

	if (!nscde_runtime_publisher_open("pagerd", "workspaces,pager",
		&pager.runtime_publisher)) {
		fprintf(stderr,
		    "nscde_pagerd: failed to open runtime producer stream at startup; will retry\n");
	}

	/* Write initial state */
	update_state();

	/* Main event loop */
	while (pager.running) {
		nscde_fd_reactor_init(&reactor);
		if (!nscde_fd_reactor_add(&reactor, wl_display_get_fd(pager.display),
			POLLIN, handle_wayland_ready, handle_wayland_error, NULL)) {
			fprintf(stderr, "nscde_pagerd: unable to register wayland watcher\n");
			break;
		}
		if (pager.session_fifo_fd >= 0 &&
			!nscde_fd_reactor_add(&reactor, pager.session_fifo_fd, POLLIN,
			handle_fifo_ready, handle_fifo_error, NULL)) {
			fprintf(stderr, "nscde_pagerd: unable to register fifo watcher\n");
			break;
		}
		if (!prepare_wayland_wait()) {
			break;
		}
		if (!nscde_fd_reactor_run_once(&reactor, -1)) {
			if (errno == EINTR) {
				if (caught_signal) {
					fprintf(stderr, "nscde_pagerd: caught signal %d\n",
					    caught_signal);
					pager.running = false;
				}
				finish_wayland_wait();
				continue;
			}
			fprintf(stderr, "nscde_pagerd: event wait error: %s\n",
			    strerror(errno));
			break;
		}
		finish_wayland_wait();

		/* Update state if dirty */
		if (pager.dirty) {
			update_state();
		}
	}

	/* Cleanup */
	if (pager.session_fifo_fd >= 0) {
		close(pager.session_fifo_fd);
	}

	if (pager.manager) {
		ext_workspace_manager_v1_destroy(pager.manager);
	}
	nscde_runtime_publisher_close(&pager.runtime_publisher);

	if (pager.registry) {
		wl_registry_destroy(pager.registry);
	}

	if (pager.display) {
		wl_display_disconnect(pager.display);
	}

	return 0;
}
