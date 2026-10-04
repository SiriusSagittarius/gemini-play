/**
 * PromptPlay – Cloud Functions
 *
 * ensureUserProfile  Legt users/{uid} beim ersten Start mit Gratis-Credits an
 *                    und liefert den aktuellen Kontostand.
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
const { SYSTEM_PROMPT, buildUserPrompt, cleanHtml, extractTitle } = require("./html");
const {
  PRODUCTS,
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
const GEMINI_MODEL = "gemini-flash-latest"; // Alias auf das aktuelle Flash-Modell.
const FREE_CREDITS = 2;
const MAX_PROMPT_LENGTH = 4000;
const FUNCTION_TIMEOUT_SECONDS = 300;
// Kürzer als das Function-Timeout, damit die Rückbuchung sicher noch läuft.
const GEMINI_TIMEOUT_MS = 240_000;

const baseOptions = {
  region: REGION,
  // Für die Produktion empfohlen: App Check (Play Integrity) einrichten und
  // hier auf true setzen, damit nur deine echte App die Functions aufrufen kann.
  enforceAppCheck: false,
};

exports.ensureUserProfile = onCall(baseOptions, async (request) => {
  const uid = requireUid(request);
  const userRef = db.collection("users").doc(uid);

  const credits = await db.runTransaction(async (tx) => {
    const snap = await tx.get(userRef);
    if (snap.exists) return readCredits(snap);
    tx.set(userRef, {
      credits: FREE_CREDITS,
      createdAt: FieldValue.serverTimestamp(),
    });
    return FREE_CREDITS;
  });

  return { credits };
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
    const prompt = typeof request.data?.prompt === "string" ? request.data.prompt.trim() : "";
    if (!prompt) {
      throw new HttpsError("invalid-argument", "Bitte beschreibe, was erstellt werden soll.");
    }
    if (prompt.length > MAX_PROMPT_LENGTH) {
      throw new HttpsError(
        "invalid-argument",
        `Der Prompt ist zu lang (maximal ${MAX_PROMPT_LENGTH} Zeichen).`,
      );
    }

    const userRef = db.collection("users").doc(uid);

    // 1. Credit atomar abziehen. Neue Nutzer bekommen dabei ihr Startguthaben.
    const creditsLeft = await db.runTransaction(async (tx) => {
      const snap = await tx.get(userRef);
      const credits = snap.exists ? readCredits(snap) : FREE_CREDITS;
      if (credits <= 0) {
        // „resource-exhausted“ steht in der App ausschließlich für „keine Credits“.
        throw new HttpsError(
          "resource-exhausted",
          "Keine Credits mehr – bitte im Shop aufladen.",
          { credits: 0 },
        );
      }
      if (snap.exists) {
        tx.update(userRef, {
          credits: FieldValue.increment(-1),
          lastGenerationAt: FieldValue.serverTimestamp(),
        });
      } else {
        tx.set(userRef, {
          credits: FREE_CREDITS - 1,
          createdAt: FieldValue.serverTimestamp(),
          lastGenerationAt: FieldValue.serverTimestamp(),
        });
      }
      return credits - 1;
    });

    // 2. Generieren – bei jedem Fehler den Credit zurückbuchen.
    try {
      const html = await generateHtml(prompt);
      return { html, title: extractTitle(html), creditsLeft };
    } catch (error) {
      await refundCredit(userRef, uid);
      if (error instanceof HttpsError) throw error;
      logger.error("Generierung fehlgeschlagen", { uid, error: String(error) });
      throw new HttpsError(
        "internal",
        "Die Generierung ist fehlgeschlagen. Dein Credit wurde zurückgebucht.",
      );
    }
  },
);

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

async function generateHtml(prompt) {
  const ai = new GoogleGenAI({ apiKey: GEMINI_API_KEY.value() });

  let response;
  try {
    response = await ai.models.generateContent({
      model: GEMINI_MODEL,
      contents: buildUserPrompt(prompt),
      config: {
        systemInstruction: SYSTEM_PROMPT,
        abortSignal: AbortSignal.timeout(GEMINI_TIMEOUT_MS),
      },
    });
  } catch (error) {
    throw describeGeminiError(error);
  }

  const blockReason = response.promptFeedback?.blockReason;
  if (blockReason) {
    throw new HttpsError(
      "invalid-argument",
      `Der Prompt wurde von Gemini blockiert (${blockReason}). Dein Credit wurde zurückgebucht – bitte formuliere ihn um.`,
    );
  }
  if (response.candidates?.[0]?.finishReason === "MAX_TOKENS") {
    throw new HttpsError(
      "failed-precondition",
      "Die Antwort war zu lang und wurde abgeschnitten. Dein Credit wurde zurückgebucht – bitte vereinfache den Prompt.",
    );
  }

  const html = cleanHtml(response.text ?? "");
  if (!html) {
    throw new HttpsError(
      "internal",
      "Gemini hat keinen HTML-Code geliefert. Dein Credit wurde zurückgebucht – bitte erneut versuchen.",
    );
  }
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
      "Gemini hat nicht rechtzeitig geantwortet. Dein Credit wurde zurückgebucht – bitte erneut versuchen.",
    );
  }
  if (status === 400 || status === 401 || status === 403 || status === 404) {
    // Falscher Key oder Modellname auf dem Server – Details stehen im Log.
    return new HttpsError(
      "internal",
      "Der Generierungsdienst ist falsch konfiguriert. Dein Credit wurde zurückgebucht.",
    );
  }
  return new HttpsError(
    "unavailable",
    "Gemini ist gerade überlastet oder nicht erreichbar. Dein Credit wurde zurückgebucht – bitte später erneut versuchen.",
  );
}

async function refundCredit(userRef, uid) {
  try {
    await userRef.update({ credits: FieldValue.increment(1) });
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
