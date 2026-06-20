#include "nscde-pixel-icon.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static cairo_surface_t *load_cached_icon_surface(
	struct nscde_pixel_icon_context *ctx,
	const char *relpath, int *width, int *height);
static cairo_surface_t *load_xpm_like_surface(
	struct nscde_pixel_icon_context *ctx, const char *path);
static bool parse_xpm_color(const char *spec, uint32_t *argb);
static bool parse_xpm_color_entry(struct nscde_pixel_icon_context *ctx,
	char *entry, int cpp, uint32_t *argb);
static bool render_icon_surface_exact(cairo_t *cr, cairo_surface_t *surface,
	int sw, int sh, int x, int y, int w, int h);

void
nscde_pixel_icon_init(struct nscde_pixel_icon_context *ctx,
	const char *data_dir)
{
	memset(ctx, 0, sizeof(*ctx));
	nscde_pixel_icon_set_data_dir(ctx, data_dir);
}

void
nscde_pixel_icon_set_palette(struct nscde_pixel_icon_context *ctx,
	uint32_t bg_argb, uint32_t hi_argb, uint32_t sh_argb, uint32_t sel_argb)
{
	if (!ctx) {
		return;
	}
	ctx->bg_argb = bg_argb;
	ctx->hi_argb = hi_argb;
	ctx->sh_argb = sh_argb;
	ctx->sel_argb = sel_argb;
	for (int i = 0; i < NSCDE_PIXEL_ICON_CACHE_MAX; i++) {
		if (ctx->cache[i].surface) {
			cairo_surface_destroy(ctx->cache[i].surface);
			ctx->cache[i].surface = NULL;
			ctx->cache[i].path[0] = '\0';
		}
	}
}

void
nscde_pixel_icon_set_data_dir(struct nscde_pixel_icon_context *ctx,
	const char *data_dir)
{
	if (!ctx) {
		return;
	}
	if (!data_dir) {
		ctx->data_dir[0] = '\0';
		return;
	}
	strncpy(ctx->data_dir, data_dir, sizeof(ctx->data_dir) - 1);
	ctx->data_dir[sizeof(ctx->data_dir) - 1] = '\0';
}

void
nscde_pixel_icon_destroy(struct nscde_pixel_icon_context *ctx)
{
	if (!ctx) {
		return;
	}
	for (int i = 0; i < NSCDE_PIXEL_ICON_CACHE_MAX; i++) {
		if (ctx->cache[i].surface) {
			cairo_surface_destroy(ctx->cache[i].surface);
			ctx->cache[i].surface = NULL;
		}
	}
}

bool
nscde_pixel_icon_render_asset(struct nscde_pixel_icon_context *ctx,
	cairo_t *cr, const char *relpath, int x, int y, int w, int h)
{
	int sw;
	int sh;
	cairo_surface_t *surface;
	double scale_x;
	double scale_y;
	double scale;
	int dw;
	int dh;
	int dx;
	int dy;

	if (!ctx || !cr || !relpath) {
		return false;
	}

	surface = load_cached_icon_surface(ctx, relpath, &sw, &sh);
	if (!surface || sw <= 0 || sh <= 0) {
		return false;
	}

	scale_x = (double)w / (double)sw;
	scale_y = (double)h / (double)sh;
	scale = scale_x < scale_y ? scale_x : scale_y;
	dw = (int)(sw * scale + 0.5);
	dh = (int)(sh * scale + 0.5);
	dx = x + (w - dw) / 2;
	dy = y + (h - dh) / 2;

	return render_icon_surface_exact(cr, surface, sw, sh, dx, dy, dw, dh);
}

bool
nscde_pixel_icon_render_asset_centered(
	struct nscde_pixel_icon_context *ctx, cairo_t *cr,
	const char *relpath, int x, int y, int w, int h, bool shrink_only)
{
	int sw;
	int sh;
	int dw;
	int dh;
	double scale_x;
	double scale_y;
	double scale;

	if (!nscde_pixel_icon_get_asset_size(ctx, relpath, &sw, &sh)) {
		return false;
	}

	dw = sw;
	dh = sh;
	if (!shrink_only || dw > w || dh > h) {
		scale_x = (double)w / (double)dw;
		scale_y = (double)h / (double)dh;
		scale = scale_x < scale_y ? scale_x : scale_y;
		dw = (int)(dw * scale + 0.5);
		dh = (int)(dh * scale + 0.5);
		if (dw < 1) {
			dw = 1;
		}
		if (dh < 1) {
			dh = 1;
		}
	}

	return render_icon_surface_exact(cr, load_cached_icon_surface(ctx, relpath,
		&sw, &sh), sw, sh, x + (w - dw) / 2, y + (h - dh) / 2, dw, dh);
}

bool
nscde_pixel_icon_get_asset_size(struct nscde_pixel_icon_context *ctx,
	const char *relpath, int *width, int *height)
{
	int sw;
	int sh;
	cairo_surface_t *surface;

	if (!ctx || !relpath) {
		return false;
	}

	surface = load_cached_icon_surface(ctx, relpath, &sw, &sh);
	if (!surface || sw <= 0 || sh <= 0) {
		return false;
	}

	if (width) {
		*width = sw;
	}
	if (height) {
		*height = sh;
	}
	return true;
}

static cairo_surface_t *
load_cached_icon_surface(struct nscde_pixel_icon_context *ctx,
	const char *relpath, int *width, int *height)
{
	char fullpath[NSCDE_PIXEL_ICON_PATH_MAX * 2];
	int slot = -1;

	if (!relpath || !relpath[0] || !ctx->data_dir[0]) {
		return NULL;
	}

	snprintf(fullpath, sizeof(fullpath), "%s/%s", ctx->data_dir, relpath);
	fullpath[sizeof(fullpath) - 1] = '\0';

	for (int i = 0; i < NSCDE_PIXEL_ICON_CACHE_MAX; i++) {
		if (ctx->cache[i].surface &&
			strcmp(ctx->cache[i].path, fullpath) == 0) {
			if (width) {
				*width = ctx->cache[i].width;
			}
			if (height) {
				*height = ctx->cache[i].height;
			}
			return ctx->cache[i].surface;
		}
		if (slot < 0 && !ctx->cache[i].surface) {
			slot = i;
		}
	}

	if (access(fullpath, R_OK) != 0) {
		return NULL;
	}

	cairo_surface_t *surface = NULL;
	const char *ext = strrchr(fullpath, '.');
	if (ext && strcmp(ext, ".png") == 0) {
		surface = cairo_image_surface_create_from_png(fullpath);
		if (cairo_surface_status(surface) != CAIRO_STATUS_SUCCESS) {
			cairo_surface_destroy(surface);
			return NULL;
		}
	} else if (ext && (strcmp(ext, ".xpm") == 0 || strcmp(ext, ".pm") == 0)) {
		surface = load_xpm_like_surface(ctx, fullpath);
		if (!surface) {
			return NULL;
		}
	} else {
		return NULL;
	}

	if (slot < 0) {
		slot = 0;
		if (ctx->cache[slot].surface) {
			cairo_surface_destroy(ctx->cache[slot].surface);
		}
	}

	strncpy(ctx->cache[slot].path, fullpath,
		sizeof(ctx->cache[slot].path) - 1);
	ctx->cache[slot].path[sizeof(ctx->cache[slot].path) - 1] = '\0';
	ctx->cache[slot].surface = surface;
	ctx->cache[slot].width = cairo_image_surface_get_width(surface);
	ctx->cache[slot].height = cairo_image_surface_get_height(surface);

	if (width) {
		*width = ctx->cache[slot].width;
	}
	if (height) {
		*height = ctx->cache[slot].height;
	}
	return surface;
}

static bool
parse_xpm_color(const char *spec, uint32_t *argb)
{
	if (!spec || !argb) {
		return false;
	}
	if (strcmp(spec, "none") == 0) {
		*argb = 0x00000000;
		return true;
	}
	if (spec[0] == '#') {
		unsigned int r, g, b;
		if (strlen(spec) == 7 && sscanf(spec + 1, "%02x%02x%02x", &r, &g, &b) == 3) {
			*argb = 0xff000000u | (r << 16) | (g << 8) | b;
			return true;
		}
		if (strlen(spec) == 13 && sscanf(spec + 1, "%04x%04x%04x", &r, &g, &b) == 3) {
			*argb = 0xff000000u | ((r >> 8) << 16) | ((g >> 8) << 8) | (b >> 8);
			return true;
		}
	}
	if (strcmp(spec, "black") == 0) {
		*argb = 0xff000000u;
		return true;
	}
	if (strcmp(spec, "white") == 0) {
		*argb = 0xffffffffu;
		return true;
	}
	if (strcmp(spec, "red") == 0) {
		*argb = 0xffff0000u;
		return true;
	}
	if (strcmp(spec, "green") == 0) {
		*argb = 0xff00ff00u;
		return true;
	}
	if (strcmp(spec, "blue") == 0) {
		*argb = 0xff0000ffu;
		return true;
	}
	if (strcmp(spec, "yellow") == 0) {
		*argb = 0xffffff00u;
		return true;
	}
	if (strcmp(spec, "cyan") == 0) {
		*argb = 0xff00ffffu;
		return true;
	}
	if (strcmp(spec, "magenta") == 0) {
		*argb = 0xffff00ffu;
		return true;
	}
	return false;
}

static bool
parse_xpm_color_entry(struct nscde_pixel_icon_context *ctx,
	char *entry, int cpp, uint32_t *argb)
{
	char *rest = entry + cpp;
	char *saveptr = NULL;
	char *tok = strtok_r(rest, " \t", &saveptr);
	char *symbolic = NULL;
	char *color_spec = NULL;

	while (tok) {
		if (strcmp(tok, "s") == 0) {
			symbolic = strtok_r(NULL, " \t", &saveptr);
		} else if (strcmp(tok, "c") == 0) {
			color_spec = strtok_r(NULL, " \t", &saveptr);
		}
		tok = strtok_r(NULL, " \t", &saveptr);
	}

	if (symbolic) {
		if (strcmp(symbolic, "background") == 0) {
			*argb = ctx->bg_argb;
			return true;
		}
		if (strcmp(symbolic, "topShadowColor") == 0) {
			*argb = ctx->hi_argb;
			return true;
		}
		if (strcmp(symbolic, "bottomShadowColor") == 0) {
			*argb = ctx->sh_argb;
			return true;
		}
		if (strcmp(symbolic, "selectColor") == 0) {
			*argb = ctx->sel_argb;
			return true;
		}
	}

	if (color_spec) {
		if (strcmp(color_spec, "iconColor1") == 0) {
				*argb = ctx->bg_argb;
				return true;
		}
		if (strcmp(color_spec, "topShadowColor") == 0) {
				*argb = ctx->hi_argb;
				return true;
		}
		if (strcmp(color_spec, "bottomShadowColor") == 0) {
				*argb = ctx->sh_argb;
				return true;
		}
		if (strcmp(color_spec, "selectColor") == 0) {
				*argb = ctx->sel_argb;
				return true;
		}
		return parse_xpm_color(color_spec, argb);
	}

	return false;
}

static cairo_surface_t *
load_xpm_like_surface(struct nscde_pixel_icon_context *ctx, const char *path)
{
	FILE *fp = fopen(path, "r");
	if (!fp) {
		return NULL;
	}

	char **entries = NULL;
	size_t entries_cap = 0;
	size_t entries_len = 0;
	char line[2048];
	while (fgets(line, sizeof(line), fp)) {
		char *start = strchr(line, '"');
		char *end = start ? strrchr(start + 1, '"') : NULL;
		if (!start || !end || end <= start) {
			continue;
		}
		*end = '\0';
		if (entries_len == entries_cap) {
			size_t new_cap = entries_cap ? entries_cap * 2 : 64;
			char **new_entries = realloc(entries, new_cap * sizeof(char *));
			if (!new_entries) {
				fclose(fp);
				return NULL;
			}
			entries = new_entries;
			entries_cap = new_cap;
		}
		entries[entries_len++] = strdup(start + 1);
	}
	fclose(fp);

	if (entries_len == 0) {
		free(entries);
		return NULL;
	}

	int width = 0;
	int height = 0;
	int ncolors = 0;
	int cpp = 0;
	if (sscanf(entries[0], "%d %d %d %d", &width, &height, &ncolors, &cpp) != 4 ||
		width <= 0 || height <= 0 || ncolors <= 0 || cpp <= 0) {
		goto fail;
	}
	if (entries_len < (size_t)(1 + ncolors + height)) {
		goto fail;
	}

	struct color_entry {
		char key[8];
		uint32_t argb;
	} *colors = calloc((size_t)ncolors, sizeof(*colors));
	if (!colors) {
		goto fail;
	}

	for (int i = 0; i < ncolors; i++) {
		char *entry = entries[1 + i];
		if ((int)strlen(entry) < cpp) {
			free(colors);
			goto fail;
		}
		if (cpp >= (int)sizeof(colors[i].key)) {
			free(colors);
			goto fail;
		}
		memcpy(colors[i].key, entry, (size_t)cpp);
		colors[i].key[cpp] = '\0';

		if (!parse_xpm_color_entry(ctx, entry, cpp, &colors[i].argb)) {
			colors[i].argb = 0x00000000u;
		}
	}

	cairo_surface_t *surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32,
		width, height);
	if (cairo_surface_status(surface) != CAIRO_STATUS_SUCCESS) {
		free(colors);
		goto fail;
	}

	unsigned char *data = cairo_image_surface_get_data(surface);
	int stride = cairo_image_surface_get_stride(surface);
	for (int y = 0; y < height; y++) {
		char *row = entries[1 + ncolors + y];
		uint32_t *dst = (uint32_t *)(data + y * stride);
		for (int x = 0; x < width; x++) {
			char key[8];
			uint32_t argb = 0;
			memcpy(key, row + x * cpp, (size_t)cpp);
			key[cpp] = '\0';
			for (int i = 0; i < ncolors; i++) {
				if (memcmp(colors[i].key, key, (size_t)cpp) == 0) {
					argb = colors[i].argb;
					break;
				}
			}
			dst[x] = argb;
		}
	}
	cairo_surface_mark_dirty(surface);
	free(colors);
	for (size_t i = 0; i < entries_len; i++) {
		free(entries[i]);
	}
	free(entries);
	return surface;

fail:
	for (size_t i = 0; i < entries_len; i++) {
		free(entries[i]);
	}
	free(entries);
	return NULL;
}

static bool
render_icon_surface_exact(cairo_t *cr, cairo_surface_t *surface,
	int sw, int sh, int x, int y, int w, int h)
{
	if (!cr || !surface || sw <= 0 || sh <= 0 || w <= 0 || h <= 0) {
		return false;
	}

	cairo_save(cr);
	cairo_translate(cr, x, y);
	cairo_scale(cr, (double)w / (double)sw, (double)h / (double)sh);
	cairo_set_source_surface(cr, surface, 0, 0);
	cairo_pattern_set_filter(cairo_get_source(cr), CAIRO_FILTER_NEAREST);
	cairo_pattern_set_extend(cairo_get_source(cr), CAIRO_EXTEND_NONE);
	cairo_paint(cr);
	cairo_restore(cr);
	return true;
}
