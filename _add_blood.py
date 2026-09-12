import io
p = "D:/BoomCraft/MineRoulette/scripts/main.gd"
src = open(p, encoding="utf-8").read()

# 1) call the new builder inside _build_world (after _build_arena_rig())
call_old = "\t_build_arena_rig()\n"
call_new = "\t_build_arena_rig()\n\t_build_blood_basin()\n"
assert call_old in src, "call anchor not found"
src = src.replace(call_old, call_new, 1)

# 2) insert the function definition before the furnace-glow comment
fn = '''

## 血色背景层：底部暗红渐变 + 轮盘核心血色圆盘。
## 仅叠加在场地结构之后，呼应参考图下半区密集血色；不影响矿石(gem)/小球(ball)。
func _build_blood_basin() -> void:
\t# 底部血池渐变：屏幕底部亮血色，向上淡出（叠在轮盘与地面之后、在 rig 之前）
\tvar basin_mat := StandardMaterial3D.new()
\tbasin_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
\tbasin_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
\tbasin_mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
\tvar bg := Gradient.new()
\tbg.set_color(0, Color(0.8, 0.11, 0.05, 0.85))   # 底部亮血色
\tbg.set_color(1, Color(0.06, 0.02, 0.02, 0.0))     # 顶部淡出
\tvar btex := GradientTexture2D.new()
\tbtex.gradient = bg
\tbtex.fill = GradientTexture2D.FILL_LINEAR
\tbtex.fill_from = Vector2(0.5, 1.0)
\tbtex.fill_to = Vector2(0.5, 0.0)
\tbtex.width = 64
\tbtex.height = 256
\tbasin_mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
\tbasin_mat.albedo_texture = btex
\tvar bq := MeshInstance3D.new()
\tvar bqm := QuadMesh.new()
\tbqm.size = Vector2(FIELD_RIGHT - FIELD_LEFT + 40.0, 360.0)
\tbq.mesh = bqm
\tbq.material_override = basin_mat
\tbq.position = Vector3(0.0, FIELD_BOTTOM + 150.0, -26.0)
\tadd_child(bq)

\t# 轮盘核心血色圆盘：径向渐变，填充中央空洞（位于 rig 环之后）
\tvar core_mat := StandardMaterial3D.new()
\tcore_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
\tcore_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
\tcore_mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
\tvar cg := Gradient.new()
\tcg.set_color(0, Color(0.85, 0.13, 0.06, 0.7))
\tcg.set_color(1, Color(0.15, 0.03, 0.02, 0.0))
\tvar ctex := GradientTexture2D.new()
\tctex.gradient = cg
\tctex.fill = GradientTexture2D.FILL_RADIAL
\tctex.fill_from = Vector2(0.5, 0.5)
\tctex.fill_to = Vector2(0.5, 0.0)
\tctex.width = 256
\tctex.height = 256
\tcore_mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
\tcore_mat.albedo_texture = ctex
\tvar cq := MeshInstance3D.new()
\tvar cqm := QuadMesh.new()
\tcqm.size = Vector2(300.0, 300.0)
\tcq.mesh = cqm
\tcq.material_override = core_mat
\tcq.position = Vector3(0.0, 0.0, -22.0)
\tadd_child(cq)

'''

anchor = "## 熔池炉光闪烁"
assert anchor in src, "fn anchor not found"
src = src.replace(anchor, fn + anchor, 1)

open(p, "w", encoding="utf-8").write(src)
print("inserted _build_blood_basin; call added:", call_new.strip())
