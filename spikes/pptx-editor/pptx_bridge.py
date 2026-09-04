#!/usr/bin/env python3
"""Minimal PPTX geometry bridge for the Emacs feasibility spike.

Reads slide geometry without rewriting the package and moves/resizes top-level
shapes by patching only the selected slide XML member.  All other ZIP members
are copied byte-for-byte.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import tempfile
import zipfile
from pathlib import Path
from xml.etree import ElementTree as ET

EMU_PER_INCH = 914400
P_NS = "http://schemas.openxmlformats.org/presentationml/2006/main"
A_NS = "http://schemas.openxmlformats.org/drawingml/2006/main"
SUPPORTED_TAGS = {"sp", "pic", "graphicFrame", "cxnSp"}


def local_name(tag: str) -> str:
    return tag.rsplit("}", 1)[-1] if "}" in tag else tag


def inches(value: int) -> float:
    return value / EMU_PER_INCH


def presentation_size(archive: zipfile.ZipFile) -> tuple[int, int]:
    root = ET.fromstring(archive.read("ppt/presentation.xml"))
    size = root.find(f"{{{P_NS}}}sldSz")
    if size is None:
        raise ValueError("presentation has no slide size")
    return int(size.attrib["cx"]), int(size.attrib["cy"])


def shape_geometry(element: ET.Element) -> tuple[int, int, int, int] | None:
    xfrm = next((node for node in element.iter() if local_name(node.tag) == "xfrm"), None)
    if xfrm is None:
        return None
    off = next((node for node in xfrm if local_name(node.tag) == "off"), None)
    ext = next((node for node in xfrm if local_name(node.tag) == "ext"), None)
    if off is None or ext is None:
        return None
    return int(off.attrib["x"]), int(off.attrib["y"]), int(ext.attrib["cx"]), int(ext.attrib["cy"])


def inspect_deck(path: str | Path, slide_number: int) -> dict:
    member = f"ppt/slides/slide{slide_number}.xml"
    with zipfile.ZipFile(path, "r") as archive:
        slide_w, slide_h = presentation_size(archive)
        root = ET.fromstring(archive.read(member))
    sp_tree = root.find(f".//{{{P_NS}}}spTree")
    if sp_tree is None:
        raise ValueError(f"slide {slide_number} has no shape tree")
    shapes = []
    for element in list(sp_tree):
        kind = local_name(element.tag)
        if kind not in SUPPORTED_TAGS:
            continue
        c_nv_pr = next((node for node in element.iter() if local_name(node.tag) == "cNvPr"), None)
        geom = shape_geometry(element)
        if c_nv_pr is None or geom is None:
            continue
        x, y, w, h = geom
        texts = [node.text or "" for node in element.iter() if local_name(node.tag) == "t"]
        shapes.append({
            "id": int(c_nv_pr.attrib["id"]),
            "name": c_nv_pr.attrib.get("name", ""),
            "type": kind,
            "left": inches(x),
            "top": inches(y),
            "width": inches(w),
            "height": inches(h),
            "text": " ".join(t.strip() for t in texts if t.strip())[:160],
        })
    return {
        "slide": slide_number,
        "slide_width": inches(slide_w),
        "slide_height": inches(slide_h),
        "shapes": shapes,
    }


def _shape_block(text: str, shape_id: int) -> tuple[int, int, str]:
    marker = re.search(
        r'<(?P<pfx>[A-Za-z_][\w.-]*):cNvPr\b[^>]*\bid="%d"[^>]*>' % shape_id,
        text,
    )
    if not marker:
        raise ValueError(f"shape id {shape_id} not found")
    pfx = marker.group("pfx")
    starts: list[tuple[int, str]] = []
    for tag in SUPPORTED_TAGS:
        for match in re.finditer(r'<%s:%s\b' % (re.escape(pfx), tag), text[: marker.start()]):
            starts.append((match.start(), tag))
    if not starts:
        raise ValueError(f"shape id {shape_id} is not a supported top-level shape")
    start, tag = max(starts)
    closing = f"</{pfx}:{tag}>"
    end = text.find(closing, marker.end())
    if end < 0:
        raise ValueError("shape closing tag not found")
    end += len(closing)
    return start, end, text[start:end]


def _replace_int_attr(tag: str, attr: str, value: int) -> str:
    pattern = re.compile(r'(\b%s=")-?\d+(\")' % re.escape(attr))
    result, count = pattern.subn(lambda m: f"{m.group(1)}{value}{m.group(2)}", tag, count=1)
    if count != 1:
        raise ValueError(f"attribute {attr} not found")
    return result


def patch_geometry(data: bytes, shape_id: int, dx: float, dy: float, dw: float = 0.0, dh: float = 0.0) -> bytes:
    text = data.decode("utf-8")
    start, end, block = _shape_block(text, shape_id)
    xfrm = re.search(r'<(?:[A-Za-z_][\w.-]*):xfrm\b.*?</(?:[A-Za-z_][\w.-]*):xfrm>', block)
    if not xfrm:
        raise ValueError("shape transform not found")
    transform = xfrm.group(0)
    off = re.search(r'<(?:[A-Za-z_][\w.-]*):off\b[^>]*/?>', transform)
    ext = re.search(r'<(?:[A-Za-z_][\w.-]*):ext\b[^>]*/?>', transform)
    if not off or not ext:
        raise ValueError("shape offset/extent not found")

    def attr(tag: str, name: str) -> int:
        match = re.search(r'\b%s="(-?\d+)"' % re.escape(name), tag)
        if not match:
            raise ValueError(f"attribute {name} not found")
        return int(match.group(1))

    off_tag, ext_tag = off.group(0), ext.group(0)
    nx = attr(off_tag, "x") + round(dx * EMU_PER_INCH)
    ny = attr(off_tag, "y") + round(dy * EMU_PER_INCH)
    nw = attr(ext_tag, "cx") + round(dw * EMU_PER_INCH)
    nh = attr(ext_tag, "cy") + round(dh * EMU_PER_INCH)
    if nw <= 0 or nh <= 0:
        raise ValueError("resize would make shape non-positive")
    patched_off = _replace_int_attr(_replace_int_attr(off_tag, "x", nx), "y", ny)
    patched_ext = _replace_int_attr(_replace_int_attr(ext_tag, "cx", nw), "cy", nh)
    patched_transform = transform[: off.start()] + patched_off + transform[off.end() :]
    ext2 = re.search(r'<(?:[A-Za-z_][\w.-]*):ext\b[^>]*/?>', patched_transform)
    assert ext2 is not None
    patched_transform = patched_transform[: ext2.start()] + patched_ext + patched_transform[ext2.end() :]
    patched_block = block[: xfrm.start()] + patched_transform + block[xfrm.end() :]
    return (text[:start] + patched_block + text[end:]).encode("utf-8")


def edit_package(src: str | Path, dst: str | Path, slide_number: int, shape_id: int, dx: float, dy: float, dw: float = 0.0, dh: float = 0.0) -> None:
    src, dst = Path(src), Path(dst)
    member = f"ppt/slides/slide{slide_number}.xml"
    with zipfile.ZipFile(src, "r") as zin, zipfile.ZipFile(dst, "w") as zout:
        found = False
        for item in zin.infolist():
            payload = zin.read(item.filename)
            if item.filename == member:
                payload = patch_geometry(payload, shape_id, dx, dy, dw, dh)
                found = True
            zout.writestr(item, payload)
        if not found:
            raise ValueError(f"slide {slide_number} not found")


def edit_in_place(path: str | Path, slide_number: int, shape_id: int, dx: float, dy: float, dw: float = 0.0, dh: float = 0.0) -> None:
    path = Path(path)
    fd, tmp_name = tempfile.mkstemp(prefix=path.stem + "-", suffix=".pptx", dir=path.parent)
    os.close(fd)
    tmp = Path(tmp_name)
    try:
        edit_package(path, tmp, slide_number, shape_id, dx, dy, dw, dh)
        os.replace(tmp, path)
    finally:
        tmp.unlink(missing_ok=True)


def render_slide(path: str | Path, output: str | Path, slide_number: int, soffice: str, pdftoppm: str) -> None:
    path, output = Path(path).resolve(), Path(output).resolve()
    with tempfile.TemporaryDirectory(prefix="p3-pptx-") as td_name:
        td = Path(td_name)
        subprocess.run([soffice, "--headless", "--convert-to", "pdf", "--outdir", str(td), str(path)], check=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        pdf = td / f"{path.stem}.pdf"
        prefix = td / "slide"
        subprocess.run([pdftoppm, "-png", "-f", str(slide_number), "-singlefile", "-r", "120", str(pdf), str(prefix)], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        shutil.copyfile(str(prefix) + ".png", output)


def main() -> None:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    inspect_p = sub.add_parser("inspect")
    inspect_p.add_argument("pptx")
    inspect_p.add_argument("--slide", type=int, default=1)
    edit_p = sub.add_parser("edit")
    edit_p.add_argument("pptx")
    edit_p.add_argument("--slide", type=int, default=1)
    edit_p.add_argument("--shape-id", type=int, required=True)
    for name in ("dx", "dy", "dw", "dh"):
        edit_p.add_argument(f"--{name}", type=float, default=0.0)
    render_p = sub.add_parser("render")
    render_p.add_argument("pptx")
    render_p.add_argument("output")
    render_p.add_argument("--slide", type=int, default=1)
    render_p.add_argument("--soffice", default="libreoffice")
    render_p.add_argument("--pdftoppm", default="pdftoppm")
    args = parser.parse_args()
    if args.command == "inspect":
        print(json.dumps(inspect_deck(args.pptx, args.slide), indent=2))
    elif args.command == "edit":
        edit_in_place(args.pptx, args.slide, args.shape_id, args.dx, args.dy, args.dw, args.dh)
    else:
        render_slide(args.pptx, args.output, args.slide, args.soffice, args.pdftoppm)


if __name__ == "__main__":
    main()
