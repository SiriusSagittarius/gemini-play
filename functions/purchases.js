/**
 * Google-Play-Käufe: Produkte, Prüfung von Kaufbelegen und Hilfsfunktionen.
 *
 * Voraussetzung: Das Dienstkonto der Functions ist in der Play Console unter
 * „Nutzer und Berechtigungen“ eingeladen (Finanzdaten ansehen, Bestellungen
 * verwalten) und die „Google Play Android Developer API“ ist aktiviert.
 */

const crypto = require("node:crypto");
const { HttpsError } = require("firebase-functions/v2/https");
const { androidpublisher, auth } = require("@googleapis/androidpublisher");

const PACKAGE_NAME = "com.promptplay.promptplay";

/** Produkt-ID aus der Play Console → Anzahl gutgeschriebener Credits. */
const PRODUCTS = { credits_10: 10, credits_30: 30, credits_70: 70 };

let client;
function playClient() {
  client ??= androidpublisher({
    version: "v3",
    auth: new auth.GoogleAuth({ scopes: ["https://www.googleapis.com/auth/androidpublisher"] }),
  });
  return client;
}

function sha256(value) {
  return crypto.createHash("sha256").update(value).digest("hex");
}

/** Gleiche Kennung, die die App beim Kauf an Google Play übergibt. */
function accountIdFor(uid) {
  return sha256(uid);
}

function purchaseDocId(purchaseToken) {
  return sha256(purchaseToken);
}

/**
 * Prüft Status und Kontozuordnung eines Kaufs (ProductPurchase der
 * Android Publisher API) und wirft, wenn er nicht gutgeschrieben werden darf.
 */
function checkPurchase(purchase, expectedAccountId) {
  if (purchase.purchaseState === 2) {
    throw new HttpsError(
      "failed-precondition",
      "Die Zahlung ist noch nicht abgeschlossen. Die Credits werden gutgeschrieben, sobald Google Play sie bestätigt.",
      { pending: true },
    );
  }
  if (purchase.purchaseState !== 0) {
    throw new HttpsError("failed-precondition", "Dieser Kauf wurde storniert.");
  }
  if (
    purchase.obfuscatedExternalAccountId &&
    purchase.obfuscatedExternalAccountId !== expectedAccountId
  ) {
    throw new HttpsError("permission-denied", "Dieser Kauf gehört zu einem anderen Konto.");
  }
}

async function fetchPurchase(productId, purchaseToken) {
  const response = await playClient().purchases.products.get({
    packageName: PACKAGE_NAME,
    productId,
    token: purchaseToken,
  });
  return response.data;
}

async function consumePurchase(productId, purchaseToken) {
  await playClient().purchases.products.consume({
    packageName: PACKAGE_NAME,
    productId,
    token: purchaseToken,
  });
}

module.exports = {
  PRODUCTS,
  sha256,
  accountIdFor,
  purchaseDocId,
  checkPurchase,
  fetchPurchase,
  consumePurchase,
};
