import Foundation

/// Reader mode. The extraction script picks the densest block of article text on the page and
/// returns its cleaned HTML; `document` wraps that in a calm, readable page. Original code, not a
/// third-party readability library.
enum Reader {
    /// Runs in the page, returns a JSON string: { title, heading, byline, html }.
    static let extractionJS = """
    (function () {
      function textLength(el) {
        var ps = el.querySelectorAll('p');
        var n = 0;
        for (var i = 0; i < ps.length; i++) n += (ps[i].innerText || '').trim().length;
        return n;
      }
      var pool = document.querySelectorAll('article, main, [role="main"], .post, .article, .content, div, section');
      var best = null, bestScore = 0;
      for (var i = 0; i < pool.length; i++) {
        var s = textLength(pool[i]);
        if (s > bestScore) { bestScore = s; best = pool[i]; }
      }
      if (!best || bestScore < 200) best = document.body;
      var clone = best.cloneNode(true);
      var junk = clone.querySelectorAll(
        'script, style, noscript, iframe, nav, aside, header, footer, form, button, input, svg, ' +
        '[role="navigation"], [class*="share"], [class*="comment"], [class*="promo"], [class*="newsletter"], ' +
        '[class*="ad-"], [id*="ad-"], [class*="related"], [aria-hidden="true"]');
      for (var j = 0; j < junk.length; j++) junk[j].remove();
      var imgs = clone.querySelectorAll('img');
      for (var k = 0; k < imgs.length; k++) {
        var src = imgs[k].getAttribute('data-src') || imgs[k].getAttribute('src');
        if (src) imgs[k].setAttribute('src', src);
        imgs[k].removeAttribute('srcset');
      }
      var h1 = document.querySelector('h1');
      var author = document.querySelector('[rel="author"], .author, [class*="byline"]');
      return JSON.stringify({
        title: document.title || '',
        heading: h1 ? (h1.innerText || '').trim() : '',
        byline: author ? (author.innerText || '').trim() : '',
        html: clone.innerHTML
      });
    })();
    """

    /// Wraps the extracted article in a clean page. Serif body, one column, light and dark aware.
    static func document(title: String, byline: String, bodyHTML: String) -> String {
        let safeTitle = title.replacingOccurrences(of: "<", with: "&lt;")
        let bylineHTML = byline.isEmpty ? "" : "<p class=\"byline\">\(byline.replacingOccurrences(of: "<", with: "&lt;"))</p>"
        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        :root { color-scheme: light dark; }
        html { -webkit-text-size-adjust: 100%; }
        body {
          margin: 0; padding: 64px 24px 120px;
          font: 19px/1.7 ui-serif, Georgia, 'Times New Roman', serif;
          color: #1a1a1a; background: #faf9f7;
          display: flex; justify-content: center;
        }
        main { max-width: 680px; width: 100%; }
        h1 { font-size: 34px; line-height: 1.2; font-weight: 700; margin: 0 0 8px; }
        .byline { color: #777; font-size: 15px; margin: 0 0 32px; font-style: italic; }
        p { margin: 0 0 20px; }
        a { color: #2b6cb0; }
        img, figure, video { max-width: 100%; height: auto; border-radius: 8px; display: block; margin: 24px auto; }
        figure { margin: 24px 0; }
        figcaption { font-size: 14px; color: #888; text-align: center; }
        blockquote { border-left: 3px solid #ddd; margin: 24px 0; padding: 4px 0 4px 20px; color: #555; }
        pre, code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 15px; }
        pre { background: #f0efec; padding: 16px; border-radius: 8px; overflow-x: auto; }
        h2, h3 { line-height: 1.3; margin: 36px 0 12px; }
        hr { border: none; border-top: 1px solid #e3e1dc; margin: 40px 0; }
        @media (prefers-color-scheme: dark) {
          body { color: #e4e2de; background: #1a1a1a; }
          .byline { color: #999; }
          a { color: #7cb3ec; }
          blockquote { border-left-color: #444; color: #aaa; }
          pre { background: #262626; }
          hr { border-top-color: #333; }
        }
        </style>
        </head>
        <body>
        <main>
        <h1>\(safeTitle)</h1>
        \(bylineHTML)
        \(bodyHTML)
        </main>
        </body>
        </html>
        """
    }
}
