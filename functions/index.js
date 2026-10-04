/**
 * PromptPlay – Cloud Functions
 *
 * ensureUserProfile  Legt users/{uid} an und schreibt nach der Google-Anmeldung
 *                    einmalig Gratis-Credits gut; liefert den Kontostand.
 * generateGame       Zieht atomar 1 Credit ab, generiert per Gemini eine
 *                    HTML-App und bucht den Credit zurück, falls das scheitert.
 * verifyPurchase     Prüft einen Google-Play-Kauf und schreibt die Credits
 *                    genau einmal gut.
 * reportContent      Nimmt Meldungen zu KI-generierten Inhalten entgegen
 *                    (Google-Play-Richtlinie für KI-Apps).
 * deleteAccount      Löscht Credits-Profil und anonymes Konto des Nutzers.
 *
 * Nur diese Functions schreiben in Firestore (Admin SDK). Die Firestore-Regeln
 * verbieten Clients jeden Schreibzugriff.
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const logger = require("firebase-functions/logger");
const { initializeApp } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { GoogleGenAI } = require("@google/genai");
const {
  SIZES,
  MAX_BASE_HTML,
  SOURCE_COST,
  buildGeminiRequest,
  costForExtend,
  parseSources,
  cleanHtml,
  extractTitle,
} = require("./html");
const {
  PRODUCTS,
  sha256,
  accountIdFor,
  purchaseDocId,
  checkPurchase,
  fetchPurchase,
  consumePurchase,
} = require("./purchases");

initializeApp();
const db = getFirestore();

// Wird mit `firebase functions:secrets:set GEMINI_API_KEY` hinterlegt.
const GEMINI_API_KEY = defineSecret("GEMINI_API_KEY");

const REGION = "europe-west3"; // Frankfurt – muss in der App identisch sein.
// Fest gewählt statt „gemini-flash-latest“, damit Kosten pro Credit planbar bleiben.
const GEMINI_MODEL = "gemini-3.8-flash";
const FREE_CREDITS = 2;
const MAX_PROMPT_LENGTH = 4000;
const MAX_IMAGES = 6;
const MAX_IMAGE_BASE64 = 900_000; // ca. 650 KB Bilddaten
const IMAGE_TYPES = new Set(["image/png", "image/jpeg", "image/webp"]);
// Wartezeiten vor erneuten Versuchen, wenn Gemini überlastet ist.
const RETRY_DELAYS_MS = [3_000, 8_000, 15_000];
const FUNCTION_TIMEOUT_SECONDS = 300;
// Kürzer als das Function-Timeout, damit die Rückbuchung sicher noch läuft.
const GEMINI_TIMEOUT_MS = 240_000;

const baseOptions = {
  region: REGION,
  // Für die Produktion empfohlen: App Check (Play Integrity) einrichten und
  // hier auf true setzen, damit nur deine echte App die Functions aufrufen kann.
  enforceAppCheck: false,
};

/**
 * Legt das Profil an (anonym: 0 Credits) und schreibt die Gratis-Credits gut,
 * sobald das Konto mit Google verbunden ist – einmalig pro Google-Konto, auch
 * über Kontolöschung und Neuinstallation hinweg (freeGrants/{Hash}).
 */
exports.ensureUserProfile = onCall(baseOptions, async (request) => {
  const uid = requireUid(request);
  const googleId = request.auth.token.firebase?.identities?.["google.com"]?.[0] ?? null;
  const userRef = db.collection("users").doc(uid);
  const grantRef = googleId ? db.collection("freeGrants").doc(sha256(`google:${googleId}`)) : null;

  return db.runTransaction(async (tx) => {
    const userSnap = await tx.get(userRef);
    const grantSnap = grantRef ? await tx.get(grantRef) : null;
    let credits = userSnap.exists ? readCredits(userSnap) : 0;
    const grantFree = grantSnap !== null && !grantSnap.exists;

    if (grantFree) {
      tx.set(grantRef, { grantedAt: FieldValue.serverTimestamp() });
      credits += FREE_CREDITS;
    }
    if (!userSnap.exists || grantFree) {
      tx.set(
        userRef,
        {
          credits,
          ...(userSnap.exists ? {} : { createdAt: FieldValue.serverTimestamp() }),
        },
        { merge: true },
      );
    }
    return { credits, freeCreditsGranted: grantFree ? FREE_CREDITS : 0 };
  });
});

exports.generateGame = onCall(
  {
    ...baseOptions,
    secrets: [GEMINI_API_KEY],
    timeoutSeconds: FUNCTION_TIMEOUT_SECONDS,
    memory: "512MiB",
    maxInstances: 10,
  },
  async (request) => {
    const uid = requireUid(request);
    const job = parseGenerationRequest(request.data ?? {});
    const userRef = db.collection("users").doc(uid);

    // 1. Credits atomar abziehen. Gratis-Credits gibt es nur über
    //    ensureUserProfile nach der Google-Anmeldung.
    const creditsLeft = await db.runTransaction(async (tx) => {
      const snap = await tx.get(userRef);
      const credits = snap.exists ? readCredits(snap) : 0;
      if (credits < job.cost) {
        // „resource-exhausted“ steht in der App ausschließlich für „zu wenig Credits“.
        throw new HttpsError(
          "resource-exhausted",
          credits <= 0
            ? "Keine Credits mehr – bitte im Shop aufladen."
            : `Dafür brauchst du ${job.cost} Credits, du hast ${credits}. Bitte im Shop aufladen.`,
          { credits, cost: job.cost },
        );
      }
      tx.update(userRef, {
        credits: FieldValue.increment(-job.cost),
        lastGenerationAt: FieldValue.serverTimestamp(),
      });
      return credits - job.cost;
    });

    // 2. Generieren – bei jedem Fehler die Credits zurückbuchen.
    try {
      const html = await generateHtml(job);
      return { html, title: extractTitle(html), creditsLeft, cost: job.cost };
    } catch (error) {
      await refundCredits(userRef, uid, job.cost);
      if (error instanceof HttpsError) throw error;
      logger.error("Generierung fehlgeschlagen", { uid, error: String(error) });
      throw new HttpsError(
        "internal",
        "Die Generierung ist fehlgeschlagen. Deine Credits wurden zurückgebucht.",
      );
    }
  },
);

/**
 * Prüft die Anfrage der App und berechnet die Kosten.
 * Neues Spiel: { prompt, size, images?, sources? } – Weiterbauen: { prompt, baseHtml, images?, sources? }
 */
function parseGenerationRequest(data) {
  const prompt = typeof data.prompt === "string" ? data.prompt.trim() : "";
  if (!prompt) {
    throw new HttpsError("invalid-argument", "Bitte beschreibe, was erstellt werden soll.");
  }
  if (prompt.length > MAX_PROMPT_LENGTH) {
    throw new HttpsError(
      "invalid-argument",
      `Der Prompt ist zu lang (maximal ${MAX_PROMPT_LENGTH} Zeichen).`,
    );
  }

  const baseHtml = typeof data.baseHtml === "string" && data.baseHtml.trim() ? data.baseHtml : null;
  if (baseHtml && baseHtml.length > MAX_BASE_HTML) {
    throw new HttpsError(
      "invalid-argument",
      "Dieses Spiel ist zu groß, um es weiterzubauen. Starte am besten ein neues Projekt.",
    );
  }

  const size = data.size ?? "small";
  if (!baseHtml && !Object.hasOwn(SIZES, size)) {
    throw new HttpsError("invalid-argument", "Unbekannte Größe.");
  }

  const rawImages = data.images ?? [];
  if (!Array.isArray(rawImages) || rawImages.length > MAX_IMAGES) {
    throw new HttpsError("invalid-argument", `Höchstens ${MAX_IMAGES} Bilder pro Spiel.`);
  }
  const names = new Set();
  const images = rawImages.map((image) => {
    const name = typeof image?.name === "string" ? image.name : "";
    const valid =
      /^[a-z0-9_-]{1,30}$/.test(name) &&
      !names.has(name) &&
      IMAGE_TYPES.has(image?.mimeType) &&
      typeof image?.data === "string" &&
      image.data.length > 0 &&
      image.data.length <= MAX_IMAGE_BASE64;
    if (!valid) throw new HttpsError("invalid-argument", "Ein Bild ist ungültig oder zu groß.");
    names.add(name);
    return { name, mimeType: image.mimeType, data: image.data };
  });

  let sources;
  try {
    sources = parseSources(data.sources);
  } catch (error) {
    throw new HttpsError("invalid-argument", error.message);
  }

  const cost =
    (baseHtml ? costForExtend(baseHtml.length) : SIZES[size].cost) +
    (sources.length > 0 ? SOURCE_COST : 0);
  const kidSafe = data.kidSafe === true;
  return { prompt, size, images, sources, baseHtml, kidSafe, cost };
}

exports.verifyPurchase = onCall({ ...baseOptions, maxInstances: 10 }, async (request) => {
  const uid = requireUid(request);
  const productId = limitedString(request.data?.productId, 100);
  const purchaseToken = limitedString(request.data?.purchaseToken, 4096);
  const credits = PRODUCTS[productId];
  if (!credits) throw new HttpsError("invalid-argument", "Unbekanntes Produkt.");
  if (!purchaseToken) throw new HttpsError("invalid-argument", "Der Kaufbeleg fehlt.");

  // 1. Beleg direkt bei Google Play prüfen – der App wird nicht vertraut.
  let purchase;
  try {
    purchase = await fetchPurchase(productId, purchaseToken);
  } catch (error) {
    const status = error?.response?.status ?? error?.status ?? null;
    logger.error("Kauf-Prüfung bei Google Play fehlgeschlagen", {
      uid,
      productId,
      status,
      detail: String(error?.message ?? error),
    });
    if (status === 400 || status === 404 || status === 410) {
      throw new HttpsError("invalid-argument", "Der Kaufbeleg ist ungültig.");
    }
    throw new HttpsError(
      "unavailable",
      "Der Kauf konnte gerade nicht geprüft werden. Deine Credits werden automatisch nachgebucht.",
    );
  }
  checkPurchase(purchase, accountIdFor(uid));

  // 2. Gutschreiben – jeder Beleg genau einmal (Transaktion über purchases/{hash}).
  const purchaseRef = db.collection("purchases").doc(purchaseDocId(purchaseToken));
  const userRef = db.collection("users").doc(uid);
  const added = await db.runTransaction(async (tx) => {
    const purchaseSnap = await tx.get(purchaseRef);
    if (purchaseSnap.exists) {
      if (purchaseSnap.get("uid") !== uid) {
        throw new HttpsError("permission-denied", "Dieser Kauf gehört zu einem anderen Konto.");
      }
      return 0;
    }
    tx.set(purchaseRef, {
      uid,
      productId,
      orderId: purchase.orderId ?? null,
      credits,
      createdAt: FieldValue.serverTimestamp(),
    });
    tx.set(
      userRef,
      { credits: FieldValue.increment(credits), lastPurchaseAt: FieldValue.serverTimestamp() },
      { merge: true },
    );
    return credits;
  });

  // 3. Verbrauchen, damit das Paket erneut gekauft werden kann. Schlägt das
  //    fehl, holt es der nächste Aufruf mit demselben Beleg nach.
  if (purchase.consumptionState !== 1) {
    try {
      await consumePurchase(productId, purchaseToken);
    } catch (error) {
      logger.error("Kauf konnte nicht verbraucht werden", {
        uid,
        productId,
        detail: String(error?.message ?? error),
      });
    }
  }

  if (added > 0) logger.info("Kauf gutgeschrieben", { uid, productId, orderId: purchase.orderId, added });
  return { added };
});

const MAX_REPORT_TEXT = 4000;
const MAX_REPORT_HTML = 100_000;

exports.reportContent = onCall({ ...baseOptions, maxInstances: 5 }, async (request) => {
  const uid = requireUid(request);
  const data = request.data ?? {};
  const reason = limitedString(data.reason, MAX_REPORT_TEXT);
  if (!reason) {
    throw new HttpsError("invalid-argument", "Bitte gib einen Grund für die Meldung an.");
  }

  await db.collection("reports").add({
    uid,
    reason,
    title: limitedString(data.title, 200),
    prompt: limitedString(data.prompt, MAX_REPORT_TEXT),
    generatedBy: limitedString(data.generatedBy, 200),
    html: limitedString(data.html, MAX_REPORT_HTML),
    status: "open",
    createdAt: FieldValue.serverTimestamp(),
  });
  logger.info("Inhalt gemeldet", { uid, reason });
  return { reported: true };
});

exports.deleteAccount = onCall(baseOptions, async (request) => {
  const uid = requireUid(request);

  await db.collection("users").doc(uid).delete();

  // Meldungen (Moderation) und Kaufbelege (Aufbewahrungspflicht) bleiben
  // erhalten, werden aber vom Konto getrennt.
  const [reports, purchases] = await Promise.all([
    db.collection("reports").where("uid", "==", uid).get(),
    db.collection("purchases").where("uid", "==", uid).get(),
  ]);
  const batch = db.batch();
  for (const doc of [...reports.docs, ...purchases.docs]) {
    batch.update(doc.ref, { uid: FieldValue.delete() });
  }
  await batch.commit();

  await getAuth().deleteUser(uid);
  logger.info("Konto gelöscht", { uid });
  return { deleted: true };
});

async function generateHtml(job) {
  const ai = new GoogleGenAI({ apiKey: GEMINI_API_KEY.value() });
  const { systemInstruction, parts, safetySettings, tools } = buildGeminiRequest(job);
  const deadline = Date.now() + GEMINI_TIMEOUT_MS;

  let response;
  for (let attempt = 0; ; attempt++) {
    try {
      response = await ai.models.generateContent({
        model: GEMINI_MODEL,
        contents: [{ role: "user", parts }],
        config: {
          systemInstruction,
          safetySettings,
          ...(tools ? { tools } : {}),
          abortSignal: AbortSignal.timeout(Math.max(1_000, deadline - Date.now())),
        },
      });
      break;
    } catch (error) {
      // Bei Überlastung kurz warten und erneut versuchen, solange Zeit bleibt.
      const delay = RETRY_DELAYS_MS[attempt];
      const retriable = [429, 500, 503].includes(error?.status);
      if (retriable && delay && Date.now() + delay < deadline - 60_000) {
        logger.warn("Gemini überlastet, neuer Versuch", { status: error.status, attempt: attempt + 1 });
        await new Promise((resolve) => setTimeout(resolve, delay));
        continue;
      }
      throw describeGeminiError(error);
    }
  }

  const blockReason = response.promptFeedback?.blockReason;
  if (blockReason) {
    throw new HttpsError(
      "invalid-argument",
      `Der Prompt wurde von Gemini blockiert (${blockReason}). Deine Credits wurden zurückgebucht – bitte formuliere ihn um.`,
    );
  }
  if (response.candidates?.[0]?.finishReason === "SAFETY") {
    throw new HttpsError(
      "invalid-argument",
      job.kidSafe
        ? "Dieser Wunsch passt nicht zum Familien-Modus. Deine Credits wurden zurückgebucht – bitte formuliere ihn kindgerecht."
        : "Die Sicherheitsfilter von Gemini haben die Antwort gestoppt. Deine Credits wurden zurückgebucht – bitte formuliere den Wunsch um.",
    );
  }
  if (response.candidates?.[0]?.finishReason === "MAX_TOKENS") {
    throw new HttpsError(
      "failed-precondition",
      "Die Antwort war zu lang und wurde abgeschnitten. Deine Credits wurden zurückgebucht – bitte vereinfache den Wunsch oder wähle eine kleinere Größe.",
    );
  }

  const html = cleanHtml(response.text ?? "");
  if (!html) {
    throw new HttpsError(
      "internal",
      "Gemini hat keinen HTML-Code geliefert. Deine Credits wurden zurückgebucht – bitte erneut versuchen.",
    );
  }
  // Bei Vorlagen-Links: welche Seiten Gemini lesen konnte (Kosten im Blick behalten).
  const urls = response.candidates?.[0]?.urlContextMetadata?.urlMetadata?.map((entry) => ({
    url: entry.retrievedUrl,
    status: entry.urlRetrievalStatus,
  }));
  logger.info("Generiert", {
    usage: response.usageMetadata,
    kb: Math.round(html.length / 1024),
    ...(urls ? { urls } : {}),
  });
  return html;
}

function describeGeminiError(error) {
  const status = typeof error?.status === "number" ? error.status : null;
  logger.error("Gemini-Aufruf fehlgeschlagen", {
    status,
    errorName: error?.name,
    detail: String(error?.message ?? error),
  });

  if (error?.name === "TimeoutError" || error?.name === "AbortError") {
    return new HttpsError(
      "deadline-exceeded",
      "Gemini hat nicht rechtzeitig geantwortet. Deine Credits wurden zurückgebucht – bitte erneut versuchen.",
    );
  }
  if (status === 400 || status === 401 || status === 403 || status === 404) {
    // Falscher Key oder Modellname auf dem Server – Details stehen im Log.
    return new HttpsError(
      "internal",
      "Der Generierungsdienst ist falsch konfiguriert. Deine Credits wurden zurückgebucht.",
    );
  }
  return new HttpsError(
    "unavailable",
    "Gemini ist gerade überlastet oder nicht erreichbar. Deine Credits wurden zurückgebucht – bitte später erneut versuchen.",
  );
}

async function refundCredits(userRef, uid, amount) {
  try {
    await userRef.update({ credits: FieldValue.increment(amount) });
  } catch (error) {
    logger.error("Credit-Rückbuchung fehlgeschlagen", { uid, error: String(error) });
  }
}

function requireUid(request) {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Bitte melde dich zuerst an.");
  return uid;
}

function limitedString(value, maxLength) {
  return typeof value === "string" ? value.trim().slice(0, maxLength) : "";
}

function readCredits(snap) {
  const credits = snap.get("credits");
  return Number.isInteger(credits) ? credits : 0;
}
