import { Box, Button, Container, Flex, Heading, Input, Text } from '@chakra-ui/react';
import { Table, Thead, Tbody, Tr, Th, Td, Spinner } from '@chakra-ui/react';
import { observer } from 'mobx-react-lite';
import React, { useEffect, useMemo, useRef, useState } from 'react';
import { BlueTitleBar } from '../../shared/base/blue-title-bar';

// ============================================================
// SECTION 00 — FILE OVERVIEW
// PURPOSE: AI Admin screen (manual admin actions for Claims/GenAI subsystem)
// ============================================================
//
// Phase 1 goal:
// - Button: "Create new session"
// - Admin types contractor_id (UUID) into a textbox (default provided)
// - Calls backend endpoint (POST /api/claims/sessions)
// - Receives { session_id: "uuid" } (or similar)
// - Displays the created session id on-screen for the admin
//
// Added:
// - session_id is editable (Input)
// - Button: "New upload" opens file chooser for PDFs, then POSTs to:
//     POST /api/claims/sessions/:session_id/upload
//   passing session_id + PDF(s) in multipart/form-data.
//
// Added (support/troubleshooting-friendly):
// - "Run Output" panel that shows the LAST response JSON returned by create/upload.
// - If backend returns messages[] / run_id / correlation_id etc, it will show it.
//   This helps phone support without needing docker logs.
// ============================================================

// ============================================================
// SECTION 01 — API CONTRACT (TEMP)
// PURPOSE: Keep response parsing in one place so backend changes are easy
// ============================================================

type CreateSessionResponse =
  | { session_id: string }
  | { id: string }
  | { sessionId: string }
  | { session?: { id?: string } }
  | any;

// ============================================================
// SECTION 02 — HELPERS
// ============================================================

function safeJsonStringify(obj: any): string {
  try {
    return JSON.stringify(obj, null, 2);
  } catch (e) {
    return String(obj);
  }
}

function tryGetSessionIdFromCreateResponse(data: CreateSessionResponse): string {
  const sid = data?.session_id ?? data?.id ?? data?.sessionId ?? data?.session?.id ?? '';
  return sid ? String(sid) : '';
}

function guessMessagesFromResponse(data: any): string[] {
  // If backend provides messages already, use it.
  const msgs = data?.messages ?? data?.logs ?? data?.debug_lines ?? data?.debug ?? null;
  if (Array.isArray(msgs)) return msgs.map((x) => String(x));
  if (typeof msgs === 'string') return [msgs];

  // Otherwise, try a few common shapes:
  if (Array.isArray(data?.results)) {
    return [`results: ${data.results.length} item(s)`];
  }

  return [];
}





// ============================================================
// SECTION 03 — SCREEN COMPONENT
// ============================================================

export const AIAdminScreen = observer(function AIAdminScreen() {
  // ============================================================
  // SECTION 03.01 — STATE
  // ============================================================

  // ============================================================
  // SECTION 03.01.01 — INPUT FIELDS (EDITABLE)
  // PURPOSE: Admin can type/paste ids; handlers may populate them.
  // ============================================================

  const DEFAULT_RULESET_ID = '4bf85215-6bb3-4533-b0a2-f73e0d9b6cd6';

  const [contractorId, setContractorId] = useState<string>('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');

  // Editable session id
  const [sessionId, setSessionId] = useState<string>('');

// Editable ids (populated from responses, but admin can override)
const [invoiceId, setInvoiceId] = useState<string>('');
const [invoiceVersionId, setInvoiceVersionId] = useState<string>('');

// x.03.01.01.25 — Editable ruleset id (admin can paste a fresh UUID)
// PURPOSE: Avoid stale hardcoded DEFAULT_RULESET_ID when rulesets are reloaded.
const [validationGenaiRulesetId, setValidationGenaiRulesetId] =
  useState<string>(DEFAULT_RULESET_ID);


  // ============================================================
  // SECTION 03.01.02 — CREATE SESSION UI STATE
  // ============================================================

  // Create session
  const [isCreatingSession, setIsCreatingSession] = useState<boolean>(false);
  const [createSessionError, setCreateSessionError] = useState<string>('');

  // ============================================================
  // SECTION 03.01.03 — UPLOAD UI STATE and other 1 off buttons
  // ============================================================


  // Upload
  const fileInputRef = useRef<HTMLInputElement | null>(null);
  const [selectedFiles, setSelectedFiles] = useState<File[]>([]);
  const [isUploading, setIsUploading] = useState<boolean>(false);
  const [uploadError, setUploadError] = useState<string>('');
  const [uploadOkMsg, setUploadOkMsg] = useState<string>('');

  


// ============================================================
// SECTION 03.01.03.01 — END-TO-END UI STATE
// PURPOSE: Track the end-to-end ingest button progress + messages.
// ============================================================

const [isRunningEndToEnd, setIsRunningEndToEnd] = useState<boolean>(false);
const [endToEndError, setEndToEndError] = useState<string>('');
const [endToEndOkMsg, setEndToEndOkMsg] = useState<string>('');

// ============================================================
// SECTION 03.01.03.02 — OCR UI STATE
// ============================================================

const [isRunningOcr, setIsRunningOcr] = useState<boolean>(false);
const [ocrError, setOcrError] = useState<string>('');
const [ocrOkMsg, setOcrOkMsg] = useState<string>('');

// ============================================================
// SECTION 03.01.03.03 — GENAI UI STATE
// ============================================================

const [isRunningGenai, setIsRunningGenai] = useState<boolean>(false);
const [genaiError, setGenaiError] = useState<string>('');
const [genaiOkMsg, setGenaiOkMsg] = useState<string>('');

  // ============================================================
  // SECTION 03.01.04 — RUN OUTPUT PANEL STATE
  // PURPOSE: Show last response JSON for troubleshooting.
  // ============================================================

  // Run Output panel
  const [lastActionLabel, setLastActionLabel] = useState<string>('(none)');
  const [lastHttpStatus, setLastHttpStatus] = useState<number | null>(null);
  const [lastResponseJson, setLastResponseJson] = useState<any>(null);
  const [lastResponseTextFallback, setLastResponseTextFallback] = useState<string>('');
  const [showRunOutput, setShowRunOutput] = useState<boolean>(true);

  // ============================================================
  // SECTION 03.01.05 — DERIVED DISPLAY VALUES
  // PURPOSE: Pretty-print JSON + extract messages list.
  // ============================================================


  const lastResponsePretty = useMemo(() => {
    if (lastResponseJson != null) return safeJsonStringify(lastResponseJson);
    if (lastResponseTextFallback) return lastResponseTextFallback;
    return '';
  }, [lastResponseJson, lastResponseTextFallback]);

  const derivedMessages = useMemo(() => {
    if (!lastResponseJson) return [];
    return guessMessagesFromResponse(lastResponseJson);
  }, [lastResponseJson]);

// ============================================================
// SECTION 03.01.06 — RUN TRACKER (2 GRIDS)
// ============================================================

type IngestRunRow = {
  id: string;
  session_id: string;
  status?: string;
  total_files?: number;
  completed_files?: number;
  failed_files?: number;
  created_at?: string;
  updated_at?: string;
  completed_at?: string | null;
};

type IngestStepRow = {
  id: string;
  ingest_run_id: string;
  invoice_version_id?: string | null;
  step_type?: string;
  ok?: boolean;
  error_text?: string | null;
  validationgenai_ruleset_id?: string | null;
  created_at?: string;
  updated_at?: string;
};

const [runsLoading, setRunsLoading] = useState<boolean>(false);
const [runsError, setRunsError] = useState<string>('');
const [runs, setRuns] = useState<IngestRunRow[]>([]);

const [selectedRunId, setSelectedRunId] = useState<string>('');

const [stepsLoading, setStepsLoading] = useState<boolean>(false);
const [stepsError, setStepsError] = useState<string>('');
const [steps, setSteps] = useState<IngestStepRow[]>([]);

const fmtTs = (s?: string | null) => (s ? String(s).replace('T', ' ').replace('Z', '') : '');



  // ============================================================
  // SECTION 03.02 — EVENT HANDLERS
  // ============================================================

  // ============================================================
  // SECTION 03.02.01 — RUN OUTPUT HELPERS
  // ============================================================

  const clearRunOutput = () => {
    setLastActionLabel('(none)');
    setLastHttpStatus(null);
    setLastResponseJson(null);
    setLastResponseTextFallback('');
  };

  const captureRunOutput = (label: string, status: number, json: any, textFallback: string = '') => {
    setLastActionLabel(label);
    setLastHttpStatus(status);
    setLastResponseJson(json);
    setLastResponseTextFallback(textFallback);
  };

  // ============================================================
  // SECTION 03.02.02 — CREATE SESSION HANDLERS
  // ============================================================

  const handleCreateNewSession = async () => {
    setIsCreatingSession(true);
    setCreateSessionError('');
    setUploadError('');
    setUploadOkMsg('');
    setSelectedFiles([]);
    clearRunOutput();
setInvoiceId('');
setInvoiceVersionId('');

    try {
      if (!contractorId.trim()) {
        throw new Error('Please enter a contractor_id (UUID) first.');
      }

      const res = await fetch('/api/claims/sessions', {
        method: 'POST',
        headers: {
          Accept: 'application/json',
          'Content-Type': 'application/json',
        },
        credentials: 'include',
        body: JSON.stringify({
          contractor_id: contractorId.trim(),
        }),
      });

      setLastHttpStatus(res.status);

      // Try JSON first, then fallback to text
      let data: any = null;
      let textFallback = '';
      const contentType = res.headers.get('content-type') || '';
      if (contentType.includes('application/json')) {
        data = await res.json();
      } else {
        textFallback = await res.text().catch(() => '');
      }

      if (!res.ok) {
        captureRunOutput('Create session', res.status, data, textFallback);
        const errText =
          (data && (data.error || data.message)) ||
          textFallback ||
          `HTTP ${res.status} ${res.statusText}`;
        throw new Error(String(errText));
      }

      captureRunOutput('Create session', res.status, data, textFallback);

      const sid = tryGetSessionIdFromCreateResponse(data);
      if (!sid) {
        throw new Error('Endpoint returned JSON but no session id field was found.');
      }

      setSessionId(sid);
    } catch (err: any) {
      setCreateSessionError(err?.message || 'Failed to create session.');
    } finally {
      setIsCreatingSession(false);
    }
  };

// ============================================================
// SECTION 03.02.02.01 — RUN TRACKER HANDLERS (INSIDE COMPONENT)
// PURPOSE:
// - Fetch ingest_step_runs filtered by session_id (single-grid screen)
// - Uses Run Output panel for debugging
// ============================================================

const fetchStepsBySession = async () => {
  setStepsLoading(true);
  setStepsError('');
  setSteps([]);

  try {
    if (!sessionId.trim()) {
      throw new Error('Please enter a session_id first.');
    }

    const params = new URLSearchParams();
    params.set('session_id', sessionId.trim());
    params.set('limit', '200');

    const url = `/api/claims/ingest/steps?${params.toString()}`;

    const res = await fetch(url, {
      method: 'GET',
      headers: { Accept: 'application/json' },
      credentials: 'include',
    });

    const data = await res.json().catch(() => ({}));

    // Reuse your existing Run Output panel
    captureRunOutput('Refresh steps', res.status, data, '');

    if (!res.ok) {
      throw new Error(data?.error || data?.message || `HTTP ${res.status}`);
    }

    setSteps(Array.isArray(data?.steps) ? data.steps : []);
  } catch (e: any) {
    setStepsError(e?.message || 'Failed to load steps.');
  } finally {
    setStepsLoading(false);
  }
};




// ============================================================
// SECTION 03.02.03 — UPLOAD HANDLERS
// PURPOSE: Admin-only “New upload” for testing.
// RULES:
// - Single-file ONLY (no multi-select, no loop mental-map confusion)
// - Requires session_id to be provided (paste/create first)
// ============================================================

// ============================================================
// SECTION 03.02.03.01 — OPEN FILE CHOOSER
// ============================================================

const openFileChooser = () => {
  setUploadError('');
  setUploadOkMsg('');
  if (!sessionId.trim()) {
    setUploadError('Please enter a session_id first (or create one).');
    return;
  }
  fileInputRef.current?.click();
};

// ============================================================
// SECTION 03.02.03.02 — FILE PICKED (SINGLE-FILE ONLY)
// PURPOSE:
// - Force exactly one file
// - Clear <input> so same file can be re-selected
// ============================================================

const handleFilesChosen = async (e: React.ChangeEvent<HTMLInputElement>) => {
  setUploadError('');
  setUploadOkMsg('');

  const files = Array.from(e.target.files || []);
  const firstFile = files[0] ?? null;

  // let the same file be selected again later
  e.target.value = '';

  if (!firstFile) return;

  // ADMIN RULE: New upload is single-file only (testing tool)
  setSelectedFiles([firstFile]);

  if (!sessionId.trim()) {
    setUploadError('Please enter a session_id first (or create one).');
    return;
  }

  await uploadFiles(sessionId.trim(), firstFile);
};

// ============================================================
// SECTION 03.02.03.03 — DO UPLOAD (SINGLE FILE)
// PURPOSE: Calls Rails upload endpoint using multipart/form-data.
// NOTE: End-to-end pipeline will do looping elsewhere (NOT here).
// ============================================================

const uploadFiles = async (sid: string, file: File) => {
  setIsUploading(true);
  setUploadError('');
  setUploadOkMsg('');
  clearRunOutput();

// ============================================================
// SECTION 03.02.03.03.05 — CLEAR OCR STATUS ON NEW UPLOAD
// PURPOSE: New upload changes invoice_version_id; clear stale OCR messages.
// ============================================================

setOcrError('');
setOcrOkMsg('');



  try {
    const endpoint = `/api/claims/sessions/${encodeURIComponent(sid)}/upload`;

    const form = new FormData();
    form.append('session_id', sid);
    form.append('pdfs[]', file, file.name); // single file

    const res = await fetch(endpoint, {
      method: 'POST',
      credentials: 'include',
      body: form,
    });

    setLastHttpStatus(res.status);

    let data: any = null;
    let textFallback = '';
    const contentType = res.headers.get('content-type') || '';
    if (contentType.includes('application/json')) {
      data = await res.json();
    } else {
      textFallback = await res.text().catch(() => '');
    }

    if (!res.ok) {
      captureRunOutput('New upload', res.status, data, textFallback);
      const errText =
        (data && (data.error || data.message)) ||
        textFallback ||
        `HTTP ${res.status} ${res.statusText}`;
      throw new Error(String(errText));
    }

    captureRunOutput('New upload', res.status, data, textFallback);

    // Populate editable ids if backend returned them
    const newInvoiceId = data?.invoice_id ?? data?.invoice?.id ?? '';
    const newInvoiceVersionId = data?.invoice_version_id ?? data?.invoice_version?.id ?? '';

    if (newInvoiceId) setInvoiceId(String(newInvoiceId));
    if (newInvoiceVersionId) setInvoiceVersionId(String(newInvoiceVersionId));

    // Prefer backend-provided summary if it exists
    const runId = data?.run_id ?? data?.upload_run_id ?? data?.correlation_id ?? '';
    const msg =
      data?.message ||
      data?.summary ||
      `Upload accepted for session ${sid} (1 file).${runId ? ` run_id=${runId}` : ''}`;

    setUploadOkMsg(String(msg));
  } catch (err: any) {
    setUploadError(err?.message || 'Upload failed.');
  } finally {
    setIsUploading(false);
  }
};


// ============================================================
// SECTION 03.02.04 — END-TO-END HANDLERS
// PURPOSE: One button that will create session + upload + OCR + GenAI.
// NOTE: For now this is a stub that calls a placeholder endpoint.
// ============================================================

const handleRunEndToEnd = async () => {
  setIsRunningEndToEnd(true);
  setEndToEndError('');
  setEndToEndOkMsg('');
  clearRunOutput();

  // optional: clear ids so you can see what got populated
  setSessionId('');
  setInvoiceId('');
  setInvoiceVersionId('');

  try {
    if (!contractorId.trim()) {
      throw new Error('Please enter a contractor_id (UUID) first.');
    }

    // STUB endpoint for now (we will implement in Rails next)
    const endpoint = `/api/claims/ingest/end_to_end`;

    const res = await fetch(endpoint, {
      method: 'POST',
      headers: {
        Accept: 'application/json',
        'Content-Type': 'application/json',
      },
      credentials: 'include',
      body: JSON.stringify({
        contractor_id: contractorId.trim(),
      }),
    });

    setLastHttpStatus(res.status);

    let data: any = null;
    let textFallback = '';
    const contentType = res.headers.get('content-type') || '';
    if (contentType.includes('application/json')) {
      data = await res.json();
    } else {
      textFallback = await res.text().catch(() => '');
    }

    if (!res.ok) {
      captureRunOutput('End-to-end', res.status, data, textFallback);
      const errText =
        (data && (data.error || data.message)) ||
        textFallback ||
        `HTTP ${res.status} ${res.statusText}`;
      throw new Error(String(errText));
    }

    captureRunOutput('End-to-end', res.status, data, textFallback);

    // Populate ids if returned
    const newSessionId = data?.session_id ?? data?.session?.id ?? '';
    const newInvoiceId = data?.invoice_id ?? data?.invoice?.id ?? '';
    const newInvoiceVersionId = data?.invoice_version_id ?? data?.invoice_version?.id ?? '';

    if (newSessionId) setSessionId(String(newSessionId));
    if (newInvoiceId) setInvoiceId(String(newInvoiceId));
    if (newInvoiceVersionId) setInvoiceVersionId(String(newInvoiceVersionId));

    const runId = data?.run_id ?? data?.correlation_id ?? '';
    const msg =
      data?.message ||
      data?.summary ||
      `End-to-end run started.${runId ? ` run_id=${runId}` : ''}`;

    setEndToEndOkMsg(String(msg));
  } catch (err: any) {
    setEndToEndError(err?.message || 'End-to-end failed.');
  } finally {
    setIsRunningEndToEnd(false);
  }
};


// ============================================================
// SECTION 03.02.05 — OCR HANDLER (Run OCR button)
// PURPOSE:
// - Calls Rails: POST /api/claims/ingest/run_ocr
// - Uses session_id + invoice_version_id (from textboxes)
// - Captures Run Output panel JSON for phone-support style debugging
// ============================================================

const handleRunOcr = async () => {
  // 3.2.5.1 — UI state reset
  setIsRunningOcr(true);
  setOcrError('');
  setOcrOkMsg('');
  clearRunOutput();

  try {
    // 3.2.5.2 — Basic validation (these are required for OCR step)
    if (!sessionId.trim()) {
      throw new Error('Please enter a session_id first.');
    }
    if (!invoiceVersionId.trim()) {
      throw new Error('Please enter an invoice_version_id first (upload populates it).');
    }

    // 3.2.5.3 — Call Rails OCR endpoint
    const endpoint = `/api/claims/ingest/run_ocr`;

    const res = await fetch(endpoint, {
      method: 'POST',
      headers: {
        Accept: 'application/json',
        'Content-Type': 'application/json',
      },
      credentials: 'include',
      body: JSON.stringify({
        // 3.2.5.4 — Payload fields (match your Rails controller params)
        session_id: sessionId.trim(),
        invoice_version_id: invoiceVersionId.trim(),

        // optional: include model override if you want (otherwise omit)
        // model_id: 'prebuilt-invoice',
      }),
    });

    setLastHttpStatus(res.status);

    // 3.2.5.5 — Parse JSON (fallback to text if needed)
    let data: any = null;
    let textFallback = '';
    const contentType = res.headers.get('content-type') || '';
    if (contentType.includes('application/json')) {
      data = await res.json();
    } else {
      textFallback = await res.text().catch(() => '');
    }

    // 3.2.5.6 — Capture into Run Output panel (success or failure)
    captureRunOutput('Run OCR', res.status, data, textFallback);

    if (!res.ok) {
      const errText =
        (data && (data.error || data.message)) ||
        textFallback ||
        `HTTP ${res.status} ${res.statusText}`;
      throw new Error(String(errText));
    }

    // 3.2.5.7 — Success message for the OCR panel
    const stepRunId = data?.step_run_id ?? data?.ingest_step_run_id ?? data?.id ?? '';
    const msg =
      data?.message ||
      data?.summary ||
      `OCR queued/started for invoice_version_id=${invoiceVersionId.trim()}${stepRunId ? ` step_run_id=${stepRunId}` : ''}`;

    setOcrOkMsg(String(msg));

    // 3.2.5.8 — Optional: auto-refresh the step grid so you see the new row
    await fetchStepsBySession();
  } catch (err: any) {
    setOcrError(err?.message || 'Run OCR failed.');
  } finally {
    setIsRunningOcr(false);
  }
};

// ============================================================
// SECTION 03.02.05.50 — GENAI HANDLER (Run GenAI button)
// PURPOSE:
// - Milestone 1 only: call Rails stub endpoint
// - Use session_id + invoice_version_id (from textboxes)
// - Capture Run Output JSON
// ============================================================

const handleRunGenai = async () => {
  setIsRunningGenai(true);
  setGenaiError('');
  setGenaiOkMsg('');
  clearRunOutput();

  try {
    if (!sessionId.trim()) {
      throw new Error('Please enter a session_id first.');
    }
    if (!invoiceVersionId.trim()) {
      throw new Error('Please enter an invoice_version_id first (upload populates it).');
    }

    // Milestone 1 stub endpoint (Rails)
    const endpoint = `/api/claims/ingest/run_genai`;

    const res = await fetch(endpoint, {
      method: 'POST',
      headers: {
        Accept: 'application/json',
        'Content-Type': 'application/json',
      },
      credentials: 'include',
      body: JSON.stringify({
        session_id: sessionId.trim(),
        invoice_version_id: invoiceVersionId.trim(),
validationgenai_ruleset_id: validationGenaiRulesetId.trim(),
      }),
    });

    setLastHttpStatus(res.status);

    let data: any = null;
    let textFallback = '';
    const contentType = res.headers.get('content-type') || '';
    if (contentType.includes('application/json')) {
      data = await res.json();
    } else {
      textFallback = await res.text().catch(() => '');
    }

    // Always capture output (success or failure)
    captureRunOutput('Run GenAI', res.status, data, textFallback);

    if (!res.ok) {
      const errText =
        (data && (data.error || data.message)) ||
        textFallback ||
        `HTTP ${res.status} ${res.statusText}`;
      throw new Error(String(errText));
    }

    const stepRunId = data?.step_run_id ?? data?.ingest_step_run_id ?? data?.id ?? '';
    const msg =
      data?.message ||
      data?.summary ||
      `GenAI queued/started for invoice_version_id=${invoiceVersionId.trim()}${stepRunId ? ` step_run_id=${stepRunId}` : ''}`;

    setGenaiOkMsg(String(msg));

    // optional: refresh step grid (if your stub endpoint also writes a step row later)
    // await fetchStepsBySession();
  } catch (err: any) {
    setGenaiError(err?.message || 'Run GenAI failed.');
  } finally {
    setIsRunningGenai(false);
  }
};

// ============================================================
// SECTION 03.02.06 — OPEN READ SCREEN (NEW TAB)
// PURPOSE:
// - Opens the Rails read screen in a NEW browser tab
// - Uses the editable sessionId + invoiceId fields from the screen
// - Example target format:
//   http://localhost:3000/sessions/:session_id/invoices/:invoice_id/read
// ============================================================

const handleOpenReadScreen = () => {
  // basic validation
  if (!sessionId.trim()) {
    setUploadError('Please enter a session_id first (needed to open read screen).');
    return;
  }
  if (!invoiceId.trim()) {
    setUploadError('Please enter an invoice_id first (needed to open read screen).');
    return;
  }

  // build URL
  const url = `http://localhost:3000/sessions/${encodeURIComponent(
    sessionId.trim()
  )}/invoices/${encodeURIComponent(invoiceId.trim())}/read`;

  // open new tab
  window.open(url, '_blank', 'noopener,noreferrer');
};

  // ============================================================
  // SECTION 04 — RENDER
  // ============================================================

  // ============================================================
  // SECTION 04.01 — PAGE SHELL
  // ============================================================


  return (
    <Flex as="main" direction="column" w="full" bg="greys.white" pb="24" minH="100vh">
      <BlueTitleBar title="Admin - 1 off reruns" />

      <Container maxW="container.lg" pb={4} flex="1" pt={6}>
        <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="lg" p={5} bg="white">
          <Heading size="md" mb={2}>
            Ingest Manual Tools
          </Heading>

          <Text fontSize="sm" opacity={0.8} mb={4}>
            Create a new <code>claims.sessions</code> record (status <code>OPENBUTNOTSUBMITTED</code>) and then optionally
            upload PDF(s) into Azure for that session.
          </Text>

{/* ============================================================
    SECTION 04.01.50 — END-TO-END BUTTON (PRIMARY)
    PURPOSE: Run full ingest chain in one click (prod-style).
============================================================ */}

<Box mt={6} mb={6} p={4} borderWidth="1px" borderColor="greys.grey20" borderRadius="md" bg="gray.50">
  <Heading size="sm" mb={2}>
    End-to-end ingest
  </Heading>

  <Text fontSize="sm" opacity={0.8} mb={3}>
    Creates a new session and runs the full pipeline (upload → OCR → GenAI) in one action.
  </Text>

  <Button
    colorScheme="green"
    onClick={handleRunEndToEnd}
    isLoading={isRunningEndToEnd}
    loadingText="Running..."
    isDisabled={isCreatingSession || isUploading}
  >
    Run end-to-end
  </Button>

  {endToEndError && (
    <Box mt={3} p={3} bg="red.50" borderWidth="1px" borderColor="red.200" borderRadius="md">
      <Text fontSize="sm" color="red.700">
        {endToEndError}
      </Text>
    </Box>
  )}

  {endToEndOkMsg && (
    <Box mt={3} p={3} bg="green.50" borderWidth="1px" borderColor="green.200" borderRadius="md">
      <Text fontSize="sm" color="green.800">
        {endToEndOkMsg}
      </Text>
    </Box>
  )}
</Box>



{/* ============================================================
    SECTION 04.02 — CREATE SESSION INPUT
    PURPOSE: contractor_id input only (button is in the admin buttons row)
============================================================ */}

<Box mb={4}>
  <Text fontSize="xs" opacity={0.7} mb={1}>
    contractor_id (UUID)
  </Text>
  <Input
    value={contractorId}
    onChange={(e) => setContractorId(e.target.value)}
    placeholder="e.g. aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    bg="white"
    fontFamily="mono"
  />
</Box>


{/* ============================================================
    SECTION 04.02.02 — IDS (EDITABLE)
    PURPOSE: session_id / invoice_id / invoice_version_id
============================================================ */}

{/* session_id (editable) */}
<Box mt={5} mb={4}>
  <Text fontSize="xs" opacity={0.7} mb={1}>
    session_id (editable)
  </Text>
  <Input
    value={sessionId}
    onChange={(e) => setSessionId(e.target.value)}
    placeholder="session UUID will appear here (or type one)"
    bg="white"
    fontFamily="mono"
  />
  <Text fontSize="xs" opacity={0.6} mt={2}>
    Tip: you can paste an existing session id here if you want to upload to it.
  </Text>
</Box>

{/* invoice_id (editable) */}
<Box mb={4}>
  <Text fontSize="xs" opacity={0.7} mb={1}>
    invoice_id (editable)
  </Text>
  <Input
    value={invoiceId}
    onChange={(e) => setInvoiceId(e.target.value)}
    placeholder="invoice UUID will appear here after upload (or type one)"
    bg="white"
    fontFamily="mono"
  />
</Box>

{/* invoice_version_id (editable) */}
<Box mb={4}>
  <Text fontSize="xs" opacity={0.7} mb={1}>
    invoice_version_id (editable)
  </Text>
  <Input
    value={invoiceVersionId}
    onChange={(e) => setInvoiceVersionId(e.target.value)}
    placeholder="invoice_version UUID will appear here after upload (or type one)"
    bg="white"
    fontFamily="mono"
  />
</Box>

{/* x.04.02.02.40 — validationgenai_ruleset_id (editable) */}
<Box mb={4}>
  <Text fontSize="xs" opacity={0.7} mb={1}>
    validationgenai_ruleset_id (editable)
  </Text>
  <Input
    value={validationGenaiRulesetId}
    onChange={(e) => setValidationGenaiRulesetId(e.target.value)}
    placeholder="paste ruleset UUID here"
    bg="white"
    fontFamily="mono"
  />
</Box>


{/* ============================================================
    SECTION 04.03 — UPLOAD PANEL
============================================================ */}

<Box>
  {/* hidden file input (ADMIN: single file only) */}
  <input
    ref={fileInputRef}
    type="file"
    accept="application/pdf,.pdf"
    style={{ display: 'none' }}
    onChange={handleFilesChosen}
  />

  {/* ============================================================
      SECTION 04.03.01 — ADMIN BUTTONS ROW
      PURPOSE: One-off admin buttons, laid out side-by-side.
  ============================================================ */}

  <Box mt={3}>
    <Flex gap={3} wrap="wrap">
      <Button
        colorScheme="blue"
        onClick={handleCreateNewSession}
        isLoading={isCreatingSession}
        loadingText="Creating..."
        isDisabled={isUploading || isRunningEndToEnd}
      >
        Create new session
      </Button>

      <Button
        colorScheme="blue"
        onClick={openFileChooser}
        isLoading={isUploading}
        loadingText="Uploading..."
        isDisabled={isCreatingSession || isRunningEndToEnd}
      >
        Upload New invoice
      </Button>

      <Button variant="outline" isDisabled>
        Upload-fix +1 version
      </Button>

{/* ============================================================
    SECTION 04.03.01.20 — RUN OCR BUTTON
    PURPOSE: Calls Rails OCR endpoint and queues Sidekiq work
============================================================ */}

<Button
  colorScheme="blue"
  onClick={handleRunOcr}
  isLoading={isRunningOcr}
  loadingText="Running..."
  isDisabled={!sessionId.trim() || !invoiceVersionId.trim()}
>
  Run OCR
</Button>



<Button
  colorScheme="blue"
  onClick={handleRunGenai}
  isLoading={isRunningGenai}
  loadingText="Running..."
  isDisabled={!sessionId.trim() || !invoiceVersionId.trim()}
>
  Run GenAI
</Button>

    </Flex>
  </Box>


{/* ============================================================
    SECTION 04.03.01.25 — OPEN READ SCREEN BUTTON (NEW TAB)
    PURPOSE:
    - Opens the Rails read screen for the typed session_id + invoice_id
============================================================ */}

<Button
  colorScheme="purple"
  variant="outline"
  onClick={handleOpenReadScreen}
  isDisabled={!sessionId.trim() || !invoiceId.trim()}
>
  Open Confirm Details Screen
</Button>

  {/* ============================================================
      SECTION 04.03.02 — SELECTED FILE (ADMIN)
      PURPOSE: New upload is single-file only.
  ============================================================ */}

  {selectedFiles.length > 0 && (
    <Box mt={3}>
      <Text fontSize="xs" opacity={0.7}>
        Selected file
      </Text>

      <Text fontFamily="mono" fontSize="sm">
        {selectedFiles[0].name} ({Math.round(selectedFiles[0].size / 1024)} KB)
      </Text>
    </Box>
  )}

  {/* ============================================================
      SECTION 04.03.03 — MESSAGES
  ============================================================ */}

  <Box mt={4}>
    {createSessionError && (
      <Box mt={3} p={3} bg="red.50" borderWidth="1px" borderColor="red.200" borderRadius="md">
        <Text fontSize="sm" color="red.700">
          {createSessionError}
        </Text>
      </Box>
    )}

    {uploadError && (
      <Box mt={3} p={3} bg="red.50" borderWidth="1px" borderColor="red.200" borderRadius="md">
        <Text fontSize="sm" color="red.700">
          {uploadError}
        </Text>
      </Box>
    )}

    {uploadOkMsg && (
      <Box mt={3} p={3} bg="green.50" borderWidth="1px" borderColor="green.200" borderRadius="md">
        <Text fontSize="sm" color="green.800">
          {uploadOkMsg}
        </Text>
      </Box>
    )}

{/* ============================================================
    SECTION 04.03.03.20 — OCR MESSAGES
============================================================ */}

{ocrError && (
  <Box mt={3} p={3} bg="red.50" borderWidth="1px" borderColor="red.200" borderRadius="md">
    <Text fontSize="sm" color="red.700">
      {ocrError}
    </Text>
  </Box>
)}

{ocrOkMsg && (
  <Box mt={3} p={3} bg="green.50" borderWidth="1px" borderColor="green.200" borderRadius="md">
    <Text fontSize="sm" color="green.800">
      {ocrOkMsg}
    </Text>
  </Box>
)}


  </Box>
</Box>

{/* ============================================================
    SECTION 04.03.03.30 — GENAI MESSAGES
============================================================ */}

{genaiError && (
  <Box mt={3} p={3} bg="red.50" borderWidth="1px" borderColor="red.200" borderRadius="md">
    <Text fontSize="sm" color="red.700">
      {genaiError}
    </Text>
  </Box>
)}

{genaiOkMsg && (
  <Box mt={3} p={3} bg="green.50" borderWidth="1px" borderColor="green.200" borderRadius="md">
    <Text fontSize="sm" color="green.800">
      {genaiOkMsg}
    </Text>
  </Box>
)}

{/* ============================================================
    SECTION 04.03.50 — RUN TRACKER (SINGLE GRID)
    PURPOSE:
    - Show ingest_step_runs only
    - Filter by session_id textbox (sessionId state)
    - Use Run Output panel to show raw JSON from refresh
============================================================ */}

<Box mt={8} p={4} borderWidth="1px" borderColor="greys.grey20" borderRadius="md" bg="gray.50">
  <Flex align="center" justify="space-between" mb={3} wrap="wrap" gap={3}>
    <Box>
      <Heading size="sm">Step Run Tracker</Heading>
      <Text fontSize="xs" opacity={0.7}>
        Single grid: ingest_step_runs filtered by <code>session_id</code> (paste a session id above, then Refresh).
      </Text>
    </Box>

    <Flex gap={2}>
      {/* NOTE: Step 2.02 will wire this button to a new fetchStepsForSession() function.
          For now it just keeps your existing fetchRuns() so the section compiles. */}
<Button size="sm" onClick={fetchStepsBySession} isLoading={stepsLoading}>
        Refresh
      </Button>

      <Button
        size="sm"
        variant="outline"
        onClick={() => {
          setSteps([]);
          setStepsError('');
        }}
        isDisabled={steps.length === 0}
      >
        Clear
      </Button>
    </Flex>
  </Flex>

  {/* show errors (we will use stepsError going forward) */}
  {stepsError && (
    <Box mb={3} p={3} bg="red.50" borderWidth="1px" borderColor="red.200" borderRadius="md">
      <Text fontSize="sm" color="red.700">
        {stepsError}
      </Text>
    </Box>
  )}

  {/* GRID: STEPS ONLY */}
  <Box bg="white" borderWidth="1px" borderColor="greys.grey20" borderRadius="md" p={3}>
    <Flex align="center" justify="space-between" mb={2}>
      <Text fontSize="sm" fontWeight="bold">
        Steps (filtered by session_id)
      </Text>
      {stepsLoading && <Spinner size="sm" />}
    </Flex>

    <Table size="sm">
      <Thead>
        <Tr>
          <Th>created</Th>
          <Th>step_id</Th>
          <Th>type</Th>
          <Th>ok</Th>
          <Th>invoice_version_id</Th>
          <Th>ruleset</Th>
          <Th>error</Th>
        </Tr>
      </Thead>

      <Tbody>
        {steps.map((s) => (
          <Tr key={s.id}>
            <Td fontFamily="mono" fontSize="xs">
              {fmtTs(s.created_at)}
            </Td>
            <Td fontFamily="mono" fontSize="xs">
              {s.id}
            </Td>
            <Td fontFamily="mono" fontSize="xs">
              {s.step_type ?? ''}
            </Td>
            <Td fontFamily="mono" fontSize="xs">
              {String(s.ok ?? '')}
            </Td>
            <Td fontFamily="mono" fontSize="xs">
              {s.invoice_version_id ?? ''}
            </Td>
            <Td fontFamily="mono" fontSize="xs">
              {s.validationgenai_ruleset_id ?? ''}
            </Td>
            <Td fontFamily="mono" fontSize="xs" whiteSpace="pre-wrap">
              {s.error_text ?? ''}
            </Td>
          </Tr>
        ))}

        {!stepsLoading && steps.length === 0 && (
          <Tr>
            <Td colSpan={7}>
              <Text fontSize="sm" opacity={0.7}>
                Paste a session_id above and click Refresh.
              </Text>
            </Td>
          </Tr>
        )}
      </Tbody>
    </Table>
  </Box>
</Box>



          {/* ============================================================
              SECTION 04.04 — RUN OUTPUT (DEBUG)
              PURPOSE: Show last server response on-screen for phone support
          ============================================================ */}

          <Box mt={8} borderTopWidth="1px" borderTopColor="greys.grey20" pt={5}>
            <Flex align="center" justify="space-between" mb={2}>
              <Heading size="sm">Run Output</Heading>

              <Flex gap={2}>
                <Button size="sm" variant="ghost" onClick={() => setShowRunOutput((v) => !v)}>
                  {showRunOutput ? 'Hide' : 'Show'}
                </Button>
                <Button size="sm" variant="ghost" onClick={clearRunOutput} isDisabled={!lastResponsePretty}>
                  Clear
                </Button>
              </Flex>
            </Flex>

            <Text fontSize="xs" opacity={0.7} mb={3}>
              Shows the last JSON returned by the server for troubleshooting (useful for phone support). This does not
              replace server logs; it just exposes a safe, structured “run report”.
            </Text>

            {showRunOutput && (
              <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="md" p={4} bg="gray.50">
                <Flex mb={3} gap={6} wrap="wrap">
                  <Box>
                    <Text fontSize="xs" opacity={0.7}>
                      last_action
                    </Text>
                    <Text fontFamily="mono" fontSize="sm">
                      {lastActionLabel}
                    </Text>
                  </Box>

                  <Box>
                    <Text fontSize="xs" opacity={0.7}>
                      http_status
                    </Text>
                    <Text fontFamily="mono" fontSize="sm">
                      {lastHttpStatus ?? ''}
                    </Text>
                  </Box>

                  {lastResponseJson?.run_id && (
                    <Box>
                      <Text fontSize="xs" opacity={0.7}>
                        run_id
                      </Text>
                      <Text fontFamily="mono" fontSize="sm">
                        {String(lastResponseJson.run_id)}
                      </Text>
                    </Box>
                  )}

                  {lastResponseJson?.correlation_id && (
                    <Box>
                      <Text fontSize="xs" opacity={0.7}>
                        correlation_id
                      </Text>
                      <Text fontFamily="mono" fontSize="sm">
                        {String(lastResponseJson.correlation_id)}
                      </Text>
                    </Box>
                  )}
                </Flex>

                {derivedMessages.length > 0 && (
                  <Box mb={3}>
                    <Text fontSize="xs" opacity={0.7} mb={1}>
                      messages
                    </Text>
                    {derivedMessages.map((m, i) => (
                      <Text key={`${i}-${m}`} fontFamily="mono" fontSize="sm">
                        • {m}
                      </Text>
                    ))}
                  </Box>
                )}

                <Text fontSize="xs" opacity={0.7} mb={1}>
                  raw_response
                </Text>

                <Box
                  as="pre"
                  fontFamily="mono"
                  fontSize="xs"
                  whiteSpace="pre-wrap"
                  wordBreak="break-word"
                  m={0}
                  p={3}
                  bg="white"
                  borderWidth="1px"
                  borderColor="greys.grey20"
                  borderRadius="md"
                  maxH="360px"
                  overflow="auto"
                >
                  {lastResponsePretty || '(no response captured yet)'}
                </Box>
              </Box>
            )}
          </Box>
        </Box>
      </Container>
    </Flex>
  );
});
