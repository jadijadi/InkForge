import Foundation

/// Typography shared by the live preview and the exported EPUB.
/// Tuned for long-form reading: serif body, generous measure, relaxed leading.
enum ReadingStylesheet {
    static let epub = """
    html { font-size: 100%; }
    body {
      font-family: "Iowan Old Style", "Palatino", "Charter", Georgia, serif;
      line-height: 1.6;
      margin: 0 auto;
      padding: 1.5em 1.25em;
      max-width: 40em;
      text-rendering: optimizeLegibility;
      -webkit-hyphens: auto; hyphens: auto;
    }
    h1, h2, h3, h4, h5, h6 { font-weight: 600; line-height: 1.25; margin: 1.6em 0 0.6em; -webkit-hyphens: none; hyphens: none; }
    h1 { font-size: 2em; margin-top: 0.8em; }
    h2 { font-size: 1.5em; }
    h3 { font-size: 1.2em; }
    h4, h5, h6 { font-size: 1em; }
    p { margin: 0 0 1em; }
    p + p { text-indent: 0; }
    a { color: #2a5db0; text-decoration: none; }
    a:hover { text-decoration: underline; }
    blockquote { margin: 1.2em 0; padding: 0.2em 1.2em; border-left: 3px solid #c8c2b4; color: #5c5850; font-style: italic; }
    blockquote p:last-child { margin-bottom: 0; }
    ul, ol { margin: 0 0 1em; padding-left: 1.6em; }
    li { margin: 0.25em 0; }
    li > p { margin: 0.2em 0; }
    li.task { list-style: none; margin-left: -1.4em; }
    code, pre { font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace; font-size: 0.86em; }
    code { background: rgba(127,127,127,0.14); padding: 0.1em 0.35em; border-radius: 4px; }
    pre { background: rgba(127,127,127,0.10); padding: 0.9em 1.1em; border-radius: 8px; overflow-x: auto; line-height: 1.45; margin: 0 0 1.2em; }
    pre code { background: none; padding: 0; font-size: 1em; }
    img { max-width: 100%; height: auto; display: block; margin: 1.5em auto; border-radius: 4px; }
    hr { border: 0; height: 1px; background: #c8c2b4; margin: 2.4em auto; width: 40%; }
    table { border-collapse: collapse; margin: 0 0 1.5em; width: 100%; font-size: 0.95em; }
    th, td { border-bottom: 1px solid #ddd6c8; padding: 0.45em 0.6em; text-align: left; vertical-align: top; }
    th { font-weight: 600; border-bottom-width: 2px; }
    del { opacity: 0.6; }
    """

    /// Preview additions: app-like colors that follow the system appearance.
    static let previewExtras = """
    :root { color-scheme: light dark; }
    body { background: #fbfaf7; color: #1d1c1a; padding: 2.5em 3em 6em; max-width: 44em; }
    body.empty { color: #8c877d; text-align: center; padding-top: 6em; font-style: italic; }
    pre.plain { background: none; padding: 0; font-size: 0.9em; white-space: pre-wrap; }
    @media (prefers-color-scheme: dark) {
      body { background: #1e1e1f; color: #dedbd4; }
      a { color: #7fa9ec; }
      blockquote { border-color: #4a4640; color: #a8a297; }
      hr { background: #4a4640; }
      th, td { border-color: #3a3835; }
    }
    """

    static let previewPage = """
    <!DOCTYPE html>
    <html>
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
    \(epub)
    \(previewExtras)
    </style>
    </head>
    <body class="empty">Nothing to preview</body>
    <script>
    window.inkforge = {
      setContent(html) {
        const body = document.body;
        const y = window.scrollY;
        body.className = html.trim() ? "" : "empty";
        body.innerHTML = html.trim() ? html : "Nothing to preview";
        window.scrollTo(0, y);
      }
    };
    </script>
    </html>
    """
}
