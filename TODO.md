# Maintenance pass

- [x] Fix test runners. `make test`, `make test-verbose`, `make test-count`
  and the interactive runner must cover all eight test suites.
- [x] Add CI. Check Emacs 30.1 and 31.1 with both parser paths on pushes,
  pull requests and a monthly schedule.
- [x] Fix packaging and quality checks. Build a versioned, installable tarball
  and fail when compilation or package lint reports a problem.
- [x] Publish a release. Version and changelog updated. The tested package is
  available as [1.1.0](https://github.com/rjprins/markdown-modern/releases/tag/1.1.0).
- [x] Improve installation and visibility. Test fresh installs, document
  tree-sitter setup, refresh the screenshot and build the MELPA recipe.

# Backlog

Track future work in [GitHub Issues](https://github.com/rjprins/markdown-modern/issues).
Tracked items are possibilities, not delivery commitments.

- [Consider removing the regex fallback (#4)](https://github.com/rjprins/markdown-modern/issues/4)
- [Add ordered-list renumbering (#5)](https://github.com/rjprins/markdown-modern/issues/5)
- [Reveal rendered math at point for editing (#6)](https://github.com/rjprins/markdown-modern/issues/6)
- [Audit reveal support for display-rendered elements (#7)](https://github.com/rjprins/markdown-modern/issues/7)
- [Consider cell-level reveal when editing tables (#8)](https://github.com/rjprins/markdown-modern/issues/8)
- [Render inline Markdown inside table cells (#9)](https://github.com/rjprins/markdown-modern/issues/9)
- [Consider horizontal scrolling for an overlong active table cell (#10)](https://github.com/rjprins/markdown-modern/issues/10)

# Completed enhancements

- Reflow ordinary paragraph source newlines as spaces while preserving explicit
  hard breaks and block boundaries.
- Code-block syntax highlighting wired up (1.0.1).
- Reveal line-leading markers (bullets, ordered, blockquote) and heading `#`
  markers at the heading's size (1.1.0).
- Task checkboxes as interactive widgets: no reveal; `SPC` toggles,
  `Backspace`/`Delete` removes the checkbox (1.1.0).
- Keep tables rendered while editing — implemented as row-level reveal with the
  active row drawn as an editable, pixel-aligned grid row (valign-style), plus
  fit-to-window table sizing so tables never wrap (1.1.0).
