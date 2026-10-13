# Render a GDS to PNG with KLayout batch mode:
#   GDS=... LYP=$PDK_ROOT/sky130A/libs.tech/klayout/tech/sky130A.lyp OUT=docs/img/layout.png klayout -zz -r scripts/render_layout.py
import pya, os
gds = os.environ["GDS"]; lyp = os.environ["LYP"]; out = os.environ["OUT"]
v = pya.LayoutView()
v.load_layout(gds, 0)
v.load_layer_props(lyp)
v.max_hier()
v.set_config("background-color", "#ffffff")
v.set_config("grid-visible", "false")
v.set_config("text-visible", "false")
v.zoom_fit()
v.save_image_with_options(out, 2400, 820, 0, 0, 0, pya.DBox(), False)
print("wrote", out)
