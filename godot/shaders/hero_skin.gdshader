shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// 英雄「皮肤材质层」：把通用角色包里那几套贴图，重新上色成每个英雄的设定色。
//
// 为什么需要它（而不是继续用 ModelUtils.tint 直接改 albedo_color）：
//   1. 通用包的 albedo 贴图本身是「棕色皮甲 + 绿色布料」的杂色。直接压一个
//      albedo_color 只是整体乘一个色相，结果是「脏绿」「脏棕」，5 个英雄都土；
//   2. 王者荣耀的角色靠的是**三件事**：主色纯度、明暗分层、边缘轮廓光。
//      这三件都必须逐像素做，albedo_color 只能做第一件的一半；
//   3. 需要在同一个材质里同时拿到「基色替换 + 明暗保留 + 轮廓光 + 队伍色」，
//      而队伍色每帧可能变（联机中途换视角），只能走 shader 参数。
//
// 关键口径（都是看着实拍图调的，别凭手感改回去）：
//   - 贴图亮度先做一次**对数式拉伸**（pow(luma, contrast)），把皮甲的暗部提上来，
//     否则换成深色主色之后整个人会糊成一团黑；
//   - 主色替换用 luma 做 lerp 权重，**保留 0.55 的原始明暗**，否则衣服变成一块平板；
//   - 轮廓光用 fresnel 的 3 次方：2 次方在 21 米机位下会糊到整条手臂，
//     4 次方又只剩一条 1 像素的线；
//   - 队伍色只在**暗部**叠加（pow(1-fresnel)），亮部保持英雄主色 —— 否则红蓝两队
//     的英雄会变成两个纯色色块，认不出是谁。

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 base_color : source_color = vec4(1.0);
// 第二主色（金属件 / 皮革件），按贴图的暗部占比混入。
uniform vec4 accent_color : source_color = vec4(1.0);
uniform float accent_amount : hint_range(0.0, 1.0) = 0.0;
// 主色替换强度。0 = 保持原贴图，1 = 完全由 base_color 决定色相。
uniform float recolor : hint_range(0.0, 1.0) = 0.85;
// 明暗保留：把原贴图的 luma 分几层映射到 1±lighting_keep。
uniform float lighting_keep : hint_range(0.0, 1.0) = 0.55;
uniform float contrast : hint_range(0.5, 3.0) = 1.35;
uniform float brightness : hint_range(0.2, 3.0) = 1.0;
// 轮廓光：颜色 × 强度。强度 0 时完全不参与（默认关闭，避免和其他叠加层打架）。
uniform vec4 rim_color : source_color = vec4(1.0);
uniform float rim_strength : hint_range(0.0, 3.0) = 0.0;
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
// 队伍色：压暗部 + 描边缘，双管齐下。
//
// 为什么需要两处：实测（fight_close.png 里两个苍刃对砍）只压暗部时，
// 16% 的染色在 21 米机位下**完全看不出来** —— 红蓝两个苍刃身体颜色几乎一样，
// 玩家会对着队友挥技能。所以再加一档**轮廓队伍色**：边缘亮边不占身体色彩面积，
// 主色仍然认得出是谁，但人群里看轮廓就能分敌我。
uniform vec4 team_tint : source_color = vec4(1.0);
uniform float team_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 team_rim_color : source_color = vec4(0.0, 0.0, 0.0, 0.0);
uniform float team_rim_strength : hint_range(0.0, 4.0) = 0.0;
// 自发光（发丝 / 晶饰 / 纹路）。按贴图亮度加权，避免"整件衣服在发光"。
uniform vec4 glow_color : source_color = vec4(1.0);
uniform float glow_strength : hint_range(0.0, 6.0) = 0.0;
// 高光粗糙度。布料要哑（0.85+），金属件偏低（0.35）。
uniform float roughness_value : hint_range(0.0, 1.0) = 0.82;
uniform float metallic_value : hint_range(0.0, 1.0) = 0.0;
uniform float specular_value : hint_range(0.0, 1.0) = 0.35;

void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	// 贴图可能是带 alpha 的（头发 / 布料镂空），保留 alpha 交给 alpha_scissor 处理。
	float luma = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
	// 对数式提亮：暗部抬得多、亮部抬得少，皮甲不会一压主色就变成黑洞。
	float shaped = pow(clamp(luma, 0.0, 1.0), 1.0 / max(0.05, contrast));
	// 明暗分层：以 0.5 为中心收放，保住褶皱/甲片的层次。
	float shade = mix(0.5, shaped, lighting_keep * 2.0);
	// 主色替换：亮部偏 base，暗部偏 accent，再按 recolor 与原贴图混合。
	vec3 toned = mix(accent_color.rgb, base_color.rgb, smoothstep(0.25, 0.85, shaped));
	vec3 original = tex.rgb * brightness;
	// 0.42 + shade*0.62：最亮处 ≈ 1.04、最暗处 ≈ 0.48。第一版写 0.55+shade*0.9
	// 最亮能到 1.54，在 FILMIC + 1.68 主光下整件衣服直接过曝成粉彩色。
	//
	// ★ `brightness` 必须乘在 toned 上，不能只乘 original。
	//   第一版只写了 `original = tex.rgb * brightness`，而 recolor 通常 0.86~0.94，
	//   等于 brightness 被稀释到只剩 6~14% —— 调它几乎没有效果。
	//   浅色英雄（翎羽的米白战衣）正是靠这一档抬回米白：
	//   实测米白 base 0.62 渲出来只有 114/128/133（灰蓝）。
	vec3 lit = mix(original, toned * brightness * (0.42 + shade * 0.62), recolor);
	// 暗部压入队伍色：亮部保留英雄主色，红蓝两队不至于变成两个色块。
	vec3 dark_mask = vec3(1.0 - shaped);
	lit = mix(lit, lit * team_tint.rgb, team_amount * dark_mask);
	// 金属 / 皮革的第二主色：只在中间调落，避免整块发灰。
	lit = mix(lit, accent_color.rgb * (0.5 + shaped * 0.8), accent_amount * smoothstep(0.15, 0.7, 1.0 - shaped));

	ALBEDO = clamp(lit, vec3(0.0), vec3(4.0));
	ROUGHNESS = roughness_value;
	METALLIC = metallic_value;
	SPECULAR = specular_value;

	// 轮廓光：fresnel 三次方，只在掠射角出现，21 米机位下是一条清楚的亮边。
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	vec3 rim = rim_color.rgb * rim_strength * fres;

	if (glow_strength > 0.001) {
		// 自发光按「贴图亮部」加权：只有原本就亮的区域（发丝高光、金饰）才发亮。
		float glow_mask = smoothstep(0.45, 0.95, shaped);
		EMISSION = glow_color.rgb * glow_strength * glow_mask;
	}
	EMISSION += rim;
	// 轮廓队伍色：敌我识别靠这一圈边缘。乘 2.2 次方让它比上面的英雄 rim 更贴边，
	// 不抢主色；强度由 GDScript 按红/蓝给（0.72）。
	float team_fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.2);
	EMISSION += team_rim_color.rgb * team_rim_strength * team_fres;
}
