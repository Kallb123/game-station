# Vendored skills

The `caveman/`, `caveman-compress/` and `caveman-review/` skills in this directory are vendored,
unmodified, from an upstream project.

| | |
|---|---|
| Upstream | https://github.com/JuliusBrussee/caveman |
| Version | v2.0.0 (commit `a0109974ea3258a14aadaef1ed1f8ff2837d30d5`) |
| Vendored | 2026-08-11 |
| Paths taken | `skills/caveman/`, `skills/caveman-compress/`, `skills/caveman-review/` |
| License | MIT — `skills/` is MIT per upstream `LICENSING.md` |

Upstream ships 20 skills; these three are the ones this repository uses. The others are available
at the upstream URL above — note that `caveman-optimize` and `caveman-evidence-review` are Caveman
Cloud operator tools requiring a logged-in Caveman CLI, not local document tools, despite their
names.

`caveman-plan/` is **not** vendored — there is no upstream skill by that name. It was written for
this repository and is covered by this repository's own license, as is `../agents/caveman.md`.

Only the upstream `skills/` tree is vendored. The upstream compression engine, proxy, and MCP
binaries (`engine/`, `proxy/`, `mcp/`, `shrink/`, `browse/`, `shared/platform/`) are Business
Source License 1.1 and are deliberately **not** included — nothing here is BSL-licensed.

Local changes: upstream `README.md` files were dropped (they duplicate the upstream repo's docs).
`SKILL.md` and `scripts/` are byte-identical to upstream. To update, re-copy those two directories
from a newer upstream tag and bump the table above.

`../agents/caveman.md` is **not** vendored — it is written for this repository and is covered by
this repository's own license.

## `caveman-compress` runtime requirement

`caveman-compress` shells out to a second model call (`python3 -m scripts <file>`), using
`ANTHROPIC_API_KEY` if set and otherwise the `claude --print` CLI. It needs Python 3 and one of
those two on the machine. It writes its backup out of tree, under
`$XDG_DATA_HOME/caveman-compress/backups/` (`%LOCALAPPDATA%\caveman-compress\backups\` on
Windows), so the pre-compression original is not in the repo — commit before running it if you
want the original recoverable from git.

Note that it compresses to full caveman register. For documents that stay in the repo, prefer the
`caveman` agent at `lite`, which keeps ordinary prose (see the "Boundaries" section of
`caveman/SKILL.md`: persisted documents are written as normal prose).

---

MIT License

Copyright (c) 2026 Julius Brussee

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
