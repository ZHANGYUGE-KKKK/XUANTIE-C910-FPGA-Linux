"""Read the source PDF's exterior J4 labels and actual pin/wire/NC geometry.

This is intentionally independent of the generated drawing/netlist. Requires
pdfplumber; tied to the bundled v1.0 schematic, not a generic PDF netlist reader.
"""
from pathlib import Path
import json
import re
import pdfplumber

ROOT = Path(__file__).resolve().parent
SOURCE = ROOT.parent / "fmc-ddr-gpio-card-schematics-v1.0(1).pdf"
# Each bus was traced to its local ground symbol in the rendered source.
GROUND_BUS_X = dict(A=64.56, B=113.88, C=131.52, D=272.64, E=286.8,
                    F=389.16, G=406.8, H=565.56, J=576.12, K=632.52)


def read_contacts():
    with pdfplumber.open(SOURCE) as pdf:
        p = pdf.pages[3]
        words = p.extract_words(extra_attrs=["non_stroking_color"])
        labels = [w for w in words if re.fullmatch(r"[ABCDEFGHJK][0-9]{1,2}", w["text"])
                  and w["non_stroking_color"] == (0., 0., 0.) and w["top"] < 178 and w["x0"] < 640]
        curves = p.curves
        leads = [c for c in curves if c["stroking_color"] == (.668, .535, .266)
                 and c["height"] < .01 and 6.9 < c["width"] < 7.2]
        crosses = [c for c in curves if c["stroking_color"] == (.5, .25, 0.)
                   and 2 < c["height"] < 2.5 and 2 < c["width"] < 2.5]
        wires = [c for c in curves if c["stroking_color"] == (.258, 0., 1.)
                 and c["height"] < .01]
        contacts = {}
        for w in labels:
            matched = [c for c in leads if abs(c["top"] - w["bottom"] - .16) < .03
                       and c["x0"] < w["x1"] and c["x1"] > w["x0"]]
            assert len(matched) == 1, (w, matched)
            lead = matched[0]
            # Exterior endpoint lies outside the black pin label.
            side = "left" if w["text"][0] in "ACEGJ" else "right"
            x = lead["x0"] if side == "left" else lead["x1"]
            y = lead["top"]
            nc = any(abs((c["x0"] + c["x1"]) / 2 - x) < .15
                     and abs((c["top"] + c["bottom"]) / 2 - y) < .1 for c in crosses)
            attached = [c for c in wires if abs(c["top"] - y) < .02
                        and (abs(c["x0"] - x) < .02 or abs(c["x1"] - x) < .02)]
            assert not (nc and attached), (w["text"], nc, attached)
            assert w["text"] not in contacts, w["text"]
            contacts[w["text"]] = {"nc": nc or not attached, "nc_cross": nc, "endpoint": (x, y),
                                   "wires": [(c["x0"], c["x1"]) for c in attached]}
            contacts[w["text"]]["ground"] = any(
                abs(v - GROUND_BUS_X[w["text"][0]]) < .02
                for c in attached for v in (c["x0"], c["x1"]))
            net_words = [v["text"] for v in words if v["text"].startswith("GPIO")
                         and abs(v["bottom"] - y + .64) < .03
                         and any(c["x0"] <= v["x0"] <= c["x1"] for c in attached)]
            contacts[w["text"]]["gpio_net"] = net_words
        assert len(contacts) == 400, len(contacts)
        return contacts


if __name__ == "__main__":
    contacts = read_contacts()
    doc = json.loads((ROOT / "pinmap.json").read_text(encoding="utf-8"))
    g = doc["ground_contacts"]
    standard = {f"{r}{n}" for r, ns in g["standard_carrier_ground_by_row"].items() for n in ns}
    actual = {pin for pin, item in contacts.items() if item["ground"]}
    expected = (standard - set(g["subcard_remove_from_standard_ground"])) | set(g["subcard_add_to_ground"])
    assert actual == expected, ("SOURCE ground differs", sorted(actual - expected), sorted(expected - actual))
    for s in doc["signals"]:
        pin = contacts[s["subcard_contact"]]
        assert not pin["ground"] and not pin["nc"], s
        assert pin["gpio_net"] == [s["subcard_net"]], (s, pin)
    carrier_pdf = ROOT.parents[1] / "VCU118" / "HW-U1-VCU118_REV2_0_SCHEMATIC_7-14-2017.pdf"
    with pdfplumber.open(carrier_pdf) as pdf:
        carrier_words = {r: pdf.pages[i].extract_words() for i, rows in
                         [(38, "CD"), (39, "G"), (40, "H")] for r in rows}
        for s in doc["signals"]:
            words = carrier_words[s["carrier_contact"][0]]
            pairs = [(pin, net) for pin in words if pin["text"] == s["carrier_contact"]
                     for net in words if net["text"] == s["carrier_net"]
                     and abs(net["top"] - pin["top"]) < .03
                     and 0 <= net["x0"] - pin["x1"] < 30]
            assert len(pairs) == 1, ("Carrier source pin/net mismatch", s, pairs)
    print(f"PASS: source PDF exterior J4 geometry parsed for all {len(contacts)} contacts.")
    print(f"PASS: all {len(actual)} daughter ground contacts traced to source ground buses.")
    print("PASS: all 50 daughter pin/GPIO nets and carrier J2 pin/net pairs match source PDFs.")
    print("NOTE: U26 ball mapping, power selectors and reset termination require separate drawing review;")
    print("      this parser does not certify PCB routing, populated hardware or SI.")
