shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_back;

// 石壁材质（野区墙体 + 边界墙共用）。
//
// 为什么不能直接用 StandardMaterial3D 贴 cliff_side_Diffuse：
// BoxMesh 每个面的 UV 固定是 0..1，16 米长的墙 = 一格 16 米宽的贴图，
// 岩石的水平层理被拉成等距横线，加上赭黄砂岩的暖色，整面墙读成「木板」。
//
// 这里做三件事：
// 1. **世界空间三平面投影**：贴图按 tile_size（米/格）铺，密度与墙长无关。
// 2. **去饱和 + 冷调**：赭黄的暖色相是「木头」的直接来源，拉到中性灰再乘冷调。
// 3. **顶面长草**：俯视机位下顶面最常被看见，那一道草绿顶边是「石壁」的唯一线索。
//
// GL Compatibility 渲染器：只用最基础的采样 + 算术，不依赖 SSAO / 屏幕空间效果。

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D roughness_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D ao_tex : hint_default_white, filter_linear_mipmap, repeat_enable;

// 一格贴图覆盖多少世界米。2~6 米读作「一层岩壁块面」；更小石头碎成砂，更大又变回拉伸纹理。
uniform float tile_size : hint_range(0.5, 12.0) = 3.4;
// 去饱和强度。砂岩贴图的色相必须被抹掉，否则怎么调亮度都是木头色。
uniform float desaturate : hint_range(0.0, 1.0) = 0.84;
uniform vec4 rock_tint : source_color = vec4(0.58, 0.61, 0.63, 1.0);
// 去饱和会整体压暗（灰度 ≈ 原色亮度），这里补回中间调的亮度。
uniform float rock_gain : hint_range(0.5, 3.0) = 1.55;
uniform vec4 moss_color : source_color = vec4(0.24, 0.36, 0.20, 1.0);
uniform float moss_amount : hint_range(0.0, 1.0) = 0.62;
// 脊顶压暗。朝上的面受光最足，一条十几米长的**亮头顶边**读起来不是山脊，
// 是「墙顶铺好了一条走道」。压到 0.6 左右，顶面才比立面沉。
uniform float crest_darken : hint_range(0.3, 1.0) = 0.62;
// 墙根的暗化。没有它，墙和地面之间没有接触阴影，看起来像浮着的贴纸。
uniform float base_darken : hint_range(0.0, 1.0) = 0.38;
uniform float normal_strength : hint_range(0.0, 2.0) = 0.9;
uniform float ao_strength : hint_range(0.0, 1.0) = 0.75;

// --- 砌石砖缝 -------------------------------------------------------------
// 参考图里的城墙是**砌**出来的：横向分层、竖向错缝、缝里发暗。
// 三平面投影的岩壁贴图是「自然崖面」，没有一块砖的边界 ——
// 只在贴图上做文章，16 米长的墙永远读成「一根灰色的原木」。
// 所以在世界空间再铺一层砖格：层高与砖长都按**米**给，与墙长无关。
uniform float brick_course : hint_range(0.2, 1.5) = 0.52;   // 一层砖多高
uniform float brick_length : hint_range(0.4, 4.0) = 1.15;   // 一块砖多长
uniform float mortar_width : hint_range(0.0, 0.2) = 0.035;  // 砖缝半宽（米）
uniform float mortar_darken : hint_range(0.1, 1.0) = 0.62;  // 缝里比砖面暗多少
uniform float brick_tint : hint_range(0.0, 0.4) = 0.10;     // 单块砖的亮度差

varying vec3 world_pos;
varying vec3 world_normal;
// 沿墙面水平方向的位置（局部坐标，米）。长立面用 X，端面用 Z ——
// 不区分的话，端面的砖缝会退化成同一列。
varying float face_along;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// 墙体网格是轴对齐的盒体（尺寸烘进 mesh，节点 scale 恒为 1），
	// 所以直接用 MODEL_MATRIX 旋转法线就是对的，不需要逆转置。
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 local_normal = normalize(NORMAL);
	face_along = abs(local_normal.x) > 0.6 ? VERTEX.z : VERTEX.x;
}

void fragment() {
	vec3 n = normalize(world_normal);
	// 五次方而不是平方：三平面混合带要窄，否则转角处会出现「三张图叠在一起」的重影。
	vec3 w = pow(abs(n), vec3(5.0));
	w /= max(w.x + w.y + w.z, 0.0001);

	vec3 p = world_pos / max(tile_size, 0.05);

	vec3 ax = texture(albedo_tex, p.zy).rgb;
	vec3 ay = texture(albedo_tex, p.xz).rgb;
	vec3 az = texture(albedo_tex, p.xy).rgb;
	vec3 alb = ax * w.x + ay * w.y + az * w.z;

	// 赭黄砂岩 → 灰岩。
	float lum = dot(alb, vec3(0.299, 0.587, 0.114));
	alb = mix(alb, vec3(lum), desaturate) * rock_tint.rgb * rock_gain;

	// --- 砌石砖缝 ---------------------------------------------------------
	float course_h = max(brick_course, 0.05);
	float brick_w = max(brick_length, 0.05);
	float course = floor(world_pos.y / course_h);
	// 错缝：奇数层整体平移半块砖。少了这一步，竖向砖缝会连成一条通到底的直线，
	// 俯视看就是「一堵竖条纹的墙」，比不做还假。
	float stagger = mod(course, 2.0) * 0.5;
	float u = face_along / brick_w + stagger;
	float v = world_pos.y / course_h;
	vec2 cell = fract(vec2(u, v));
	// 到最近砖缝的距离（米）：先取「离格线多少个格子」，再乘回米。
	vec2 edge = min(cell, 1.0 - cell) * vec2(brick_w, course_h);
	float gap = min(edge.x, edge.y);
	// solid = 0 在缝里，1 在砖面中央。过渡带取缝宽的两倍，免得缝是一条硬黑线。
	float solid = smoothstep(mortar_width, mortar_width * 1.9 + 0.001, gap);
	// 单块砖一点亮度差。没有它，一整面墙是一块单色板，砖缝再准也像画上去的。
	float brick_hash = fract(sin(dot(vec2(course, floor(u)), vec2(27.13, 61.70))) * 43758.5453);
	alb *= mix(1.0 - brick_tint, 1.0 + brick_tint * 0.5, brick_hash);
	alb *= mix(mortar_darken, 1.0, solid);

	// 顶面草：用同一张贴图的两个频率做遮罩，省掉一张噪声图。
	// 必须是**斑块**而不是一层均匀绿 —— 单一频率 + 宽阈值会让整块顶面
	// 都越过阈值，顶面就变成一块绿毯子；两个频率叠起来才有「石板缝里冒草」。
	float g1 = texture(albedo_tex, p.xz * 0.31 + vec2(0.37, 0.11)).g;
	float g2 = texture(albedo_tex, p.xz * 0.87 + vec2(0.61, 0.23)).g;
	float grain = g1 * 0.65 + g2 * 0.35;
	float up = smoothstep(0.45, 0.92, n.y);
	float moss = up * moss_amount * smoothstep(0.34, 0.66, grain);
	alb = mix(alb, moss_color.rgb * (0.75 + 0.5 * grain), moss);

	// 脊顶压暗：朝上的面在阳光下最亮，不压就是一条亮头顶边 —— 俯视会读成
	// 「墙顶铺好了一条走道」，比没有石头更假。0.85 而不是 1.0，
	// 留住一点受光，否则顶面变成一条死黑边。
	alb *= mix(1.0, crest_darken, up * 0.85);

	// 墙根压暗：接触阴影。顶面 world_pos.y 已经到墙高，不会被压暗。
	alb *= mix(1.0 - base_darken, 1.0, clamp(world_pos.y / 1.1, 0.0, 1.0));

	float aox = texture(ao_tex, p.zy).r;
	float aoy = texture(ao_tex, p.xz).r;
	float aoz = texture(ao_tex, p.xy).r;
	float occ = aox * w.x + aoy * w.y + aoz * w.z;
	// 砖缝要同时压反照率和遮挡：只压颜色的话，缝在阴影里会「浮」起来 ——
	// 因为它比周围的砖面更亮，看着像画上去的一条白线。
	occ *= mix(0.70, 1.0, solid);
	alb *= mix(1.0, occ, ao_strength);

	// 三平面法线：每张法线图的 xy 是切线方向，z 是「朝外」，只取切线分量叠加到世界法线上。
	vec3 nx = texture(normal_tex, p.zy).xyz * 2.0 - 1.0;
	vec3 ny = texture(normal_tex, p.xz).xyz * 2.0 - 1.0;
	vec3 nz = texture(normal_tex, p.xy).xyz * 2.0 - 1.0;
	vec3 bump = vec3(0.0, nx.y, nx.z) * w.x
		+ vec3(ny.x, 0.0, ny.y) * w.y
		+ vec3(nz.x, nz.y, 0.0) * w.z;
	vec3 wn = normalize(n + bump * normal_strength);

	float rx = texture(roughness_tex, p.zy).r;
	float ry = texture(roughness_tex, p.xz).r;
	float rz = texture(roughness_tex, p.xy).r;
	float rough = rx * w.x + ry * w.y + rz * w.z;

	ALBEDO = alb;
	ROUGHNESS = clamp(mix(rough, 1.0, moss), 0.0, 1.0);
	METALLIC = 0.0;
	AO = occ;
	AO_LIGHT_AFFECT = 0.35;
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
}
