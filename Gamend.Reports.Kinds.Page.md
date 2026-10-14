# `Gamend.Reports.Kinds.Page`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/reports/kinds/page.ex#L1)

The built-in report kind: something on a page is broken or looks wrong.

The subject is the page's address as the reporter gave it, fragment
dropped: the full URL the form fills in (`GamendWeb.Reports.PageSubject`),
a pasted address bar, or a bare path. A URL on another site is kept too,
since the report may well be about a link that leads there.

The duplicates key is the page's path on this site, query dropped, so a
full URL and a bare path for the same page are one report; an address on
another site keys as itself.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
