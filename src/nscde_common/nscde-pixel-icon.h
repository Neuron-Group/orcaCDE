#ifndef NSCDE_PIXEL_ICON_H
#define NSCDE_PIXEL_ICON_H

#include <stdbool.h>
#include <stdint.h>

#include <cairo.h>

#define NSCDE_PIXEL_ICON_PATH_MAX 1024
#define NSCDE_PIXEL_ICON_CACHE_MAX 32

struct nscde_pixel_icon_cache_entry {
	char path[NSCDE_PIXEL_ICON_PATH_MAX];
	cairo_surface_t *surface;
	int width;
	int height;
};

struct nscde_pixel_icon_context {
	char data_dir[NSCDE_PIXEL_ICON_PATH_MAX];
	uint32_t bg_argb;
	uint32_t hi_argb;
	uint32_t sh_argb;
	uint32_t sel_argb;
	struct nscde_pixel_icon_cache_entry cache[NSCDE_PIXEL_ICON_CACHE_MAX];
};

void nscde_pixel_icon_init(struct nscde_pixel_icon_context *ctx,
	const char *data_dir);
void nscde_pixel_icon_set_data_dir(struct nscde_pixel_icon_context *ctx,
	const char *data_dir);
void nscde_pixel_icon_set_palette(struct nscde_pixel_icon_context *ctx,
	uint32_t bg_argb, uint32_t hi_argb, uint32_t sh_argb, uint32_t sel_argb);
void nscde_pixel_icon_destroy(struct nscde_pixel_icon_context *ctx);
bool nscde_pixel_icon_render_asset(struct nscde_pixel_icon_context *ctx,
	cairo_t *cr, const char *relpath, int x, int y, int w, int h);
bool nscde_pixel_icon_render_asset_centered(
	struct nscde_pixel_icon_context *ctx, cairo_t *cr,
	const char *relpath, int x, int y, int w, int h, bool shrink_only);
bool nscde_pixel_icon_get_asset_size(struct nscde_pixel_icon_context *ctx,
	const char *relpath, int *width, int *height);

#endif
