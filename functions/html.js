/**
 * Prompt-Vorgaben und Bereinigung der Modellantwort zu einer eigenständigen
 * HTML-Datei (Gegenstück zu HtmlCleaner in lib/main.dart).
 */

const SYSTEM_PROMPT = `Du bist ein Generator für eigenständige mobile Web-Apps und Browser-Spiele.
Antworte AUSSCHLIESSLICH mit dem Quellcode EINER vollständigen, validen HTML5-Datei.

FORMAT (strikt einhalten):
- Die Antwort beginnt exakt mit <!DOCTYPE html> und endet exakt mit </html>.
- KEINE Markdown-Codeblöcke, KEINE Backticks (\`\`\`), KEIN einleitender oder abschließender Text, KEINE Erklärungen.
- Sämtliches CSS steht in einem <style>-Tag, sämtliches JavaScript in <script>-Tags innerhalb dieser einen Datei.
- Keine externen Ressourcen: keine CDNs, keine Bibliotheken, keine Webfonts, keine Bilder oder Sounds aus dem Netz. Grafiken per Canvas, CSS, SVG oder Emoji; Sounds bei Bedarf per Web Audio API.
- Im <head>: <meta charset="utf-8">, <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no"> und ein kurzer, prägnanter <title> (max. 40 Zeichen), der die App benennt.

MOBILE & TOUCH:
- Ausgelegt für Smartphones im Hochformat. Das Layout passt sich an Breite UND Höhe des Viewports an und reagiert auf das resize-Event.
- Vollständig per Touch bedienbar: Touch-Events (touchstart/touchmove/touchend) oder Pointer Events. Auf Spielflächen preventDefault() mit { passive: false } und touch-action: none, damit die Seite nicht scrollt oder zoomt.
- Für Spiele, die Richtungen oder Aktionen brauchen: gut erreichbare On-Screen-Buttons oder Wischgesten. Es darf keine Tastatur nötig sein (Tastatursteuerung höchstens zusätzlich).
- Buttons mindestens 44×44 px, gut lesbare Schriftgrößen, keine Hover-Abhängigkeiten.
- Canvas-Inhalte mit devicePixelRatio scharf darstellen.
- body mit margin: 0, user-select: none, kein Overscroll.

QUALITÄT:
- Vollständig implementiert und sofort benutzbar bzw. spielbar: keine Platzhalter, keine TODOs, kein Pseudocode.
- Keine JavaScript-Fehler. Spiele haben einen Startbildschirm, Punktestand (wo sinnvoll), Game-Over-Zustand und Neustart.
- Neustart und Zurücksetzen ausschließlich per JavaScript-Zustand, NIEMALS über location.reload() oder Seitenwechsel.
- localStorage nur innerhalb von try/catch verwenden (z. B. für Highscores).
- Modernes, ansprechendes Design mit stimmigen Farben.
- Alle Texte der App in der Sprache des Nutzer-Prompts.
`;

function buildUserPrompt(prompt) {
  return `Erstelle folgende App bzw. folgendes Spiel als eine einzige HTML-Datei:\n\n${prompt}`;
}

const VIEWPORT =
  '<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">';

/**
 * Macht aus der Modellantwort eine saubere HTML-Datei.
 * Gibt `null` zurück, wenn die Antwort gar kein HTML enthält.
 */
function cleanHtml(raw) {
  // Denkprozess mancher Modelle (<think>…</think>) entfernen.
  let text = String(raw ?? "")
    .replace(/\r\n/g, "\n")
    .replace(/<think>[\s\S]*?<\/think>/gi, "")
    .trim();
  const lower = text.toLowerCase();

  let start = lower.indexOf("<!doctype");
  if (start < 0) start = lower.indexOf("<html");

  if (start >= 0) {
    // Vollständiges Dokument: Einleitung, Markdown-Fences und Erklärungen abschneiden.
    const end = lower.lastIndexOf("</html>");
    text = end > start ? text.slice(start, end + "</html>".length) : text.slice(start);
    text = text.replace(/\s*```\s*$/, "").trim();
    if (!text.toLowerCase().startsWith("<!doctype")) text = `<!DOCTYPE html>\n${text}`;
  } else {
    // Nur ein Fragment: größten Markdown-Codeblock nehmen und einbetten.
    let best = null;
    for (const match of text.matchAll(/```[^\n]*\n([\s\S]*?)(?:```|$)/g)) {
      const block = match[1].trim();
      if (best === null || block.length > best.length) best = block;
    }
    text = (best ?? text).replace(/```/g, "").trim();
    if (!/<[a-zA-Z!][^>]*>/.test(text)) return null;
    text = wrapFragment(text);
  }

  return ensureViewport(text);
}

function extractTitle(html) {
  const match = /<title[^>]*>([\s\S]*?)<\/title>/i.exec(html);
  if (!match) return null;
  const title = decodeEntities(match[1]).replace(/\s+/g, " ").trim();
  if (!title) return null;
  const chars = Array.from(title);
  return chars.length > 60 ? `${chars.slice(0, 57).join("")}…` : title;
}

function ensureViewport(html) {
  if (/<meta[^>]+name\s*=\s*["']?viewport/i.test(html)) return html;

  const head = /<head(\s[^>]*)?>/i.exec(html);
  if (head) return insertAt(html, head.index + head[0].length, `\n${VIEWPORT}`);

  const htmlTag = /<html(\s[^>]*)?>/i.exec(html);
  if (htmlTag) {
    return insertAt(
      html,
      htmlTag.index + htmlTag[0].length,
      `\n<head>\n<meta charset="utf-8">\n${VIEWPORT}\n</head>`,
    );
  }
  return html;
}

function insertAt(text, index, insertion) {
  return text.slice(0, index) + insertion + text.slice(index);
}

function wrapFragment(fragment) {
  return `<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
${VIEWPORT}
<style>body { margin: 0; }</style>
</head>
<body>
${fragment}
</body>
</html>`;
}

function decodeEntities(text) {
  return text
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&apos;/g, "'")
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&");
}

module.exports = { SYSTEM_PROMPT, buildUserPrompt, cleanHtml, extractTitle };
