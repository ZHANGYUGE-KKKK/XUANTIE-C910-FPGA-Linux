"""Generate the reviewed electrical drawing set, SVG sheets and full-contact netlist.

This produces documentation, NOT a routed PCB, Gerber or native CAD project.
Run with bundled Python containing reportlab. Source of truth: pinmap.json.
"""
from pathlib import Path
import json
import hashlib
import html
import re
from collections import Counter
from reportlab.pdfgen import canvas
from reportlab.lib.pagesizes import A3, landscape
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.cidfonts import UnicodeCIDFont
from reportlab.pdfbase.ttfonts import TTFont

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "output"
PDF = OUT / "pdf" / "FMC_DDR3_passive_adapter.pdf"
ROWS = "ABCDEFGHJK"
W, H = landscape(A3)
INK = "#183246"
BLUE = "#005f93"
TEAL = "#06715f"
RED = "#a23226"
GREY = "#687784"
LIGHT = "#edf3f7"
font_file = Path("C:/Windows/Fonts/simhei.ttf")
if font_file.exists():
    pdfmetrics.registerFont(TTFont("CJK", str(font_file)))
    CJK = "CJK"
else:
    pdfmetrics.registerFont(UnicodeCIDFont("STSong-Light"))
    CJK = "STSong-Light"


def net_name(port):
    suffix = port.removeprefix("C0_DDR3_0_")
    m = re.fullmatch(r"(addr|ba|dq|dm)\[(\d+)\]", suffix)
    if m:
        return "DDR_" + {"addr": "A", "ba": "BA", "dq": "DQ", "dm": "DM"}[m[1]] + m[2]
    m = re.fullmatch(r"dqs_([pn])\[(\d+)\]", suffix)
    if m:
        return f"DDR_DQS{m[2]}_{m[1].upper()}"
    if suffix.startswith("ck_"):
        return "DDR_CK_" + suffix[3].upper()
    return "DDR_" + suffix.replace("[0]", "").upper()


def make_manifest(doc):
    pins = {ref: {f"{r}{n}": {"ref": ref, "pin": f"{r}{n}", "net": None,
                              "status": "NC", "note": "Unused; no same-number passthrough"}
                  for r in ROWS for n in range(1, 41)} for ref in ("J1", "J2")}

    def assign(ref, pin, net, note, other=None):
        item = pins[ref][pin]
        assert item["net"] is None, f"Contact collision: {ref}.{pin}"
        item.update(net=net, status="CONNECTED", note=note)
        if other:
            item["partner"] = other

    g = doc["ground_contacts"]
    standard = {f"{r}{n}" for r, nums in g["standard_carrier_ground_by_row"].items() for n in nums}
    assert len(standard) == 159
    ground = {"J1": standard | set(g["carrier_add_to_ground"]),
              "J2": (standard - set(g["subcard_remove_from_standard_ground"])) | set(g["subcard_add_to_ground"])}
    for ref, values in ground.items():
        for pin in values:
            assign(ref, pin, "GND", "Common continuous ground plane")
    pins["J1"]["H2"]["note"] = "PRSNT_M2C intentionally grounded on adapter"
    for power in doc["power_connections"]:
        for ref, field in (("J1", "carrier_contacts"), ("J2", "subcard_contacts")):
            for pin in power[field]:
                assign(ref, pin, power["net"], f"{power['voltage_volts']} V; verify hardware before connection")
    for sig in doc["signals"]:
        net = net_name(sig["top_port"])
        assign("J1", sig["carrier_contact"], net, sig["carrier_net"], f"J2.{sig['subcard_contact']}")
        assign("J2", sig["subcard_contact"], net, sig["subcard_net"], f"J1.{sig['carrier_contact']}")
    for ref in pins:
        for pin in ("C35", "C37", "D1"):
            assert pins[ref][pin]["net"] is None
            pins[ref][pin]["note"] = "Mandatory isolation; see power sheet"
    for pin in ("G6", "G7"):
        assert pins["J1"][pin]["net"] is None
        pins["J1"][pin]["note"] = "No reference clock on FMC"
    for pin in ("G17", "G26", "H6"):
        assert pins["J2"][pin]["net"] is None
        pins["J2"][pin]["note"] = "Daughtercard contact is NC, not GND"
    nets = {}
    for ref, values in pins.items():
        for item in values.values():
            if item["net"]:
                nets.setdefault(item["net"], []).append({"ref": ref, "pin": item["pin"]})
    assert len(nets) == 53
    assert len(nets["GND"]) == 319
    assert len(nets["3V3"]) == 10 and len(nets["VADJ"]) == 8
    assert all(len(v) == 2 for k, v in nets.items() if k.startswith("DDR_"))
    manifest = {"revision": doc["revision"], "source_sha256": hashlib.sha256((ROOT / "pinmap.json").read_bytes()).hexdigest(),
                "scope": "Electrical documentation only; not a native CAD PCB or manufacturing release",
                "connectors": doc["adapter_connectors"], "contact_count": 800,
                "net_count": len(nets), "contacts": pins, "nets": nets,
                "optional_components": doc["optional_components"],
                "mechanical_terminals": g["mechanical_terminals"],
                "statistics": {ref: dict(Counter(item["net"] if item["net"] in ("GND", "3V3", "VADJ") else item["status"]
                                                 for item in values.values())) for ref, values in pins.items()}}
    return manifest


def write_connections(doc, manifest):
    """Human-readable primary handoff; generated from the same reviewed mapping."""
    lines = ["# FMC 转接板逐针对应表", "", f"版本 {doc['revision']}。从 pinmap.json 自动生成；不要只改本表。", "",
             "用途：供你在自己的 EDA 软件中画原理图。不是可投板的 PCB 工程。", "",
             "## 1. 怎么读表", "",
             "母板 J2 = VCU118 FMC_HPC1；子板 J4 = DDR 子板接口。转接板底面 J1 对接母板 J2，顶面 J2 对接子板 J4。", "",
             "下面每行就是一条实际连接：母板 J2 针号 -> 转接板 J1 同号 -> 转接板 J2 指定针号 -> 子板 J4 指定针号。", "",
             "针号按接插件电气编号，不按屏幕/焊接面位置编号；背面封装坐标的镜像不改变针号。原图内部蓝色标注有错位，按外侧黑色针号及连线核对。", "",
             "## 2. 全部 50 根 DDR 信号", "",
             "除 DQ/DQS 双向、DM 输出外，其余均由 FPGA MIG 输出；CK 是 DRAM 时钟，不是 MIG 的 250 MHz 参考输入。", "",
             "| DDR 网名 | FPGA 球号 | 母板 J2 / 转接板 J1 | 转接板 J2 / 子板 J4 | 子板原始网络 | U26 球号 |",
             "| --- | --- | --- | --- | --- | --- |"]
    for s in doc["signals"]:
        lines.append(f"| {net_name(s['top_port'])} | {s['fpga_pin']} | {s['carrier_contact']} | {s['subcard_contact']} | {s['subcard_net']} | {s['u26_ball']} |")
    lines += ["", "DQ0..7、DM0、DQS0 是低字节；DQ8..15、DM1、DQS1 是高字节。CK/DQS 保持 P/N；单端 GPIO/LA 名中的 P/N 不代表 DDR 差分，也不表示可以交换位序。", "",
              "## 3. 电源和公共地", "",
              "3V3 和 VADJ 是两个独立网络，不能短接。每一网的全部针接到同一电源铜皮；所有 GND 接同一连续地平面，不是独立一对一线。", "",
              "| 网络 | 母板 J2 / 转接板 J1 | 转接板 J2 / 子板 J4 | 条件 |",
              "| --- | --- | --- | --- |"]
    for p in doc["power_connections"]:
        lines.append(f"| {p['net']} | {', '.join(p['carrier_contacts'])} | {', '.join(p['subcard_contacts'])} | 实测 {p['voltage_volts']} V |")
    lines += ["", "下面只写数字，需加本行字母。例如 A 行的 1 表示 A1。", "",
              "| 行 | 转接板 J1 接 GND 的针号 | 转接板 J2 接 GND 的针号 |", "| --- | --- | --- |"]
    for r in ROWS:
        columns = [", ".join(str(n) for n in range(1, 41) if manifest["contacts"][ref][f"{r}{n}"]["net"] == "GND") for ref in ("J1", "J2")]
        lines.append(f"| {r} | {columns[0]} | {columns[1]} |")
    lines += ["", "母板端 GND 162 针；子板端 GND 157 针。两端额外电气屏蔽端子按正式封装接地，机械孔不默认是电气针。", "",
              "## 4. 所有 NC 接点", "",
              "NC 表示该转接板焊盘不接线、不接地、不透传；同号顶底焊盘也不能自动连通。下表穷举两端 NC，数字需加行字母。", "",
              "| 行 | 转接板 J1 NC 针号 | 转接板 J2 NC 针号 |", "| --- | --- | --- |"]
    for r in ROWS:
        columns = [", ".join(str(n) for n in range(1, 41) if manifest["contacts"][ref][f"{r}{n}"]["status"] == "NC") or "无" for ref in ("J1", "J2")]
        lines.append(f"| {r} | {columns[0]} | {columns[1]} |")
    lines += ["", "母板端 NC 179 针；子板端 NC 184 针。特别注意：", "",
              "- 两端 C35/C37 均 NC：母板是 12 V，不允许误接地或直通。两端 D1 均 NC：隔离 PGOOD 与子板 3V3_B。",
              "- 子板 B2/F2 接 GND；G17/G26/H6 为 NC；H2 接 GND。本版纠正了旧图这五处误标。母板端这些标准地针仍接 GND。",
              "- 转接板 J1 H2 接 GND 表示插卡；J1 C34/D35 接 GND，但 J2 同号 NC。",
              "- 母板 G6/G7 是 NC；子板 G6/G7 分别接 ODT/RESET_n，来自母板 G18/G19。", "",
              "## 5. 不能省略的实物确认", "",
              "- 转接板不加晶振/PLL/时钟缓冲。当前工程参考时钟在母板内部：U18、J8、250 MHz；本次审核没有改动它。",
              "- VADJ/VCCO 实测 1.5 V；DRAM VDD/VDDQ=1.5 V，VTT/VREF=0.75 V。子板供电、去耦和终端必须有正确焊装，跳线详见 README。",
              "- RN28 的 RESET_n-to-VTT 39 ohm 支路若焊装，不能直接靠 4.7k 下拉保持复位低。R_RESET 默认 DNP，确认该支路已隔离且满足上电复位要求后再决定焊装；不能整颗拆 RN28。",
              "- 本表确认电气对应关系，不保证 1600 MT/s。两个接口加三块板的延迟、阻抗、回流、机械封装和实际焊装还需验证。", "",
              "## 6. 本版审核范围", "",
              "源图独立核对：母板第 39/40/41 页的 50 对针号/网络；子板第 4 页全部 400 针的引线/地总线/NC，以及 50 对针号/GPIO 网络。U26 球号和 CK/DQS 位序、供电页与 RN28 另作图面核对。", "",
              "audit_subcard_source.py 重查源 PDF，verify_pinmap.ps1 检查当前 wrapper/XDC/官方 XDC 和生成的 800 针网表。没有运行综合、实现、硬件测试或原生 EDA ERC。", ""]
    (ROOT / "connections.md").write_text("\n".join(lines), encoding="utf-8")


class Drawing:
    """Identical geometry on PDF canvas and independent SVG sheets."""
    def __init__(self):
        for folder in (PDF.parent, OUT / "svg"):
            folder.mkdir(parents=True, exist_ok=True)
        self.c = canvas.Canvas(str(PDF), pagesize=(W, H), pageCompression=1)
        self.c.setTitle("FMC DDR3 passive adapter - revision C - wiring reference and PCB guide")
        self.c.setAuthor("C910 VCU118 project")
        self.page = 0
        self.svg = []

    def line(self, x1, y1, x2, y2, color=INK, width=0.7, dashed=False):
        self.c.setStrokeColor(color)
        self.c.setLineWidth(width)
        self.c.setDash(3, 2) if dashed else self.c.setDash()
        self.c.line(x1, y1, x2, y2)
        dash = ' stroke-dasharray="3 2"' if dashed else ""
        self.svg.append(f'<line x1="{x1}" y1="{H-y1}" x2="{x2}" y2="{H-y2}" stroke="{color}" stroke-width="{width}"{dash}/>')

    def rect(self, x, y, w, h, fill=None, stroke=INK):
        self.c.setDash()
        self.c.setLineWidth(0.7)
        self.c.setStrokeColor(stroke)
        if fill:
            self.c.setFillColor(fill)
        self.c.rect(x, y, w, h, fill=int(fill is not None), stroke=1)
        self.svg.append(f'<rect x="{x}" y="{H-y-h}" width="{w}" height="{h}" stroke="{stroke}" fill="{fill or "none"}"/>')

    def text(self, x, y, s, size=11, color=INK):
        s = str(s)
        assert "\u2011" not in s and "\u2013" not in s
        font = CJK if any(ord(ch) > 127 for ch in s) else "Helvetica"
        self.c.setFont(font, size)
        self.c.setFillColor(color)
        self.c.drawString(x, y, s)
        self.svg.append(f'<text x="{x}" y="{H-y}" font-family="Microsoft YaHei, Noto Sans CJK SC, Arial, sans-serif" font-size="{size}" fill="{color}">{html.escape(s)}</text>')

    def para(self, x, y, s, width, size=12, leading=20):
        line = ""
        for ch in s:
            font = CJK if any(ord(c) > 127 for c in line + ch) else "Helvetica"
            if ch == "\n" or pdfmetrics.stringWidth(line + ch, font, size) > width:
                self.text(x, y, line, size)
                y -= leading
                line = "" if ch == "\n" else ch
            else:
                line += ch
        if line:
            self.text(x, y, line, size)
            y -= leading
        return y

    def new(self, title, subtitle):
        if self.page:
            self.end()
        self.page += 1
        self.svg = []
        self.text(32, H-40, title, 23)
        self.text(32, H-62, subtitle, 11, GREY)
        self.line(32, H-78, W-32, H-78, BLUE, 1.5)
        self.line(32, 42, W-32, 42, GREY)
        self.text(32, 25, "2026-10-04-C | Wiring reference - not PCB fabrication release", 9, GREY)
        self.text(W-130, 25, f"Sheet {self.page} / 11", 10, GREY)

    def end(self):
        (OUT / "svg" / f"sheet_{self.page:02d}.svg").write_text(
            f'<svg xmlns="http://www.w3.org/2000/svg" width="420mm" height="297mm" viewBox="0 0 {W} {H}">'
            + "\n".join(self.svg) + "</svg>", encoding="utf-8")
        self.c.showPage()

    def finish(self):
        assert self.page == 11
        self.end()
        self.c.save()

    def arrow(self, x1, y, x2, color=BLUE):
        self.line(x1, y, x2, y, color, 1.5)
        self.line(x2-7, y+4, x2, y, color, 1.5)
        self.line(x2-7, y-4, x2, y, color, 1.5)

    def ground(self, x, y):
        self.line(x, y, x, y-8, TEAL)
        for dy, length in ((8, 14), (11, 9), (14, 4)):
            self.line(x-length/2, y-dy, x+length/2, y-dy, TEAL)


def overview(d):
    d.new("FMC DDR3 无源转接板 - 连线核对图 Rev C", "J1 bottom mates VCU118 J2 | J2 top mates daughtercard J4 | Primary handoff: connections.md")
    d.text(35, 720, "母板参考输入：不经过转接板", 17, BLUE)
    blocks = [(35, "VCU118 U18 Si570", "250 MHz - program after power-up"),
              (320, "U157 Q2 / AW23, AW22", "J8 installed; LVDS input"),
              (605, "IBUFDS -> BUFG", "BUFGCE_X1Y120 / BACKBONE"),
              (890, "MIG + clk_wiz", "No adapter clock circuitry")]
    for x, a, b in blocks:
        d.rect(x, 617, 245, 75, LIGHT)
        d.text(x+12, 662, a, 14)
        d.text(x+12, 637, b, 10)
        if x != 890:
            d.arrow(x+245, 654, x+282)
    d.para(35, 586, "U18 上电默认 156.25 MHz；J8 开路选 300 MHz。每次断电重启后将 SCUI Si570_0 设为 250 MHz。MIG / XDC 均保持 250 MHz，约束不会给外部器件自动编程。", 1090, 13, 22)
    d.text(35, 510, "DRAM 时钟和总线：由 FPGA 输出，经两个 FMC 接口重排", 17, BLUE)
    for x, a, b in [(35, "FPGA MIG", "Bank 66/67, SLR1"), (320, "J1 - adapter bottom", "ASP-134488-01"),
                    (605, "J2 - adapter top", "ASP-134486-01"), (890, "Daughtercard J4 / U26", "MT41K512M16HA-125 config")]:
        d.rect(x, 407, 245, 75, LIGHT if x in (35, 890) else "#f4faf6")
        d.text(x+12, 450, a, 14)
        d.text(x+12, 426, b, 11)
        if x != 890:
            d.arrow(x+245, 444, x+282)
    d.text(35, 378, "DDR_CK_P: BC9 -> carrier J2.H4 -> adapter J1.H4 / J2.D11 -> daughter J4.D11 -> U26.J7", 13)
    d.text(35, 350, "DDR_CK_N: BC8 -> carrier J2.H5 -> adapter J1.H5 / J2.D12 -> daughter J4.D12 -> U26.K7", 13)
    d.text(35, 320, "CK = 800 MHz / 1600 MT/s. Never connect DDR CK to the 250 MHz reference input.", 13, RED)
    d.para(35, 280, "图纸使用全局同名网络：相同 DDR_x / 3V3 / VADJ / GND 标签在所有页互连。NC 用叉号表示，彼此不互连。第 2-6 页列出两个接口全部 800 针；第 7-8 页是 50 条 DDR 的球号、接点和子板网络核对表。", 1090, 13, 24)
    d.para(35, 196, "无晶振、无 PLL、无电平转换器。电源/地接通，其他接点不直通。母板 G6/G7 已停用；子板 G6/G7 分别是 ODT/RESET_n。复位 DNP 下拉及 RN28 条件详见第 9 页。", 1090, 13, 24)
    d.text(35, 90, "本次：原始连线 / 静态针脚核对；未改 Vivado / 时钟，未运行综合、实现、物理 DRC 或上板测试。", 13, RED)


def connector_sheets(d, manifest):
    for pair in ("AB", "CD", "EF", "GH", "JK"):
        d.new(f"接插件逐针原理图 - {pair[0]} / {pair[1]} 行", "Identical global net labels connect across sheets; NC crosses are independent, not a common net. Electrical pin numbers only.")
        for col, (row, ref) in enumerate([(pair[0], "J1"), (pair[0], "J2"), (pair[1], "J1"), (pair[1], "J2")]):
            x = 35 + col * 286
            d.text(x, 738, f"{ref}{row}  ({'BOTTOM' if ref == 'J1' else 'TOP'})", 14, BLUE)
            d.text(x, 720, "to VCU118 J2" if ref == "J1" else "to daughtercard J4", 10, GREY)
            d.rect(x, 74, 54, 635, "#f8fafb")
            for n in range(1, 41):
                pin = f"{row}{n}"
                y = 696 - (n-1) * 15.7
                p = manifest["contacts"][ref][pin]
                d.text(x+7, y-3, pin, 9.5)
                end = x+82
                net = p["net"]
                if net is None:
                    d.line(x+54, y, end, y, GREY)
                    d.line(end-3, y-3, end+3, y+3, GREY)
                    d.line(end-3, y+3, end+3, y-3, GREY)
                    d.text(end+10, y-3, "NC", 9.5, GREY)
                else:
                    color = TEAL if net == "GND" else (RED if net in ("3V3", "VADJ") else BLUE)
                    d.line(x+54, y, end, y, color)
                    d.text(end+8, y-3, net, 9.5, color)
                    if "partner" in p:
                        d.text(x+203, y-3, p["partner"], 8.5, GREY)
        d.text(35, 54, "C35/C37, D1: NC both sides. J1.G6/G7: NC. J2.B2/F2: GND. J2.G17/G26/H6: NC. J1.H2: GND.", 10, RED)


def mapping(d, doc, sigs, title, subtitle):
    d.new(title, subtitle)
    columns = [35, 178, 287, 406, 493, 554, 644]
    labels = ["Adapter global net", "J1 / carrier J2", "J2 / daughter J4", "FPGA ball", "Bank", "U26 ball", "Daughtercard original net"]
    d.rect(35, 712, W-70, 27, LIGHT)
    for x, label in zip(columns, labels):
        d.text(x+5, 720, label, 10)
    for i, s in enumerate(sigs):
        y = 697 - i * 21.5
        if i % 2 == 0:
            d.rect(35, y-7, W-70, 21.5, "#f8fafc", "#f8fafc")
        vals = [net_name(s["top_port"]), s["carrier_contact"], s["subcard_contact"], s["fpga_pin"], s["bank"], s["u26_ball"], s["subcard_net"]]
        for x, val in zip(columns, vals):
            d.text(x+5, y, val, 11)
    if len(sigs) == 28:
        d.text(35, 76, "ADDR/BA/control/CK: Bank 66. CK is FPGA output. RESET_n termination/population condition: sheet 9.", 11, RED)
    else:
        d.para(35, 174, "低字节 DQ0..7 / DM0 / DQS0：Bank 67 T0。高字节 DQ8..15 / DM1 / DQS1：Bank 67 T3。原始 GPIO 名 P/N 对单端数据没有差分含义；禁止依名字重新交换数据位。CK / DQS 正负极性保持本表。", 1090, 13, 23)


def power(d):
    d.new("电源、地、NC、可选复位下拉与 BOM", "No adapter active components. Verify actual daughtercard regulator, decoupling and termination population.")
    d.text(35, 733, "公共电源 / 地：全部同名针加入同一网，不按地针一对一独立接线", 15, BLUE)
    for y, label, a, b, color in [(672, "3V3", "J1 C39,D32,D36,D38,D40", "J2 C39,D32,D36,D38,D40", RED),
                                 (612, "VADJ = 1.5 V", "J1 E39,F40,G39,H40", "J2 E39,F40,G39,H40", RED),
                                 (552, "GND", "J1 162 contacts", "J2 157 contacts", TEAL)]:
        d.text(35, y+13, a, 12)
        d.text(650, y+13, b, 12)
        d.line(35, y, 1050, y, color, 1.6)
        d.text(455, y+8, label, 13, color)
    d.para(35, 521, "母板真实 VADJ/VCCO66/67 必须 1.5 V；共享 FMC Bank 的 C910 JTAG 仍是 LVCMOS18，另行解决电平兼容。子板 VDD/VDDQ=1.5 V，VTT/VREF=0.75 V。子板本地电源/跳线见 README，禁止并联不同来源。", 1090, 13, 22)
    d.text(35, 444, "可选上电复位下拉 - 默认不焊（DNP），先处理子板既有 RESET_n 终端", 15, BLUE)
    d.text(35, 398, "DDR_RESET_N", 12, BLUE)
    d.line(150, 401, 250, 401, BLUE, dashed=True)
    d.rect(250, 392, 64, 18)
    d.text(259, 417, "R_RESET", 11)
    d.text(256, 371, "4.7 kohm DNP", 11, RED)
    d.line(314, 401, 365, 401, TEAL, dashed=True)
    d.ground(365, 401)
    d.para(430, 417, "子板 RN28 的 RESET_n / GPIOR_N_16 有 39 ohm 到 VTT 支路。若焊装，4.7k 下拉不能可靠拉低（约 0.744 V）。确认该支路缺省/单独隔离后才可焊 R_RESET；不整颗拆掉 RN28，其他 ODT/A13/A9 支路仍需核对。", 700, 12, 21)
    d.text(35, 316, "强制隔离 / 不直通", 15, RED)
    d.para(35, 290, "双方 C35/C37 NC（母板 12 V / 子板 NC，不是地）；双方 D1 NC（PGOOD / 3V3_B）。J1 G6/G7 NC。J2 B2/F2 接 GND；J2 G17/G26/H6 NC。J1 C34/D35 接 GND，子板同号 NC。J1 H2 接地表示插卡。其他未用 I/O / MGT / I2C / 管理 JTAG 均 NC。", 1090, 12, 22)
    d.text(35, 206, "最小 BOM", 15, BLUE)
    d.text(35, 178, "J1  ASP-134488-01 x1 bottom   |   J2  ASP-134486-01 x1 top   |   R_RESET 4.7 kohm x1 DNP", 12)
    d.para(35, 149, "不加晶振、PLL 或缓冲芯片。电源去耦按 PDN / 实物需求决定，不在未知负载下编造参数。机械/屏蔽端子根据原厂封装接地，机械孔不默认视为电气针。图纸不是确认子板实物焊装完成的证明。", 1090, 12, 22)


def pcb(d):
    d.new("PCB 制作指导 - 全链路预算，非仅转接板等长", "800 MHz CK / 1600 MT/s target is conditional on complete three-board channel SI and timing verification.")
    y = 733
    sections = [
        ("1 机械及层叠", "上下各一个原厂 FMC；按料号 3D 模型核对高度、孔、定位柱、散热器净空和 A1。不要镜像针号，不同网络顶底焊盘不能共用孔。建议 8 层：SIG/GND/SIG/GND/POWER/SIG/GND/SIG；实际介质、铜厚、线宽由制造厂求解。"),
        ("2 连续回流与换层", "CK/DQS 差分；DQ/DM 单端，按字节分组，同字节除逃线尽量同层。参考地连续、不跨缝；差分同步换层/过孔数一致。回流地过孔距信号换层过孔 <=50 mil (1.27 mm)。不加长测试支路。"),
        ("3 阻抗不是统一 100 ohm", "UG583 数据参考主干单端 39 ohm +/-10%、DQS 76 ohm +/-10%，逃线 50/86 ohm。实际三板已有阻抗和子板 20/39/51/100 ohm 终端须纳入模型，再定 CK/CA/DQ/DQS 网类及制造阻抗券。参考值不是投板许可。"),
        ("4 补偿总延迟", "T总=T封装+T母板+T两次接口+T转接板+T子板。FPGA package min/max 用中值。取得既有板逐线长度/层叠/过孔与连接器模型，再补偿本板；不编造毫米等长值。")]
    for title, body in sections:
        d.text(35, y, title, 15, BLUE)
        y = d.para(35, y-26, body, 1090, 12, 20)-12
    d.text(35, y, "UG583 保守全链路参考：实际速度等级/速率可依据官方降额表重审，不能凭空放宽", 13, BLUE)
    y -= 29
    for a, b in [("DQ/DM to own DQS", "+/-10 ps"), ("CK P/N and DQS P/N", "2 ps each"),
                 ("CA/control to CK (RESET_n excluded)", "+/-8 ps"), ("CK to DQS", "-149..1796 ps, per guide definition"),
                 ("Data total including FPGA package", "<=1186 ps")]:
        d.text(40, y, a, 11)
        d.text(565, y, b, 11)
        y -= 22
    y = d.para(35, y-5, "数据参考最大 PCB 过孔数 2 是全链路，不是每块板 2 个；三板两接口的偏离须做完整 SI。VADJ/3V3 分网、12 V 隔离；电源铜宽/过孔按真实负载、压降、额定值、温升计算。Vivado DRC 不能证明此链路稳定校准。", 1090, 12, 20)
    assert y > 50, f"PCB sheet overflow: {y}"


def release(d, manifest):
    d.new("验证记录、投板检查与资料来源", "Revision C: original PDF pin/wire audit + static consistency checks only. No Vivado project changes.")
    d.text(35, 730, "已完成 / 未完成", 17, BLUE)
    d.para(35, 698, "本次从原始 PDF 独立核对母板 50 对针号/网络、子板全部 400 针引线与地总线及 50 对针号/GPIO 网络。DDR 位序未变；纠正子板 B2/F2 为 GND、G17/G26/H6 为 NC。800 针网表与 wrapper/XDC 一致；U26 球号、CK/DQS、供电和 RN28 已作图面复查。", 1090, 13, 23)
    d.para(35, 605, "本次仅修改连线资料和图纸，未修改 Vivado/XDC/时钟，未综合、实现、编程 U18 或上板测试。版本 B 的参考路径尚未做新物理 DRC；旧 validation 报告仅属于 A。未运行原生 EDA ERC；本图不是 PCB 制造放行。", 1090, 13, 23)
    d.text(35, 523, "投板及装配放行清单", 17, BLUE)
    d.para(35, 492, "原理图 ERC -> 800 接点网表比对 -> PCB DRC / 机械 3D 对接 -> 全链路延迟 / SI -> 制造输出。资料包括 Gerber/ODB++、钻孔、层叠/阻抗券、板框/孔/公差、BOM/坐标/装配图、电测网表与表面处理。当前仅原理图指导，无已布线 PCB / Gerber。", 1090, 13, 23)
    d.para(35, 397, "断电验收：50 条 DDR、公共电源地、每个 NC 隔离和相邻针短路。先实测 VADJ=1.5 V、DRAM 电源及复位低电平，再确认 J8 + U18=250 MHz；最后观察 MIG init_calib_complete，做全地址、跨字节、长时间读写和温度测试。", 1090, 13, 23)
    d.text(35, 299, "核对来源（完整链接与跳线表见 README）", 16, BLUE)
    for y, s in [(271, "VCU118 Rev2.0 schematic: sheets 11/12, 39/40/41, 44; official XDC; native connector GND symbol."),
                 (247, "Efinix fmc-ddr-gpio-card-schematics-v1.0(1).pdf: pages 3/4, actual exterior pin numbers."),
                 (223, "AMD PG150 DDR3 Pin Rules / cross-bank BUFG clocking; VCU118 UG1224 U18/J8/Q2."),
                 (199, "AMD UG583 DDR3 routing constraints, data topology and general memory routing guidelines."),
                 (175, "Samtec ASP-134486-01 / ASP-134488-01 drawings and mating/3D models: verify before PCB release.")]:
        d.text(35, y, s, 11)
    d.text(35, 131, "Netlist: 800 contacts / 53 connected nets / J1 GND 162, NC 179 / J2 GND 157, NC 184", 11)
    d.text(35, 106, "pinmap.json SHA256: " + manifest["source_sha256"], 10, GREY)
    d.text(35, 79, "用 EDA 逐针网表原则与 PDF 渲染核对整理；不是已验证的 EasyEDA 原生工程或已投板 PCB。", 11, RED)


def main():
    doc = json.loads((ROOT / "pinmap.json").read_text(encoding="utf-8-sig"))
    manifest = make_manifest(doc)
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "adapter_netlist.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    write_connections(doc, manifest)
    d = Drawing()
    overview(d)
    connector_sheets(d, manifest)
    controls = [s for s in doc["signals"] if not re.search(r"_(dq|dm|dqs_[pn])\[", s["top_port"])]
    data = [s for s in doc["signals"] if s not in controls]
    assert len(controls) == 28 and len(data) == 22
    mapping(d, doc, controls, "DDR 地址、控制及 CK 对照表 - 28 根", "Adapter J1 = carrier J2 contacts; adapter J2 = daughtercard J4 contacts. FPGA ball is not FMC contact.")
    mapping(d, doc, data, "DDR 数据字节对照表 - 22 根", "Keep DQ/DM/DQS byte grouping and differential polarity. No data bit swapping implied by GPIO names.")
    power(d)
    pcb(d)
    release(d, manifest)
    d.finish()
    print(json.dumps({"pdf": str(PDF), "pages": d.page, "nets": manifest["net_count"], "stats": manifest["statistics"]}, ensure_ascii=False))


if __name__ == "__main__":
    main()
