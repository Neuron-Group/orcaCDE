/*
 * NsCDE backdrop daemon for the labwc backend.
 *
 * Consumes runtime-owned backdrop state and manages swaybg processes while
 * preserving the existing backdrops.env compatibility mirror as output only.
 */

#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#include <wayland-client.h>

#include "../nscde_wayland_common/runtime-client.h"

#define MAX_OUTPUTS 16
#define PATH_MAX_LEN 1024
#define VALUE_MAX_LEN 512
struct swaybg_process {
	char output_name[VALUE_MAX_LEN];
	bool use_output_arg;
	pid_t pid;
};

struct output_probe_output {
	struct wl_output *output;
	uint32_t global_id;
	bool have_name;
	char name[VALUE_MAX_LEN];
};

struct output_probe {
	struct wl_display *display;
	struct wl_registry *registry;
	struct output_probe_output outputs[MAX_OUTPUTS];
	size_t output_count;
};

static struct {
	char state_dir[PATH_MAX_LEN];
	char backdrops_env_path[PATH_MAX_LEN];
	char current_workspace[VALUE_MAX_LEN];
	char current_desk[VALUE_MAX_LEN];
	char current_image_name[VALUE_MAX_LEN];
	char current_image[PATH_MAX_LEN];
	char current_mode[VALUE_MAX_LEN];
	char current_color[VALUE_MAX_LEN];
	struct swaybg_process processes[MAX_OUTPUTS];
	size_t process_count;
	bool running;
	bool once_mode;
	bool runtime_active;
	struct nscde_runtime_subscription runtime_subscription;
} backdropd = {
	.running = true,
};

static void apply_backdrop_contents(const char *contents);
static void apply_backdrop_environment(void);
static void apply_backdrop_values(const char *workspace, const char *desk,
	const char *image_name, const char *image, const char *mode,
	const char *color);
static bool backdrop_contents_changed(const char *contents);
static void clear_output_targets(void);
static bool environment_has_backdrop_values(void);
static bool parse_env_value(const char *contents, const char *key, char *dest,
	size_t dest_size);
static bool query_runtime_backdrops(char **out_contents);
static bool query_runtime_backdrops_with_retry(char **out_contents);
static bool setup_runtime_subscription(void);
static void teardown_runtime_subscription(void);
static void handle_runtime_frame(const struct nscde_runtime_frame *frame,
	void *userdata);
static void handle_runtime_subscription(void);
static void handle_runtime_fd_ready(int fd, short revents, void *userdata);
static void handle_runtime_fd_error(int fd, short revents, void *userdata);
static void refresh_output_targets(void);
static void restart_backdrop_processes(void);
static void setup_signal_handlers(void);
static void set_default_output(void);
static void spawn_swaybg_processes(void);
static void stop_swaybg_processes(void);
static void write_backdrops_env(void);

static const char *
env_or_default(const char *name, const char *fallback)
{
	const char *value = getenv(name);
	return value && value[0] ? value : fallback;
}

static void
copy_text(char *dest, size_t dest_size, const char *src)
{
	if (!dest || !dest_size) {
		return;
	}
	if (!src) {
		dest[0] = '\0';
		return;
	}
	snprintf(dest, dest_size, "%s", src);
}

static void
build_paths(void)
{
	const char *state_dir = getenv("NSCDE_STATE_DIR");
	const char *cache_home = getenv("XDG_CACHE_HOME");
	const char *home = env_or_default("HOME", "/tmp");

	if (state_dir && state_dir[0]) {
		copy_text(backdropd.state_dir, sizeof(backdropd.state_dir), state_dir);
	} else if (!cache_home || !cache_home[0]) {
		snprintf(backdropd.state_dir, sizeof(backdropd.state_dir),
			"%s/.cache/nscde-stage1", home);
	} else {
		snprintf(backdropd.state_dir, sizeof(backdropd.state_dir),
			"%s/nscde-stage1", cache_home);
	}

	snprintf(backdropd.backdrops_env_path, sizeof(backdropd.backdrops_env_path),
		"%s/backdrops.env", backdropd.state_dir);
}

static void
ensure_directories(void)
{
	mkdir(backdropd.state_dir, 0755);
}

static void
clear_output_targets(void)
{
	size_t i;

	for (i = 0; i < MAX_OUTPUTS; i++) {
		backdropd.processes[i].output_name[0] = '\0';
		backdropd.processes[i].use_output_arg = false;
		backdropd.processes[i].pid = -1;
	}
	backdropd.process_count = 0;
}

static void
set_default_output(void)
{
	clear_output_targets();
	copy_text(backdropd.processes[0].output_name,
		sizeof(backdropd.processes[0].output_name), "default");
	backdropd.processes[0].use_output_arg = false;
	backdropd.process_count = 1;
}

static void
write_backdrops_env(void)
{
	/*
	 * backdrops.env remains a compatibility mirror for legacy consumers.
	 * The runtime backdrops topic is the only long-lived policy input.
	 */
	bool has_background = backdropd.current_image[0] || backdropd.current_color[0];
	FILE *handle;
	size_t i;
	char tmp_path[PATH_MAX_LEN + 4];

	snprintf(tmp_path, sizeof(tmp_path), "%s.tmp", backdropd.backdrops_env_path);
	handle = fopen(tmp_path, "w");
	if (!handle) {
		fprintf(stderr, "nscde_backdropd: cannot write %s: %s\n",
			tmp_path, strerror(errno));
		return;
	}

	fprintf(handle, "NSCDE_BACKDROP_WORKSPACE=%s\n", backdropd.current_workspace);
	fprintf(handle, "NSCDE_BACKDROP_DESK=%s\n", backdropd.current_desk);
	fprintf(handle, "NSCDE_BACKDROP_MODE=%s\n", backdropd.current_mode);
	fprintf(handle, "NSCDE_BACKDROP_IMAGE_NAME=%s\n",
		backdropd.current_image_name);
	fprintf(handle, "NSCDE_BACKDROP_IMAGE=%s\n", backdropd.current_image);
	fprintf(handle, "NSCDE_BACKDROP_COLOR=%s\n", backdropd.current_color);
	fprintf(handle, "NSCDE_BACKDROP_OUTPUT_COUNT=%zu\n",
		has_background ? backdropd.process_count : 0U);
	if (has_background) {
		for (i = 0; i < backdropd.process_count; i++) {
			fprintf(handle, "NSCDE_BACKDROP_OUTPUT_%s_IMAGE=%s\n",
				backdropd.processes[i].output_name,
				backdropd.current_image);
			fprintf(handle, "NSCDE_BACKDROP_OUTPUT_%s_MODE=%s\n",
				backdropd.processes[i].output_name,
				backdropd.current_mode);
			fprintf(handle, "NSCDE_BACKDROP_OUTPUT_%s_COLOR=%s\n",
				backdropd.processes[i].output_name,
				backdropd.current_color);
		}
	}
	fclose(handle);

	if (rename(tmp_path, backdropd.backdrops_env_path) != 0) {
		fprintf(stderr, "nscde_backdropd: cannot rename %s: %s\n",
			tmp_path, strerror(errno));
	}
}

static void
stop_swaybg_processes(void)
{
	size_t i;

	for (i = 0; i < backdropd.process_count; i++) {
		if (backdropd.processes[i].pid > 0) {
			kill(backdropd.processes[i].pid, SIGTERM);
			waitpid(backdropd.processes[i].pid, NULL, 0);
			backdropd.processes[i].pid = -1;
		}
	}
}

static const char *
resolve_swaybg_mode(const char *mode)
{
	if (!mode || !mode[0]) {
		return "fill";
	}
	if (strcmp(mode, "tiled") == 0) {
		return "tile";
	}
	if (strcmp(mode, "aspect") == 0) {
		return "fit";
	}
	if (strcmp(mode, "photo") == 0) {
		return "fill";
	}
	return mode;
}

static void
destroy_output_probe(struct output_probe *probe)
{
	size_t i;

	if (!probe) {
		return;
	}

	for (i = 0; i < probe->output_count; i++) {
		if (probe->outputs[i].output) {
			wl_output_destroy(probe->outputs[i].output);
			probe->outputs[i].output = NULL;
		}
	}
	if (probe->registry) {
		wl_registry_destroy(probe->registry);
		probe->registry = NULL;
	}
	if (probe->display) {
		wl_display_disconnect(probe->display);
		probe->display = NULL;
	}
}

static void
handle_output_geometry(void *data, struct wl_output *output,
	int32_t x, int32_t y, int32_t physical_width, int32_t physical_height,
	int32_t subpixel, const char *make, const char *model, int32_t transform)
{
	(void)data;
	(void)output;
	(void)x;
	(void)y;
	(void)physical_width;
	(void)physical_height;
	(void)subpixel;
	(void)make;
	(void)model;
	(void)transform;
}

static void
handle_output_mode(void *data, struct wl_output *output,
	uint32_t flags, int32_t width, int32_t height, int32_t refresh)
{
	(void)data;
	(void)output;
	(void)flags;
	(void)width;
	(void)height;
	(void)refresh;
}

static void
handle_output_done(void *data, struct wl_output *output)
{
	(void)data;
	(void)output;
}

static void
handle_output_scale(void *data, struct wl_output *output, int32_t factor)
{
	(void)data;
	(void)output;
	(void)factor;
}

static void
handle_output_name(void *data, struct wl_output *output, const char *name)
{
	struct output_probe_output *probe_output = data;

	(void)output;

	if (!probe_output || !name || !name[0]) {
		return;
	}

	copy_text(probe_output->name, sizeof(probe_output->name), name);
	probe_output->have_name = true;
}

static void
handle_output_description(void *data, struct wl_output *output,
	const char *description)
{
	(void)data;
	(void)output;
	(void)description;
}

static const struct wl_output_listener output_listener = {
	.geometry = handle_output_geometry,
	.mode = handle_output_mode,
	.done = handle_output_done,
	.scale = handle_output_scale,
	.name = handle_output_name,
	.description = handle_output_description,
};

static void
handle_registry_global(void *data, struct wl_registry *registry,
	uint32_t name, const char *interface, uint32_t version)
{
	struct output_probe *probe = data;
	struct output_probe_output *probe_output;
	uint32_t bind_version;

	if (!probe || !registry || !interface || probe->output_count >= MAX_OUTPUTS) {
		return;
	}
	if (strcmp(interface, wl_output_interface.name) != 0) {
		return;
	}

	bind_version = version < 4 ? version : 4;
	if (bind_version < 1) {
		return;
	}

	probe_output = &probe->outputs[probe->output_count];
	memset(probe_output, 0, sizeof(*probe_output));
	probe_output->output = wl_registry_bind(registry, name,
		&wl_output_interface, bind_version);
	probe_output->global_id = name;
	snprintf(probe_output->name, sizeof(probe_output->name),
		"output-%u", name);
	if (probe_output->output) {
		wl_output_add_listener(probe_output->output, &output_listener,
			probe_output);
		probe->output_count++;
	}
}

static void
handle_registry_global_remove(void *data, struct wl_registry *registry,
	uint32_t name)
{
	(void)data;
	(void)registry;
	(void)name;
}

static const struct wl_registry_listener registry_listener = {
	.global = handle_registry_global,
	.global_remove = handle_registry_global_remove,
};

static void
refresh_output_targets(void)
{
	struct output_probe probe = {0};
	size_t named_count = 0;
	size_t i;

	clear_output_targets();

	probe.display = wl_display_connect(NULL);
	if (!probe.display) {
		set_default_output();
		return;
	}

	probe.registry = wl_display_get_registry(probe.display);
	if (!probe.registry) {
		destroy_output_probe(&probe);
		set_default_output();
		return;
	}

	wl_registry_add_listener(probe.registry, &registry_listener, &probe);
	if (wl_display_roundtrip(probe.display) < 0
			|| wl_display_roundtrip(probe.display) < 0) {
		destroy_output_probe(&probe);
		set_default_output();
		return;
	}

	for (i = 0; i < probe.output_count && named_count < MAX_OUTPUTS; i++) {
		if (!probe.outputs[i].have_name || !probe.outputs[i].name[0]) {
			continue;
		}
		copy_text(backdropd.processes[named_count].output_name,
			sizeof(backdropd.processes[named_count].output_name),
			probe.outputs[i].name);
		backdropd.processes[named_count].use_output_arg = true;
		backdropd.processes[named_count].pid = -1;
		named_count++;
	}

	destroy_output_probe(&probe);

	if (!named_count) {
		set_default_output();
		return;
	}

	backdropd.process_count = named_count;
}

static void
spawn_swaybg_processes(void)
{
	const char *swaybg_bin = env_or_default("SWAYBG_BIN", "swaybg");
	const char *swaybg_mode = resolve_swaybg_mode(backdropd.current_mode);
	bool has_image = backdropd.current_image[0];
	bool has_color = backdropd.current_color[0];
	size_t i;

	if (!has_image && !has_color) {
		return;
	}

	for (i = 0; i < backdropd.process_count; i++) {
		pid_t pid = fork();

		if (pid < 0) {
			fprintf(stderr, "nscde_backdropd: fork failed: %s\n",
				strerror(errno));
			continue;
		}
		if (pid == 0) {
			if (has_image) {
				if (backdropd.processes[i].use_output_arg) {
					execlp(swaybg_bin, swaybg_bin,
						"-o", backdropd.processes[i].output_name,
						"-i", backdropd.current_image,
						"-m", swaybg_mode,
						(char *)NULL);
				} else {
					execlp(swaybg_bin, swaybg_bin,
						"-i", backdropd.current_image,
						"-m", swaybg_mode,
						(char *)NULL);
				}
			} else if (backdropd.processes[i].use_output_arg) {
				execlp(swaybg_bin, swaybg_bin,
					"-o", backdropd.processes[i].output_name,
					"-c", backdropd.current_color,
					(char *)NULL);
			} else {
				execlp(swaybg_bin, swaybg_bin,
					"-c", backdropd.current_color,
					(char *)NULL);
			}

			fprintf(stderr, "nscde_backdropd: exec %s failed: %s\n",
				swaybg_bin, strerror(errno));
			_exit(127);
		}

		backdropd.processes[i].pid = pid;
	}
}

static bool
parse_env_value(const char *contents, const char *key, char *dest,
	size_t dest_size)
{
	const char *cursor = contents;
	size_t key_len = strlen(key);

	while (cursor && *cursor) {
		const char *line_end = strchr(cursor, '\n');
		size_t line_len = line_end ? (size_t)(line_end - cursor)
			: strlen(cursor);
		if (line_len > key_len + 1
				&& !strncmp(cursor, key, key_len)
				&& cursor[key_len] == '=') {
			size_t value_len = line_len - key_len - 1;
			if (value_len >= dest_size) {
				value_len = dest_size - 1;
			}
			memcpy(dest, cursor + key_len + 1, value_len);
			dest[value_len] = '\0';
			return true;
		}
		cursor = line_end ? line_end + 1 : NULL;
	}

	dest[0] = '\0';
	return false;
}

static void
restart_backdrop_processes(void)
{
	stop_swaybg_processes();
	if (backdropd.current_image[0] || backdropd.current_color[0]) {
		refresh_output_targets();
	} else {
		clear_output_targets();
	}
	write_backdrops_env();
	spawn_swaybg_processes();
}

static void
apply_backdrop_values(const char *workspace, const char *desk,
	const char *image_name, const char *image, const char *mode,
	const char *color)
{
	copy_text(backdropd.current_workspace,
		sizeof(backdropd.current_workspace), workspace);
	copy_text(backdropd.current_desk,
		sizeof(backdropd.current_desk), desk);
	copy_text(backdropd.current_image_name,
		sizeof(backdropd.current_image_name), image_name);
	copy_text(backdropd.current_image,
		sizeof(backdropd.current_image), image);
	copy_text(backdropd.current_mode,
		sizeof(backdropd.current_mode), mode);
	copy_text(backdropd.current_color,
		sizeof(backdropd.current_color),
		color && color[0] ? color : "#506070");
	restart_backdrop_processes();
}

static void
apply_backdrop_environment(void)
{
	const char *image = getenv("NSCDE_BACKDROP_IMAGE");
	const char *mode = getenv("NSCDE_BACKDROP_MODE");
	const char *color = getenv("NSCDE_BACKDROP_COLOR");

	apply_backdrop_values("", "", "", image ? image : "",
		mode ? mode : "", color ? color : "");
}

static void
apply_backdrop_contents(const char *contents)
{
	char workspace[VALUE_MAX_LEN];
	char desk[VALUE_MAX_LEN];
	char image_name[VALUE_MAX_LEN];
	char image[PATH_MAX_LEN];
	char mode[VALUE_MAX_LEN];
	char color[VALUE_MAX_LEN];

	if (!contents) {
		return;
	}

	parse_env_value(contents, "NSCDE_BACKDROP_WORKSPACE",
		workspace, sizeof(workspace));
	parse_env_value(contents, "NSCDE_BACKDROP_DESK",
		desk, sizeof(desk));
	parse_env_value(contents, "NSCDE_BACKDROP_IMAGE_NAME",
		image_name, sizeof(image_name));
	parse_env_value(contents, "NSCDE_BACKDROP_IMAGE",
		image, sizeof(image));
	parse_env_value(contents, "NSCDE_BACKDROP_MODE",
		mode, sizeof(mode));
	parse_env_value(contents, "NSCDE_BACKDROP_COLOR",
		color, sizeof(color));

	apply_backdrop_values(workspace, desk, image_name, image, mode, color);
}

static bool
backdrop_contents_changed(const char *contents)
{
	char workspace[VALUE_MAX_LEN];
	char desk[VALUE_MAX_LEN];
	char image_name[VALUE_MAX_LEN];
	char image[PATH_MAX_LEN];
	char mode[VALUE_MAX_LEN];
	char color[VALUE_MAX_LEN];

	if (!contents) {
		return false;
	}

	parse_env_value(contents, "NSCDE_BACKDROP_WORKSPACE",
		workspace, sizeof(workspace));
	parse_env_value(contents, "NSCDE_BACKDROP_DESK",
		desk, sizeof(desk));
	parse_env_value(contents, "NSCDE_BACKDROP_IMAGE_NAME",
		image_name, sizeof(image_name));
	parse_env_value(contents, "NSCDE_BACKDROP_IMAGE",
		image, sizeof(image));
	parse_env_value(contents, "NSCDE_BACKDROP_MODE",
		mode, sizeof(mode));
	parse_env_value(contents, "NSCDE_BACKDROP_COLOR",
		color, sizeof(color));

	return strcmp(workspace, backdropd.current_workspace) != 0
		|| strcmp(desk, backdropd.current_desk) != 0
		|| strcmp(image_name, backdropd.current_image_name) != 0
		|| strcmp(image, backdropd.current_image) != 0
		|| strcmp(mode, backdropd.current_mode) != 0
		|| strcmp(color[0] ? color : "#506070", backdropd.current_color) != 0;
}

static void
handle_signal(int signo)
{
	(void)signo;
	backdropd.running = false;
}

static void
setup_signal_handlers(void)
{
	struct sigaction action;

	memset(&action, 0, sizeof(action));
	action.sa_handler = handle_signal;
	sigemptyset(&action.sa_mask);
	action.sa_flags = 0;

	sigaction(SIGINT, &action, NULL);
	sigaction(SIGTERM, &action, NULL);
}

static bool
environment_has_backdrop_values(void)
{
	const char *image = getenv("NSCDE_BACKDROP_IMAGE");
	const char *mode = getenv("NSCDE_BACKDROP_MODE");
	const char *color = getenv("NSCDE_BACKDROP_COLOR");

	return (image && image[0]) || (mode && mode[0]) || (color && color[0]);
}

static bool
query_runtime_backdrops(char **out_contents)
{
	return nscde_runtime_query_topic("backdrops", out_contents);
}

static bool
query_runtime_backdrops_with_retry(char **out_contents)
{
	struct timespec retry_delay = {
		.tv_sec = 0,
		.tv_nsec = 100 * 1000 * 1000,
	};
	int attempt;

	for (attempt = 0; attempt < 50; attempt++) {
		if (query_runtime_backdrops(out_contents)) {
			return true;
		}
		nanosleep(&retry_delay, NULL);
	}

	return false;
}

static bool
setup_runtime_subscription(void)
{
	if (backdropd.runtime_active) {
		return true;
	}

	if (!nscde_runtime_subscribe_topics("backdrops",
		&backdropd.runtime_subscription)) {
		return false;
	}

	backdropd.runtime_active = true;
	return true;
}

static void
teardown_runtime_subscription(void)
{
	nscde_runtime_subscription_close(&backdropd.runtime_subscription);
	backdropd.runtime_active = false;
}

static void
handle_runtime_frame(const struct nscde_runtime_frame *frame, void *userdata)
{
	(void)userdata;

	if (!frame || (frame->type != NSCDE_RUNTIME_FRAME_STATE &&
			frame->type != NSCDE_RUNTIME_FRAME_SNAPSHOT &&
			frame->type != NSCDE_RUNTIME_FRAME_EVENT) ||
			!frame->contents) {
		return;
	}

	if (strcmp(frame->topic, "backdrops") == 0
			&& backdrop_contents_changed(frame->contents)) {
		apply_backdrop_contents(frame->contents);
	}
}

static void
handle_runtime_subscription(void)
{
	char error_message[NSCDE_RUNTIME_FIELD_LEN] = {0};
	enum nscde_runtime_read_result result =
		nscde_runtime_subscription_drain(&backdropd.runtime_subscription,
			handle_runtime_frame, NULL, error_message,
			sizeof(error_message));

	if (result == NSCDE_RUNTIME_READ_ERROR && error_message[0]) {
		fprintf(stderr,
			"nscde_backdropd: runtime subscribe error: %s\n",
			error_message);
	}
	if (result == NSCDE_RUNTIME_READ_CLOSED ||
			result == NSCDE_RUNTIME_READ_ERROR) {
		teardown_runtime_subscription();
	}
}

static void
handle_runtime_fd_ready(int fd, short revents, void *userdata)
{
	(void)fd;
	(void)revents;
	(void)userdata;
	handle_runtime_subscription();
}

static void
handle_runtime_fd_error(int fd, short revents, void *userdata)
{
	(void)fd;
	(void)revents;
	(void)userdata;
	fprintf(stderr,
		"nscde_backdropd: runtime subscription disconnected\n");
	backdropd.running = false;
}

int
main(int argc, char **argv)
{
	char *initial_contents = NULL;
	nscde_fd_reactor reactor;

	if (argc > 2 || (argc == 2 && strcmp(argv[1], "--once") != 0)) {
		fprintf(stderr, "Usage: nscde_backdropd [--once]\n");
		return 2;
	}
	if (argc == 2) {
		backdropd.once_mode = true;
	}

	setup_signal_handlers();

	build_paths();
	ensure_directories();
	clear_output_targets();
	nscde_fd_reactor_init(&reactor);
	nscde_runtime_subscription_init(&backdropd.runtime_subscription);

	if (backdropd.once_mode) {
		if (environment_has_backdrop_values()) {
			apply_backdrop_environment();
			return 0;
		}
		if (!query_runtime_backdrops_with_retry(&initial_contents)) {
			fprintf(stderr, "nscde_backdropd: unable to query runtime backdrops topic\n");
			return 1;
		}
		apply_backdrop_contents(initial_contents);
		free(initial_contents);
		return 0;
	}

	if (query_runtime_backdrops_with_retry(&initial_contents)) {
		apply_backdrop_contents(initial_contents);
		free(initial_contents);
	} else {
		fprintf(stderr,
			"nscde_backdropd: runtime backdrops topic unavailable at startup\n");
		return 1;
	}

	while (backdropd.running) {
		if (!backdropd.runtime_active && !setup_runtime_subscription()) {
			fprintf(stderr,
				"nscde_backdropd: unable to subscribe to runtime backdrops topic\n");
			return 1;
		}

		nscde_fd_reactor_remove(&reactor, backdropd.runtime_subscription.fd);
		if (!nscde_fd_reactor_add(&reactor,
			backdropd.runtime_subscription.fd, POLLIN,
			handle_runtime_fd_ready, handle_runtime_fd_error, NULL)) {
			fprintf(stderr,
				"nscde_backdropd: unable to register runtime watcher\n");
			break;
		}
		if (!nscde_fd_reactor_run_once(&reactor, -1) && errno != EINTR) {
			fprintf(stderr, "nscde_backdropd: event wait failed: %s\n",
				strerror(errno));
			break;
		}
	}

	teardown_runtime_subscription();
	stop_swaybg_processes();
	return 0;
}
