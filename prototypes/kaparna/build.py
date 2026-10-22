#!/usr/bin/env python3
# PROTOTYPE - NOT FOR PRODUCTION
# Question: Är det roligt att kapa skepp med Clash-liknande anfall?
# Date: 2026-10-22
#
# Bakar ihop index.html + css/ + js/ till en enda fil (kaparna.html) som går att
# skicka till någon och öppna med dubbelklick.
#
#   python3 build.py                     -> kaparna.html
#   python3 build.py --fragment ut.html  -> sidinnehåll utan <html>/<head>/<body> (för webbvärdar som lägger till skelettet själva)
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent


def bundle() -> str:
    html = (ROOT / "index.html").read_text(encoding="utf-8")
    css = (ROOT / "css" / "style.css").read_text(encoding="utf-8")
    html = html.replace('<link rel="stylesheet" href="css/style.css">', "<style>\n" + css + "\n</style>")

    def inline(m: re.Match) -> str:
        return "<script>\n" + (ROOT / m.group(1)).read_text(encoding="utf-8") + "\n</script>"

    html = re.sub(r'<script src="(js/[^"]+)"></script>', inline, html)
    assert 'src="js/' not in html and 'href="css/' not in html, "något blev inte inbakat"
    return html


def fragment(html: str) -> str:
    # Plocka bort dokumentskelettet; <title> först så att den hittas direkt.
    for pat in [r"<!doctype html>\s*", r"<html[^>]*>\s*", r"</html>\s*", r"<head>\s*", r"</head>\s*", r"<body>\s*", r"</body>\s*",
                r'<meta charset="utf-8">\s*', r'<meta name="viewport"[^>]*>\s*']:
        html = re.sub(pat, "", html, flags=re.I)
    return html.strip() + "\n"


if __name__ == "__main__":
    out = bundle()
    (ROOT / "kaparna.html").write_text(out, encoding="utf-8")
    print(f"kaparna.html: {len(out) // 1024} kB")
    if "--fragment" in sys.argv:
        dest = pathlib.Path(sys.argv[sys.argv.index("--fragment") + 1])
        dest.write_text(fragment(out), encoding="utf-8")
        print(f"{dest}: fragment skrivet")
