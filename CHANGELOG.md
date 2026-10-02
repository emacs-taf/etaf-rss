# Changelog

All notable user-visible changes to ETAF RSS are recorded here. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the
project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.0] - 2026-10-03

### Added

- A complete RSS client as one ETAF text application: RSS 2.0, Atom and JSON
  Feed subscriptions (including feed autodiscovery from a site page), one
  local JSON store, all/unread/starred scopes and per-feed or per-folder
  lists.
- A reading pane that renders article HTML as wrapped blocks (headings,
  paragraphs, quotes, lists, code, table rows and collected links) and opens
  the original in the browser.
- Read and starred state with optimistic toggles, mark-all-read and
  mark-above-read, and starred articles that survive unsubscribing.
- Case-insensitive search over titles, summaries and bodies with snippets.
- OPML import and export, with folders.
- Conditional background refresh (ETag / Last-Modified), one request at a
  time, per-feed error reporting, an idle auto-refresh timer and a manual
  every-subscription refresh.
- Three responsive layouts, dark and light palettes published as ETAF UI
  theme tokens, and full keyboard, mouse and wheel navigation.
- Headless sessions with an injectable client, a public API inventory in the
  entry Commentary, and acceptance scenarios that exercise the real service
  layer over `file://` fixtures without a network.
