# etaf-rss manual

This manual describes the supported workflows of the ETAF RSS reader. The
package entry `etaf-rss.el` is the authoritative API inventory; this document
shows how the workflows compose.

## Sessions and the buffer

`etaf-rss-create` builds a session: a store-backed reader with no buffer and
no network activity until it is refreshed. `etaf-rss-open` mounts it in
`etaf-rss-buffer-name` and fills the selected window; `etaf-rss-close`
unmounts it and kills the buffer. Closing releases the refresh timer and any
in-flight request, and the same session can be mounted again later. A session
passed to `etaf-rss-open` keeps its scope, selection and open article, which
makes it usable as a persistent reader across frames.

To embed the reader in a larger ETAF view, mount `etaf-rss-view` yourself:

```elisp
(etaf-mount buffer (etaf-rss-view (etaf-rss-create)))
```

## Subscriptions

- `a` asks for an address. Anything with a scheme works; a bare host becomes
  `https://host`. The document is fetched and parsed before it is stored, so
  a wrong address is reported in the status line without changing the reader.
  If the address is a site page rather than a feed, the page's advertised
  feed links (`<link rel="alternate" type="application/rss+xml">` and
  friends) are tried next. The second prompt files the subscription under a
  folder; leave it empty for the top level.
- `d` unsubscribes the feed of the current scope after a confirmation.
  Starred articles of that feed stay in the reader; everything else goes.
- Clicking a folder's chevron collapses and expands it. `etaf-rss-move-feed`
  files an existing subscription under another folder.
- `i` imports an OPML file (feeds already subscribed by URL are skipped), and
  `e` exports every subscription with its folders.

## Browsing and reading

`1`, `2` and `3` show every stored article, the unread ones and the starred
ones; clicking a feed or folder in the sidebar shows its slice. `j` / `k`
move the selection and page the list when it walks off the page.

On a wide frame the reading pane always shows the selected article: it loads
after a short settle time (`etaf-rss-follow-delay`), renders the article HTML
as wrapped text, and marks the article read once it has stayed open for
`etaf-rss-mark-read-delay` seconds. On a medium or narrow frame one pane is
shown at a time; `RET` opens the reading pane and `v` switches back.

`SPC` scrolls the article by a page, `m` toggles read, `s` toggles the star,
`A` marks the whole scope read and `M` marks the selection and everything
above it. `o` opens the original URL in the browser.

## Search

`/` asks for a keyword and shows a search scope. Terms are literal and
case-insensitive; every space-separated term must appear in the title, the
summary or the body. Matched rows carry a short snippet of the passage. `1`
leaves the search scope.

## Refresh

`g` reloads the sidebar and list and re-fetches the feeds of the current
scope; `R` re-fetches every subscription. Feeds are fetched one at a time,
with `If-None-Match` / `If-Modified-Since` when the store knows them, so an
unchanged feed costs one 304 response. The status line reports progress, a
failed feed keeps its error in the sidebar until it succeeds, and the reader
stays usable throughout. A mounted reader also refreshes itself every
`etaf-rss-refresh-interval` seconds while it is visible; set it to `nil` to
refresh only on request.

## Configuration

| Variable | Default | Purpose |
| --- | --- | --- |
| `etaf-rss-data-file` | `<user-emacs-directory>/etaf-rss/data.json` | subscriptions, articles and reading state |
| `etaf-rss-request-timeout` | 20 | seconds before one feed request is abandoned |
| `etaf-rss-articles-per-feed` | 200 | newest articles kept per feed |
| `etaf-rss-starred-limit` | 1000 | most starred articles kept |
| `etaf-rss-search-limit` | 200 | most rows one search returns |
| `etaf-rss-save-delay` | 1.5 | seconds of quiet before the store is written |
| `etaf-rss-user-agent` | `etaf-rss/…` | User-Agent sent with feed requests |
| `etaf-rss-theme-mode` | `dark` | palette of new sessions |
| `etaf-rss-reading-measure` | 58 | preferred reading column width |
| `etaf-rss-wide-columns` | 118 | frame width of the three-column layout |
| `etaf-rss-medium-columns` | 72 | frame width of the narrow sidebar layout |
| `etaf-rss-follow-delay` | 0.45 | seconds before the pane follows the selection |
| `etaf-rss-mark-read-delay` | 1.0 | seconds before an open article is marked read |
| `etaf-rss-refresh-interval` | 900 | seconds between automatic refreshes, or `nil` |

The palette, the reading width and the store are per session: rebind the
variables before `etaf-rss-create`, or use several sessions for several
profiles.

## Failure and recovery

- A feed that cannot be fetched keeps its previous articles; its error is
  painted in the sidebar and reported in the status line, and the next
  successful refresh clears it. Nothing else changes.
- A store file that cannot be parsed is renamed to `data.json.bad` and the
  reader starts empty, so the damaged file stays recoverable instead of being
  overwritten.
- A request that exceeds `etaf-rss-request-timeout` is abandoned and reported;
  the reader never waits on one feed.
- Closing the buffer cancels the refresh timer and abandons in-flight
  requests, writing pending changes to the store first.
