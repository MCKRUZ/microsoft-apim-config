#!/usr/bin/env python
# ============================================================================
# build-site.py — render every docs/**/*.md into a styled HTML subpage for the
# GitHub Pages site. Markdown stays the source of truth; this generates the HTML
# next to it (committed, since Pages serves static with .nojekyll).
#
#   python scripts/build-site.py
#
# - .md links are rewritten to .html (stay in-site); source-file links
#   (.bicep/.xml/.json/.sh/.ps1/.yml) point at the GitHub blob.
# - ```mermaid fences render as Mermaid diagrams.
# - one index.html per docs directory, listing its pages.
# index.html (the landing page) is hand-authored and NOT touched here.
# ============================================================================
import os
import re
import posixpath
from markdown_it import MarkdownIt

MD = MarkdownIt("commonmark").enable(["table", "strikethrough"])  # CommonMark + GFM tables (no linkify dep)


def github_slug(text):
    # Match GitHub's slugify: lowercase, drop punctuation, each whitespace char -> a
    # hyphen (NOT collapsed — a spaced em-dash yields "--", which authored links rely on).
    t = re.sub(r'<[^>]+>', '', text).replace('&amp;', '&')
    t = re.sub(r'[^\w\s-]', '', t.lower())
    return re.sub(r'\s', '-', t.strip())


def add_heading_ids(html_str):
    return re.sub(r'<h([2-6])>(.*?)</h\1>',
                  lambda m: f'<h{m.group(1)} id="{github_slug(m.group(2))}">{m.group(2)}</h{m.group(1)}>',
                  html_str, flags=re.DOTALL)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BLOB = 'https://github.com/MCKRUZ/microsoft-apim-config/blob/main/'
REPO = 'https://github.com/MCKRUZ/microsoft-apim-config'

SRC_EXT = ('.bicep', '.xml', '.json', '.sh', '.ps1', '.yml', '.yaml',
           '.gitignore', '.gitattributes', '.css', '.py')


def topbar(root):
    return f'''<div class="topbar" role="navigation" aria-label="Site">
  <a class="home" href="{root}index.html">Home</a>
  <a href="{root}docs/enterprise/target-architecture.html">Architecture</a>
  <a href="{root}docs/enterprise/flag-status.html">Flags</a>
  <details class="ref"><summary>Phases &#9662;</summary><div class="menu">
    <a href="{root}docs/runbooks/network-isolation.html">1 · Network isolation</a>
    <a href="{root}docs/runbooks/ci-cd-pipeline.html">2 · CI/CD guardrails</a>
    <a href="{root}docs/runbooks/secops-loop.html">3 · SecOps loop</a>
    <a href="{root}docs/runbooks/federation.html">4 · Federation</a>
    <a href="{root}docs/runbooks/reliability.html">5 · Reliability</a>
    <a href="{root}docs/runbooks/multi-provider.html">6 · Multi-provider</a>
  </div></details>
  <details class="ref"><summary>Reference &#9662;</summary><div class="menu">
    <a href="{root}docs/index.html">All docs</a>
    <a href="{root}docs/caveats.html">Caveats</a>
    <a href="{root}docs/enterprise/capability-toggles.html">Capability toggles</a>
    <a href="{root}docs/enterprise/compliance-mapping.html">Compliance mapping</a>
    <a href="{root}docs/adr/index.html">ADRs</a>
    <a href="{root}docs/runbooks/deploy.html">Deploy</a>
  </div></details>
  <a class="sp" href="{REPO}">GitHub ↗</a>
</div>'''


def page(root, title, crumb, body, edit_url, mermaid):
    mer = ('\n<script type="module">import mermaid from '
           '"https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs";'
           'mermaid.initialize({startOnLoad:true,theme:"neutral"});</script>'
           ) if mermaid else ''
    edit = f'<p class="edit">Source: <a href="{edit_url}">edit this page on GitHub ↗</a></p>' if edit_url else ''
    return f'''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>{title} · APIM Agentic Governance</title>
<link rel="stylesheet" href="{root}assets/site.css">
</head>
<body>
{topbar(root)}
<header class="dochead"><div class="wrap">
  <p class="crumb">{crumb}</p>
  <h1>{title}</h1>
  {edit}
</div></header>
<main class="content"><div class="wrap">
{body}
</div></main>
<footer class="foot"><div class="wrap">
  MCKRUZ · APIM Agentic Governance Golden Copy ·
  <a href="{root}index.html">Home</a> ·
  <a href="{REPO}">Source on GitHub ↗</a>
</div></footer>
{mer}
</body>
</html>'''


def rel_prefix(relpath):
    d = posixpath.dirname(relpath)
    return '../' * (len(d.split('/')) if d else 0)


def md_title(text, fallback):
    for line in text.splitlines():
        if line.startswith('# '):
            return line[2:].strip()
    return fallback


def rewrite_links(html, md_dir):
    def repl(m):
        href = m.group(1)
        if re.match(r'^(https?:|mailto:|#)', href):
            return f'href="{href}"'
        path, _, anchor = href.partition('#')
        anchor = ('#' + anchor) if anchor else ''
        if not path:
            return f'href="{href}"'
        base = posixpath.basename(path)
        if path.endswith('.md'):
            return f'href="{path[:-3]}.html{anchor}"'
        if '.' not in base:            # directory link -> its index.html
            return f'href="{href}"'
        if path.endswith(SRC_EXT):     # source file -> github blob
            repo_rel = posixpath.normpath(posixpath.join(md_dir, path))
            return f'href="{BLOB}{repo_rel}{anchor}"'
        return f'href="{href}"'
    return re.sub(r'href="([^"]+)"', repl, html)


def extract_mermaid(text, store):
    def repl(m):
        # Mermaid 11 rejects "\n" line breaks in labels — use <br/>.
        store.append(m.group(1).replace('\\n', '<br/>'))
        return f'\n\nMERMAIDBLOCK{len(store) - 1}ENDMERMAID\n\n'
    return re.sub(r'```mermaid\n(.*?)```', repl, text, flags=re.DOTALL)


def crumb_for(relpath, root):
    parts = relpath.split('/')
    out = [f'<a href="{root}index.html">Home</a>']
    for i, seg in enumerate(parts[:-1]):
        depth_back = '../' * (len(parts) - 2 - i)
        out.append(f'<a href="{depth_back}index.html">{seg}</a>')
    return ' / '.join(out)


def convert(md_relpath):
    abs_md = os.path.join(ROOT, md_relpath)
    with open(abs_md, encoding='utf-8') as f:
        text = f.read()
    md_dir = posixpath.dirname(md_relpath)
    root = rel_prefix(md_relpath)
    title = md_title(text, posixpath.basename(md_relpath))

    mer_store = []
    text = extract_mermaid(text, mer_store)
    html = MD.render(text)
    # strip the leading <h1> (title already shown in the page header), then add anchor ids
    html = re.sub(r'^<h1[^>]*>.*?</h1>\s*', '', html, count=1, flags=re.DOTALL)
    html = add_heading_ids(html)
    for i, block in enumerate(mer_store):
        html = html.replace(f'<p>MERMAIDBLOCK{i}ENDMERMAID</p>',
                            f'<div class="mermaid">{block}</div>')
    html = rewrite_links(html, md_dir)

    out_rel = md_relpath[:-3] + '.html'
    page_html = page(root, title, crumb_for(md_relpath, root), html,
                     BLOB + md_relpath, bool(mer_store))
    with open(os.path.join(ROOT, out_rel), 'w', encoding='utf-8') as f:
        f.write(page_html)
    return out_rel, title


def write_dir_index(dir_rel, entries, subdirs):
    root = '../' * len(dir_rel.split('/'))
    rows = []
    for sub in sorted(subdirs):
        rows.append(f'<a class="item" href="{sub}/index.html"><div class="t">{sub}/</div>'
                    f'<div class="d">section index</div></a>')
    for fname, title in sorted(entries):
        rows.append(f'<a class="item" href="{fname}"><div class="t">{title}</div>'
                    f'<div class="d">{fname}</div></a>')
    body = f'<div class="dirlist">{"".join(rows)}</div>'
    title = 'Documentation' if dir_rel == 'docs' else f'{dir_rel}'
    crumb = crumb_for(dir_rel + '/x', root)  # reuse: treats dir as parent chain
    page_html = page(root, title, crumb, body, None, False)
    with open(os.path.join(ROOT, dir_rel, 'index.html'), 'w', encoding='utf-8') as f:
        f.write(page_html)


def main():
    md_files = []
    for dirpath, _, files in os.walk(os.path.join(ROOT, 'docs')):
        for fn in files:
            if fn.endswith('.md'):
                rel = os.path.relpath(os.path.join(dirpath, fn), ROOT).replace('\\', '/')
                md_files.append(rel)

    by_dir = {}
    for rel in sorted(md_files):
        out_rel, title = convert(rel)
        d = posixpath.dirname(rel)
        by_dir.setdefault(d, []).append((posixpath.basename(out_rel), title))

    # directory indexes (skip dirs that already ship an index.md)
    all_dirs = set(by_dir)
    for d in sorted(all_dirs, key=lambda x: -x.count('/')):
        entries = [e for e in by_dir[d] if e[0] != 'index.html']
        subdirs = [posixpath.basename(x) for x in all_dirs if posixpath.dirname(x) == d]
        write_dir_index(d, entries, subdirs)

    print(f'built {len(md_files)} pages + {len(all_dirs)} directory indexes')


if __name__ == '__main__':
    main()
