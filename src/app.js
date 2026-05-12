const DB_NAME = "korea-phone-ocr-db";
const DB_VERSION = 1;
const CONTACT_STORE = "contacts";
const SESSION_STORE = "import_sessions";
const OCR_MAX_SIZE = 2200;
const OCR_SCALE = 2;
const APP_BASE_URL = new URL("./", window.location.href);

const state = {
  db: null,
  queue: [],
  currentIndex: 0,
  selectedDecision: "",
  rawText: "",
  lastImport: null,
  contacts: [],
  previewUrl: "",
  selectedFile: null,
  selectedSourceName: "",
  previewBitmap: null,
  rotation: 0,
};

const $ = (selector) => document.querySelector(selector);
const $$ = (selector) => Array.from(document.querySelectorAll(selector));

const els = {
  storageStatus: $("#storageStatus"),
  totalCount: $("#totalCount"),
  todayCount: $("#todayCount"),
  pendingCount: $("#pendingCount"),
  cameraInput: $("#cameraInput"),
  imageInput: $("#imageInput"),
  imageReview: $("#imageReview"),
  previewCanvas: $("#previewCanvas"),
  rotateLeftButton: $("#rotateLeftButton"),
  rotateRightButton: $("#rotateRightButton"),
  extractButton: $("#extractButton"),
  progressPanel: $("#progressPanel"),
  progressLabel: $("#progressLabel"),
  progressValue: $("#progressValue"),
  progressFill: $("#progressFill"),
  importSummary: $("#importSummary"),
  resultNotice: $("#resultNotice"),
  detectedCount: $("#detectedCount"),
  duplicateCount: $("#duplicateCount"),
  newCount: $("#newCount"),
  rawTextOutput: $("#rawTextOutput"),
  startReviewButton: $("#startReviewButton"),
  emptyReviewState: $("#emptyReviewState"),
  reviewForm: $("#reviewForm"),
  reviewIndex: $("#reviewIndex"),
  reviewPhone: $("#reviewPhone"),
  companyInput: $("#companyInput"),
  phoneInput: $("#phoneInput"),
  addressInput: $("#addressInput"),
  nextButton: $("#nextButton"),
  searchInput: $("#searchInput"),
  statusFilter: $("#statusFilter"),
  exportButton: $("#exportButton"),
  historyList: $("#historyList"),
};

document.addEventListener("DOMContentLoaded", init);

async function init() {
  state.db = await openDatabase();
  await registerServiceWorker();
  bindEvents();
  await refreshContacts();
  renderStats();
  renderReview();
  renderHistory();
}

function bindEvents() {
  $$("[data-view-button]").forEach((button) => {
    button.addEventListener("click", () => showView(button.dataset.viewButton));
  });

  els.cameraInput.addEventListener("change", (event) => handleImageInput(event, "camera-capture"));
  els.imageInput.addEventListener("change", (event) => handleImageInput(event, "selected-image"));
  els.rotateLeftButton.addEventListener("click", () => rotatePreview(-90));
  els.rotateRightButton.addEventListener("click", () => rotatePreview(90));
  els.extractButton.addEventListener("click", extractSelectedImage);
  els.startReviewButton.addEventListener("click", () => showView("review"));
  els.reviewForm.addEventListener("submit", handleReviewSubmit);
  els.searchInput.addEventListener("input", renderHistory);
  els.statusFilter.addEventListener("change", renderHistory);
  els.exportButton.addEventListener("click", exportCsv);

  $$("[data-decision]").forEach((button) => {
    button.addEventListener("click", () => {
      state.selectedDecision = button.dataset.decision;
      $$("[data-decision]").forEach((item) => item.classList.toggle("is-selected", item === button));
      els.nextButton.disabled = false;
    });
  });
}

function showView(name) {
  $$("[data-view]").forEach((view) => view.classList.toggle("is-active", view.dataset.view === name));
  $$("[data-view-button]").forEach((button) => {
    button.classList.toggle("is-active", button.dataset.viewButton === name);
  });
}

function openDatabase() {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, DB_VERSION);

    request.onupgradeneeded = () => {
      const db = request.result;
      if (!db.objectStoreNames.contains(CONTACT_STORE)) {
        const store = db.createObjectStore(CONTACT_STORE, { keyPath: "id", autoIncrement: true });
        store.createIndex("normalized_phone", "normalizedPhone", { unique: true });
        store.createIndex("created_at", "createdAt");
        store.createIndex("status", "status");
      }

      if (!db.objectStoreNames.contains(SESSION_STORE)) {
        const store = db.createObjectStore(SESSION_STORE, { keyPath: "id", autoIncrement: true });
        store.createIndex("imported_at", "importedAt");
      }
    };

    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

function transaction(storeName, mode = "readonly") {
  return state.db.transaction(storeName, mode).objectStore(storeName);
}

function requestToPromise(request) {
  return new Promise((resolve, reject) => {
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

async function addRecord(storeName, record) {
  return requestToPromise(transaction(storeName, "readwrite").add(record));
}

async function putRecord(storeName, record) {
  return requestToPromise(transaction(storeName, "readwrite").put(record));
}

async function getAllRecords(storeName) {
  return requestToPromise(transaction(storeName).getAll());
}

async function getContactByPhone(normalizedPhone) {
  return requestToPromise(transaction(CONTACT_STORE).index("normalized_phone").get(normalizedPhone));
}

async function refreshContacts() {
  state.contacts = await getAllRecords(CONTACT_STORE);
  state.contacts.sort((a, b) => b.createdAt.localeCompare(a.createdAt));
}

async function handleImageInput(event, sourceName) {
  const file = event.target.files?.[0];
  if (!file) return;

  await loadImageForReview(file, file.name || sourceName);
  event.target.value = "";
}

async function loadImageForReview(file, sourceName) {
  clearImagePreview();
  resetImportSummary();
  state.selectedFile = file;
  state.selectedSourceName = sourceName;
  state.previewBitmap = await createImageBitmap(file);
  state.rotation = 0;
  els.imageReview.hidden = false;
  renderPreview();
}

async function extractSelectedImage() {
  if (!state.selectedFile) {
    alert("먼저 사진을 찍거나 이미지를 선택해주세요.");
    return;
  }

  els.extractButton.disabled = true;

  try {
    const text = await runOcr(state.selectedFile, state.rotation);
    await processRawText(text, state.selectedSourceName);
    clearImagePreview();
  } catch (error) {
    showProgress("OCR 실패", 0);
    console.error(error);
    alert("OCR 처리 중 문제가 발생했습니다. 페이지를 새로고침한 뒤 다시 시도해주세요.");
  } finally {
    els.extractButton.disabled = false;
  }
}

function rotatePreview(degrees) {
  if (!state.selectedFile) return;
  state.rotation = normalizeRotation(state.rotation + degrees);
  renderPreview();
}

function renderPreview() {
  if (!state.previewBitmap) return;

  const bitmap = state.previewBitmap;
  const isSideways = Math.abs(state.rotation) === 90 || Math.abs(state.rotation) === 270;
  const sourceWidth = isSideways ? bitmap.height : bitmap.width;
  const sourceHeight = isSideways ? bitmap.width : bitmap.height;
  const maxWidth = 1400;
  const scale = Math.min(1, maxWidth / sourceWidth);
  const canvas = els.previewCanvas;
  canvas.width = Math.max(1, Math.round(sourceWidth * scale));
  canvas.height = Math.max(1, Math.round(sourceHeight * scale));

  const context = canvas.getContext("2d");
  context.clearRect(0, 0, canvas.width, canvas.height);
  context.save();
  context.translate(canvas.width / 2, canvas.height / 2);
  context.rotate((state.rotation * Math.PI) / 180);
  const drawWidth = bitmap.width * scale;
  const drawHeight = bitmap.height * scale;
  context.drawImage(bitmap, -drawWidth / 2, -drawHeight / 2, drawWidth, drawHeight);
  context.restore();
}

function normalizeRotation(degrees) {
  return ((degrees % 360) + 360) % 360;
}

async function runOcr(file, rotation) {
  if (!window.Tesseract) {
    throw new Error("OCR 라이브러리를 불러오지 못했습니다. 인터넷 연결을 확인해주세요.");
  }

  showProgress("OCR 준비 중", 5);
  const bitmap = await createImageBitmap(file);

  try {
    const image = prepareImageForOcr(bitmap, rotation);
    showProgress("이미지 보정 중", 12);
    const result = await window.Tesseract.recognize(image, "kor+eng", {
      workerPath: assetUrl("vendor/tesseract/worker.min.js"),
      corePath: assetUrl("vendor/tesseract"),
      langPath: assetUrl("vendor/tessdata"),
      tessedit_pageseg_mode: "6",
      preserve_interword_spaces: "1",
      user_defined_dpi: "300",
      logger: (message) => {
        if (message.status === "recognizing text") {
          const percent = 12 + Math.round((message.progress || 0) * 88);
          showProgress("텍스트 추출 중", percent);
        }
      },
    });
    showProgress("OCR 완료", 100);
    return result.data.text || "";
  } finally {
    bitmap.close?.();
  }
}

function assetUrl(path) {
  return new URL(path, APP_BASE_URL).href;
}

function prepareImageForOcr(bitmap, rotation) {
  const largestSide = Math.max(bitmap.width, bitmap.height);
  const resizeRatio = Math.min(1, OCR_MAX_SIZE / largestSide);
  const width = Math.max(1, Math.round(bitmap.width * resizeRatio * OCR_SCALE));
  const height = Math.max(1, Math.round(bitmap.height * resizeRatio * OCR_SCALE));
  const isSideways = Math.abs(rotation) === 90;
  const canvas = document.createElement("canvas");
  canvas.width = isSideways ? height : width;
  canvas.height = isSideways ? width : height;
  const context = canvas.getContext("2d", { willReadFrequently: true });
  context.imageSmoothingEnabled = true;
  context.imageSmoothingQuality = "high";
  context.translate(canvas.width / 2, canvas.height / 2);
  context.rotate((rotation * Math.PI) / 180);
  context.drawImage(bitmap, -width / 2, -height / 2, width, height);
  context.setTransform(1, 0, 0, 1, 0, 0);

  const imageData = context.getImageData(0, 0, width, height);
  const data = imageData.data;
  let total = 0;

  for (let index = 0; index < data.length; index += 4) {
    const gray = data[index] * 0.299 + data[index + 1] * 0.587 + data[index + 2] * 0.114;
    total += gray;
  }

  const average = total / (data.length / 4);
  const threshold = Math.max(120, Math.min(190, average * 0.92));

  for (let index = 0; index < data.length; index += 4) {
    const gray = data[index] * 0.299 + data[index + 1] * 0.587 + data[index + 2] * 0.114;
    const contrast = (gray - 128) * 1.35 + 128;
    const value = contrast > threshold ? 255 : 0;
    data[index] = value;
    data[index + 1] = value;
    data[index + 2] = value;
  }

  context.putImageData(imageData, 0, 0);
  return canvas;
}

async function processRawText(text, sourceName) {
  state.rawText = text;
  const extracted = extractContacts(text);
  const uniqueCandidates = uniqueByPhone(extracted);
  const pending = [];
  let duplicateCount = 0;

  for (const candidate of uniqueCandidates) {
    const existing = await getContactByPhone(candidate.normalizedPhone);
    if (existing && isCompletedStatus(existing.status)) {
      duplicateCount += 1;
    } else {
      pending.push({ ...candidate, existingId: existing?.id || null });
    }
  }

  state.queue = pending;
  state.currentIndex = 0;
  state.selectedDecision = "";
  state.lastImport = {
    importedAt: new Date().toISOString(),
    sourceName,
    totalDetected: uniqueCandidates.length,
    duplicateCount,
    pendingCount: pending.length,
    savedCount: 0,
  };

  await addRecord(SESSION_STORE, state.lastImport);
  renderImportSummary(uniqueCandidates.length, duplicateCount, pending.length, text);
  renderStats();
  renderReview();
}

function extractContacts(text) {
  const lines = text
    .split(/\r?\n/)
    .map((line) => line.replace(/\s+/g, " ").trim())
    .filter(Boolean);

  const candidates = [];

  lines.forEach((line, index) => {
    const phoneMatches = findPhoneMatches(line);
    phoneMatches.forEach((match) => {
      const before = line.slice(0, match.index).trim();
      const after = line.slice(match.index + match.value.length).trim();
      const previous = lines[index - 1] || "";
      const next = lines[index + 1] || "";
      const companyName = pickCompanyName(before, previous, line);
      const address = pickAddress(after, before, next);

      candidates.push({
        companyName,
        phoneNumber: formatPhone(match.value),
        normalizedPhone: normalizePhone(match.value),
        address,
        ocrRawText: [previous, line, next].filter(Boolean).join("\n"),
      });
    });
  });

  return candidates.filter((candidate) => isValidKoreanPhone(candidate.normalizedPhone));
}

function findPhoneMatches(line) {
  const phonePattern = /(?:0(?:2|[3-6][1-5]|10|50[0-9]|70|80)[)\-\s.]*)?\d{3,4}[\-\s.]+\d{4}|0(?:2|[3-6][1-5]|10|50[0-9]|70|80)\d{7,8}/g;
  return Array.from(line.matchAll(phonePattern)).map((match) => ({
    value: match[0],
    index: match.index || 0,
  }));
}

function normalizePhone(value) {
  return String(value || "").replace(/\D/g, "");
}

function isValidKoreanPhone(value) {
  if (!value) return false;
  if (value.startsWith("02")) return value.length >= 9 && value.length <= 10;
  if (/^0(?:10|50\d|70|80)/.test(value)) return value.length >= 10 && value.length <= 12;
  if (/^0[3-6][1-5]/.test(value)) return value.length >= 10 && value.length <= 11;
  return false;
}

function formatPhone(value) {
  const digits = normalizePhone(value);
  if (digits.startsWith("02")) {
    if (digits.length === 9) return `${digits.slice(0, 2)}-${digits.slice(2, 5)}-${digits.slice(5)}`;
    if (digits.length === 10) return `${digits.slice(0, 2)}-${digits.slice(2, 6)}-${digits.slice(6)}`;
  }
  if (digits.length === 10) return `${digits.slice(0, 3)}-${digits.slice(3, 6)}-${digits.slice(6)}`;
  if (digits.length === 11) return `${digits.slice(0, 3)}-${digits.slice(3, 7)}-${digits.slice(7)}`;
  if (digits.length === 12 && digits.startsWith("050")) {
    return `${digits.slice(0, 4)}-${digits.slice(4, 8)}-${digits.slice(8)}`;
  }
  return value.trim();
}

function pickCompanyName(before, previous, fullLine) {
  const cleanedBefore = cleanText(before);
  if (cleanedBefore && !looksLikeAddress(cleanedBefore)) return cleanedBefore;

  const cleanedPrevious = cleanText(previous);
  if (cleanedPrevious && !looksLikeAddress(cleanedPrevious) && findPhoneMatches(cleanedPrevious).length === 0) {
    return cleanedPrevious;
  }

  return cleanText(fullLine.replace(/\d|[-().]/g, " ")).slice(0, 40);
}

function pickAddress(after, before, next) {
  const parts = [after, before, next].map(cleanText).filter(Boolean);
  return parts.find(looksLikeAddress) || parts.find((part) => part.length > 8) || "";
}

function cleanText(value) {
  return String(value || "")
    .replace(/[|_[\]{}]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function looksLikeAddress(value) {
  return /(서울|부산|대구|인천|광주|대전|울산|세종|경기|강원|충청|전라|경상|제주|특별시|광역시|도 |시 |군 |구 |읍 |면 |동 |리 |로 |길 )/.test(
    `${value} `
  );
}

function uniqueByPhone(candidates) {
  const map = new Map();
  candidates.forEach((candidate) => {
    if (!map.has(candidate.normalizedPhone)) map.set(candidate.normalizedPhone, candidate);
  });
  return Array.from(map.values());
}

function renderImportSummary(detected, duplicate, pending, rawText) {
  els.importSummary.hidden = false;
  els.detectedCount.textContent = detected;
  els.duplicateCount.textContent = duplicate;
  els.newCount.textContent = pending;
  els.rawTextOutput.textContent = rawText || "추출된 텍스트가 없습니다.";
  els.startReviewButton.disabled = pending === 0;
  renderResultNotice(detected, duplicate, pending, rawText);
}

function resetImportSummary() {
  els.importSummary.hidden = true;
  els.rawTextOutput.textContent = "";
  els.resultNotice.textContent = "";
  els.resultNotice.className = "result-notice";
  showProgress("OCR 준비 중", 0);
}

function renderResultNotice(detected, duplicate, pending, rawText) {
  els.resultNotice.className = "result-notice is-visible";

  if (detected === 0) {
    const hasText = rawText.trim().length > 0;
    els.resultNotice.classList.add("is-warning");
    els.resultNotice.textContent = hasText
      ? "전화번호를 찾지 못했습니다. 사진을 더 밝게 찍고, 표가 기울지 않게 다시 촬영해주세요."
      : "텍스트를 읽지 못했습니다. 초점을 맞춘 뒤 더 가까이에서 다시 촬영해주세요.";
    return;
  }

  if (pending === 0) {
    els.resultNotice.classList.add("is-info");
    els.resultNotice.textContent = "새로 처리할 전화번호가 없습니다. 감지된 번호가 모두 기존 DB에 있습니다.";
    return;
  }

  els.resultNotice.classList.add("is-success");
  els.resultNotice.textContent = `신규 전화번호 ${pending}건을 찾았습니다. 검토 시작을 누르면 업체별로 하나씩 확인합니다.`;
}

function clearImagePreview() {
  if (state.previewUrl) {
    URL.revokeObjectURL(state.previewUrl);
    state.previewUrl = "";
  }
  state.previewBitmap?.close?.();
  state.selectedFile = null;
  state.selectedSourceName = "";
  state.previewBitmap = null;
  state.rotation = 0;
  const context = els.previewCanvas.getContext("2d");
  context.clearRect(0, 0, els.previewCanvas.width, els.previewCanvas.height);
  els.previewCanvas.width = 0;
  els.previewCanvas.height = 0;
  els.imageReview.hidden = true;
}

function showProgress(label, value) {
  els.progressPanel.hidden = false;
  els.progressLabel.textContent = label;
  els.progressValue.textContent = `${value}%`;
  els.progressFill.style.width = `${Math.max(0, Math.min(100, value))}%`;
}

function renderReview() {
  els.pendingCount.textContent = state.queue.length;
  const item = state.queue[state.currentIndex];
  const hasItem = Boolean(item);

  els.emptyReviewState.hidden = hasItem;
  els.reviewForm.hidden = !hasItem;

  if (!hasItem) return;

  state.selectedDecision = "";
  $$("[data-decision]").forEach((button) => button.classList.remove("is-selected"));
  els.nextButton.disabled = true;
  els.reviewIndex.textContent = `${state.currentIndex + 1} / ${state.queue.length}`;
  els.reviewPhone.textContent = item.phoneNumber;
  els.companyInput.value = item.companyName || "";
  els.phoneInput.value = item.phoneNumber || "";
  els.addressInput.value = item.address || "";
}

async function handleReviewSubmit(event) {
  event.preventDefault();
  const item = state.queue[state.currentIndex];
  if (!item || !state.selectedDecision) return;

  const phoneNumber = els.phoneInput.value.trim();
  const normalizedPhone = normalizePhone(phoneNumber);
  if (!isValidKoreanPhone(normalizedPhone)) {
    alert("한국 전화번호 형식으로 인식할 수 없습니다.");
    return;
  }

  const existing = await getContactByPhone(normalizedPhone);
  const now = new Date().toISOString();
  const nextRecord = {
    companyName: els.companyInput.value.trim(),
    phoneNumber: formatPhone(phoneNumber),
    normalizedPhone,
    address: els.addressInput.value.trim(),
    status: state.selectedDecision,
    sourceDate: todayKey(),
    updatedAt: now,
    ocrRawText: item.ocrRawText || state.rawText,
  };

  if (existing) {
    await putRecord(CONTACT_STORE, {
      ...existing,
      ...nextRecord,
      createdAt: existing.createdAt || now,
    });
  } else {
    await addRecord(CONTACT_STORE, {
      ...nextRecord,
      createdAt: now,
    });
  }

  state.queue.splice(state.currentIndex, 1);
  if (state.currentIndex >= state.queue.length) {
    state.currentIndex = Math.max(0, state.queue.length - 1);
  }

  await refreshContacts();
  renderStats();
  renderReview();
  renderHistory();
}

function renderStats() {
  const today = todayKey();
  els.totalCount.textContent = state.contacts.length;
  els.todayCount.textContent = state.contacts.filter((contact) => contact.sourceDate === today).length;
  els.pendingCount.textContent = state.queue.length;
}

function renderHistory() {
  const keyword = els.searchInput.value.trim().toLowerCase();
  const status = els.statusFilter.value;

  const filtered = state.contacts.filter((contact) => {
    const matchesStatus = status === "all" || contact.status === status;
    const haystack = `${contact.companyName} ${contact.phoneNumber} ${contact.normalizedPhone} ${contact.address}`.toLowerCase();
    const matchesKeyword = !keyword || haystack.includes(keyword);
    return matchesStatus && matchesKeyword;
  });

  if (filtered.length === 0) {
    els.historyList.innerHTML = `<div class="panel empty-state"><h2>저장된 이력이 없습니다</h2><p>검토를 완료한 전화번호가 여기에 표시됩니다.</p></div>`;
    return;
  }

  els.historyList.innerHTML = filtered
    .map(
      (contact) => `
        <article class="history-item">
          <header>
            <strong>${escapeHtml(contact.companyName || "업체명 없음")}</strong>
            <span class="status-pill ${normalizeStatusForClass(contact.status)}">${statusLabel(contact.status)}</span>
          </header>
          <div class="history-meta">
            <span>${escapeHtml(contact.phoneNumber)}</span>
            <span>${escapeHtml(contact.address || "주소 없음")}</span>
            <span>${formatDateTime(contact.createdAt)}</span>
          </div>
        </article>
      `
    )
    .join("");
}

function exportCsv() {
  const header = ["날짜", "업체명", "전화번호", "주소", "상태"];
  const rows = state.contacts.map((contact) => [
    formatDateTime(contact.createdAt),
    contact.companyName,
    contact.phoneNumber,
    contact.address,
    statusLabel(contact.status),
  ]);
  const csv = [header, ...rows].map((row) => row.map(csvCell).join(",")).join("\n");
  const blob = new Blob(["\ufeff", csv], { type: "text/csv;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = `phone-ocr-db-${todayKey()}.csv`;
  link.click();
  URL.revokeObjectURL(url);
}

function csvCell(value) {
  return `"${String(value || "").replace(/"/g, '""')}"`;
}

function todayKey() {
  const now = new Date();
  const year = now.getFullYear();
  const month = String(now.getMonth() + 1).padStart(2, "0");
  const day = String(now.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function formatDateTime(value) {
  if (!value) return "";
  return new Intl.DateTimeFormat("ko-KR", {
    dateStyle: "short",
    timeStyle: "short",
  }).format(new Date(value));
}

function escapeHtml(value) {
  return String(value || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

function isCompletedStatus(status) {
  return ["accepted", "rejected", "called", "deleted"].includes(status);
}

function statusLabel(status) {
  const labels = {
    missed: "부재중",
    rejected: "거절",
    accepted: "승락",
    called: "전화했음",
    deleted: "지우기",
  };
  return labels[status] || "미확인";
}

function normalizeStatusForClass(status) {
  if (status === "called") return "accepted";
  if (status === "deleted") return "rejected";
  return status || "missed";
}

async function registerServiceWorker() {
  if (!("serviceWorker" in navigator)) return;
  try {
    await navigator.serviceWorker.register("./service-worker.js");
    els.storageStatus.textContent = "PWA 준비됨";
  } catch {
    els.storageStatus.textContent = "로컬 DB";
  }
}
