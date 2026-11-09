shader_type spatial;
// Rauch ohne Schattenempfang (Explosionen/Einschlaege: viel Overdraw, ~40 % guenstiger). Code: smoke_common.gdshaderinc
render_mode blend_mix, cull_disabled, depth_draw_never, specular_disabled, shadows_disabled;
#include "res://game/vfx/shaders/smoke_common.gdshaderinc"
