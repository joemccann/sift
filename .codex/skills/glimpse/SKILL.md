---
name: glimpse
description: Show native macOS UI from scripts and agents — dialogs, forms, visualizations, floating widgets, cursor companions. Use when you need to display HTML to the user, collect input, show a chart, render markdown, or create any visual interaction without a browser.
---

# Glimpse — Native macOS Micro-UI

Glimpse opens a native macOS window with a WKWebView in under 50ms. You write HTML, the user sees it instantly. Bidirectional communication via `window.glimpse.send()` (webview -> Node) and `.send(js)` (Node -> webview).

**When to use Glimpse:**
- You need user input beyond yes/no (forms, selections, text input)
- You want to show something visual (charts, markdown, images, diffs)
- You want to confirm a destructive action with a proper dialog
- You want a floating indicator, notification, or companion widget
- You need the user to interact with rich content

**Import:** Always use the absolute path to `glimpse.mjs` within the installed package:
```js
import { open, prompt } from '/Users/joemccann/dev/apps/util/glimpse-ui/src/glimpse.mjs';
```

---

## Quick Reference

### One-Shot Dialog (prompt)
```js
const answer = await prompt(html, {
  width: 400, height: 300,
  title: 'My Dialog',
  frameless: true,
  transparent: true,
});
// answer = data from window.glimpse.send(), or null if user closed window
```

### Persistent Window (open)
```js
const win = open(html, options);
win.on('ready', (info) => {});       // HTML loaded
win.on('message', data => {});       // user interaction
win.on('closed', () => {});          // window gone
win.send('document.title = "Hi"');   // eval JS in webview
win.setHTML('<h1>New content</h1>'); // replace HTML
win.close();                         // close window
```

### All Options
```js
{
  width, height,          // pixels (default: 800x600)
  title,                  // window title (default: "Glimpse")
  frameless: true,        // no title bar, draggable by background
  floating: true,         // always on top
  transparent: true,      // transparent window background
  clickThrough: true,     // mouse passes through window
  followCursor: true,     // window follows mouse cursor
  followMode: 'spring',   // 'snap' (instant, default) or 'spring' (elastic)
  cursorAnchor: 'top-right',
  cursorOffset: {x, y},
  openLinks: true,        // open clicked links in default browser
  autoClose: true,        // close after first message
  x, y,                   // exact screen position
  timeout,                // for prompt() only — ms before rejecting
}
```

### In-Page JavaScript Bridge
```js
window.glimpse.send(data)  // send data to Node (any JSON-serializable value)
window.glimpse.close()     // close the window from JS
```

---

## Common Patterns

- **Confirm Dialog**: `prompt()` with yes/no buttons, Enter/Escape keyboard handling
- **Text Input Form**: Input fields with submit on Enter
- **Selection List**: Arrow keys + Enter to pick from a list
- **Live Progress**: `open()` + push updates via `.send()` as work progresses
- **Floating Notification**: Frameless + transparent + floating + clickThrough + auto-dismiss
- **Cursor Companion**: followCursor + clickThrough for agent status indicators
- **Command Palette**: Frameless + transparent + backdrop blur + search input

## Tips

- Always set `cursor: pointer` on clickable elements
- Use `autofocus` on the primary input field
- Add keyboard shortcuts — Enter to confirm, Escape to cancel
- For transparent windows, set `background: transparent !important` on `<body>`
- `prompt()` returns `null` when the user closes without sending — always handle this
- Be generous with window height — content clips without scrollbars
