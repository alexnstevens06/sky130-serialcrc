# Regenerates docs/img/block_diagram.png and docs/img/crc_dual_edge.png (run from docs/img/).
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch

def box(ax, x, y, w, h, title, sub="", fc="#e8f0fe", ec="#1a4f9c", sfs=8.5):
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.02,rounding_size=0.12",
                                fc=fc, ec=ec, lw=1.6))
    ty = y + h/2 + (0.14 if sub else 0)
    if h > 3: ty = y + h - 0.45
    ax.text(x + w/2, ty, title, ha="center", va="center",
            fontsize=11, weight="bold", color="#10264a")
    if sub:
        ax.text(x + w/2, (y + h/2 - 0.2) if h <= 3 else (y + h/2 - 0.1), sub, ha="center", va="center",
                fontsize=sfs, color="#333")

def arrow(ax, x0, y0, x1, y1, label="", color="#333", ls="-", lx=None, ly=None, fs=8):
    ax.annotate("", xy=(x1, y1), xytext=(x0, y0),
                arrowprops=dict(arrowstyle="-|>", color=color, lw=1.3, ls=ls, shrinkA=0, shrinkB=0))
    if label:
        ax.text(lx if lx is not None else (x0+x1)/2, ly if ly is not None else (y0+y1)/2 + 0.12,
                label, ha="center", va="bottom", fontsize=fs, color=color)

# ---------------- block diagram ----------------
fig, ax = plt.subplots(figsize=(14, 7.2))
ax.set_xlim(0, 14); ax.set_ylim(0, 7.2); ax.axis("off")
ax.add_patch(FancyBboxPatch((1.9, 0.35), 9.7, 6.45, boxstyle="round,pad=0.02,rounding_size=0.2",
             fc="#fafafa", ec="#999", lw=1, ls="--"))
ax.text(2.05, 6.6, "tt_um_alexstevens_serialcrc  (clk 66 MHz, rst_n async active-low)",
        fontsize=10, color="#555", va="center")
# inputs
pins_in = [("ui_in[0]  uart_rx", 1.2), ("ui_in[1]  spi_sclk", 5.6), ("ui_in[2]  spi_cs_n", 4.9),
           ("ui_in[3]  spi_mosi", 4.2)]
for name, y in pins_in:
    ax.text(0.05, y, name, fontsize=9, va="center", family="monospace")
    box(ax, 2.2, y - 0.25, 1.1, 0.5, "sync2", fc="#f1f3f4", ec="#666")
    arrow(ax, 1.55, y, 2.2, y)
# SPI
box(ax, 4.0, 3.9, 2.0, 2.0, "spi_slave", "mode 0, 16-bit frames\n{rw,addr[6:0]}, data")
for _, y in pins_in[1:]:
    arrow(ax, 3.3, y, 4.0, y)
# regfile
box(ax, 7.0, 2.6, 2.0, 3.3, "regfile", "18 registers\nCTRL / STATUS / BAUD\nPOLY / INIT / XOROUT\nGPIO, IRQ logic")
arrow(ax, 6.0, 5.2, 7.0, 5.2, "addr, wdata, wr, rd_req")
arrow(ax, 7.0, 4.4, 6.0, 4.4, "rdata, rd_done")
# uart rx
box(ax, 4.0, 0.7, 2.0, 1.1, "uart_rx", "8N1, mid-bit sample")
arrow(ax, 3.3, 1.2, 4.0, 1.2)
arrow(ax, 6.0, 1.3, 7.6, 2.6, "rx byte, valid,\nframe_err", lx=6.55, ly=1.95)
# uart tx
box(ax, 9.7, 4.6, 1.7, 1.0, "uart_tx", "8N1")
arrow(ax, 9.0, 5.1, 9.7, 5.1, "div, byte", ly=5.18)
# crc
box(ax, 9.7, 1.0, 1.7, 2.1, "crc16_engine", "dual-edge\n2 bits / clock\n4 clocks / byte", fc="#fde8e8", ec="#a61b1b")
arrow(ax, 9.0, 2.85, 9.7, 2.85, "poly, init,\nxorout, byte", lx=9.35, ly=2.62)
arrow(ax, 9.7, 1.5, 9.0, 1.5 + 1.1, "result,\nbusy, done", lx=9.33, ly=1.55)
arrow(ax, 6.0, 0.95, 9.7, 1.25, "autofeed (CTRL[2])", color="#a61b1b", ls="--", lx=7.9, ly=0.72)
# outputs
outs = [("uo_out[0]  uart_tx", 5.1, (11.4, 5.1)), ("uo_out[1]  spi_miso", 6.2, None),
        ("uo_out[2]  crc_busy", 2.0, (11.4, 2.0)), ("uo_out[3]  irq", 3.6, None),
        ("uo_out[4]  tx_busy", 4.75, (11.4, 4.75)), ("uo_out[5]  rx_valid", 3.95, None),
        ("uio_out / uio_oe  GPIO", 3.25, None)]
for name, y, src in outs:
    ax.text(12.0, y, name, fontsize=9, va="center", family="monospace")
    if src:
        arrow(ax, src[0], src[1], 11.95, y)
arrow(ax, 5.0, 5.9, 5.0, 6.2, ""); ax.plot([5.0, 11.95], [6.2, 6.2], color="#333", lw=1.3)
arrow(ax, 11.7, 6.2, 11.95, 6.2)
for y in (3.6, 3.95, 3.25):
    arrow(ax, 9.0, y, 11.95, y)
ax.text(7.0, 0.1, "Unused: ui_in[7:4], uio_in, ena.  uo_out[7:6] = 0.", fontsize=8.5, color="#666", ha="center")
fig.tight_layout()
fig.savefig("block_diagram.png", dpi=150)

# ---------------- CRC dual-edge datapath + timing ----------------
fig = plt.figure(figsize=(14, 8.6))
ax = fig.add_axes([0.02, 0.50, 0.96, 0.44]); ax.set_xlim(0, 14); ax.set_ylim(0, 4.4); ax.axis("off")
ax.set_title("crc16_engine: two LFSR steps per clock, one on each edge", fontsize=13, weight="bold", loc="left")
box(ax, 0.4, 1.7, 1.9, 1.1, "crc[15:0]", "posedge flops\n(reset = RESET_VAL)")
box(ax, 3.1, 1.7, 2.3, 1.1, "step_lo", "(crc << 1) ^\n(crc[15]^sh[7] ? poly : 0)", fc="#fff7e0", ec="#b07a00", sfs=8)
box(ax, 6.2, 1.7, 1.9, 1.1, "crc_h[15:0]", "negedge flops\n(no reset)", fc="#fde8e8", ec="#a61b1b")
box(ax, 8.9, 1.7, 2.3, 1.1, "step_hi", "(crc_h << 1) ^\n(crc_h[15]^sh[6] ? poly : 0)", fc="#fff7e0", ec="#b07a00", sfs=8)
box(ax, 11.9, 1.7, 1.7, 1.1, "next crc", "mux: clear / busy\n(init or step_hi)")
arrow(ax, 2.3, 2.25, 3.1, 2.25); arrow(ax, 5.4, 2.25, 6.2, 2.25, "rise -> fall", color="#a61b1b", ly=2.9)
arrow(ax, 8.1, 2.25, 8.9, 2.25); arrow(ax, 11.2, 2.25, 11.9, 2.25, "fall -> rise", color="#a61b1b", ly=2.9)
ax.annotate("", xy=(1.35, 1.7), xytext=(12.75, 1.7),
            arrowprops=dict(arrowstyle="-|>", color="#333", lw=1.3, connectionstyle="bar,fraction=-0.08"))
ax.text(7.0, 0.55, "sh[7:0] shifts by 2 each rising edge; busy = (cnt != 0), cnt = 4 bit pairs per byte",
        fontsize=9, ha="center", color="#333")
ax.text(0.4, 3.85,
        "Half-cycle budget at 66 MHz: 7.575 ns - 1.058 ns inter-clock uncertainty (0.30 + 5% DCD) - setup.\n"
        "Worst routed path (max_ss_100C_1v60): crc[15] -> xor2 -> fanout buf (21) -> nand2 -> xnor2 -> crc_h[1],"
        " data path 3.98 ns, slack +2.34 ns.  Worst fall->rise slack +2.40 ns.",
        fontsize=9, va="center", color="#222")

# timing diagram
t = fig.add_axes([0.14, 0.05, 0.84, 0.40]); t.set_xlim(-0.3, 6.3); t.set_ylim(-0.5, 6.0); t.axis("off")
rows = ["clk", "start", "busy", "crc (posedge)", "crc_h (negedge)", "done"]
ys = [5, 4, 3, 2, 1, 0]
for r, y in zip(rows, ys):
    t.text(-0.35, y + 0.3, r, ha="right", va="center", fontsize=10, family="monospace")
# clk: period 1, starts low->high at 0
cx, cy = [], []
for k in range(6):
    cx += [k, k, k + 0.5, k + 0.5]; cy += [0, 1, 1, 0]
cx.append(6); cy.append(0)
t.plot(cx, [5 + 0.6*v for v in cy], color="#1a4f9c", lw=1.5)
def wave(y, segs, color="#333"):
    xs, vs = [], []
    for (a, b, v) in segs:
        xs += [a, b]; vs += [v, v]
    t.plot(xs, [y + 0.6*v for v in vs], color=color, lw=1.5, drawstyle="default")
wave(4, [(-0.2, 0.0, 0), (0.0, 1.0, 1), (1.0, 6.0, 0)])
t.plot([0.0, 0.0], [4, 4.6], color="#333", lw=1.5); t.plot([1.0, 1.0], [4, 4.6], color="#333", lw=1.5)
wave(3, [(-0.2, 1.0, 0), (1.0, 5.0, 1), (5.0, 6.0, 0)])
t.plot([1.0, 1.0], [3, 3.6], color="#333", lw=1.5); t.plot([5.0, 5.0], [3, 3.6], color="#333", lw=1.5)
wave(5 - 5, [(-0.2, 5.0, 0), (5.0, 6.0, 1)])
t.plot([5.0, 5.0], [0, 0.6], color="#333", lw=1.5); t.plot([6.0, 6.0], [0, 0.6], color="#333", lw=1.5)
def bus(y, edges, labels, color):
    for i in range(len(edges) - 1):
        a, b = edges[i], edges[i + 1]
        d = 0.06
        t.fill([a + d, b - d, b, b - d, a + d, a], [y + 0.6, y + 0.6, y + 0.3, y, y, y + 0.3],
               fc=color, ec="#333", lw=1)
        t.text((a + b)/2, y + 0.3, labels[i], ha="center", va="center", fontsize=8)
bus(2, [-0.2, 2, 3, 4, 5, 6.2], ["init", "2 bits", "4 bits", "6 bits", "8 bits"], "#e8f0fe")
bus(1, [-0.2, 1.5, 2.5, 3.5, 4.5, 5.5, 6.2], ["x", "1 bit", "3 bits", "5 bits", "7 bits", "x"], "#fde8e8")
for k in range(6):
    t.axvline(k, color="#1a4f9c", lw=0.5, ls=":", ymin=0.02, ymax=0.97)
    t.axvline(k + 0.5, color="#a61b1b", lw=0.5, ls=":", ymin=0.02, ymax=0.97)
t.text(3.0, -0.45, "start sampled at rising edge 1; 8 bits processed in 4 clocks; crc_h is recomputed on every falling edge",
       ha="center", fontsize=9, color="#333")
fig.savefig("crc_dual_edge.png", dpi=150)
print("ok")
