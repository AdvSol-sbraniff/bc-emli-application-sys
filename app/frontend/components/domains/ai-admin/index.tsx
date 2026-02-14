import { Box, Button, Container, Flex, Heading, Input, Text } from '@chakra-ui/react';
import { observer } from 'mobx-react-lite';
import React, { useMemo, useRef, useState } from 'react';
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

  const [contractorId, setContractorId] = useState<string>('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');

  // Editable session id
  const [sessionId, setSessionId] = useState<string>('');

// Editable ids (populated from responses, but admin can override)
const [invoiceId, setInvoiceId] = useState<string>('');
const [invoiceVersionId, setInvoiceVersionId] = useState<string>('');

  // ============================================================
  // SECTION 03.01.02 — CREATE SESSION UI STATE
  // ============================================================

  // Create session
  const [isCreatingSession, setIsCreatingSession] = useState<boolean>(false);
  const [createSessionError, setCreateSessionError] = useState<string>('');

  // ============================================================
  // SECTION 03.01.03 — UPLOAD UI STATE
  // ============================================================


  // Upload
  const fileInputRef = useRef<HTMLInputElement | null>(null);
  const [selectedFiles, setSelectedFiles] = useState<File[]>([]);
  const [isUploading, setIsUploading] = useState<boolean>(false);
  const [uploadError, setUploadError] = useState<string>('');
  const [uploadOkMsg, setUploadOkMsg] = useState<string>('');

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
  // SECTION 03.02.03 — UPLOAD HANDLERS
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

  const handleFilesChosen = async (e: React.ChangeEvent<HTMLInputElement>) => {
    setUploadError('');
    setUploadOkMsg('');

    const files = Array.from(e.target.files || []);
    setSelectedFiles(files);

    // let the same file be selected again later
    e.target.value = '';

    if (files.length === 0) return;

    if (!sessionId.trim()) {
      setUploadError('Please enter a session_id first (or create one).');
      return;
    }

    await uploadFiles(sessionId.trim(), files);
  };

  const uploadFiles = async (sid: string, files: File[]) => {
    setIsUploading(true);
    setUploadError('');
    setUploadOkMsg('');
    clearRunOutput();

    try {
      const endpoint = `/api/claims/sessions/${encodeURIComponent(sid)}/upload`;

      const form = new FormData();
      form.append('session_id', sid);
      files.forEach((f) => form.append('pdfs[]', f, f.name));

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
        `Upload accepted for session ${sid} (${files.length} file${files.length === 1 ? '' : 's'}).${
          runId ? ` run_id=${runId}` : ''
        }`;

      setUploadOkMsg(String(msg));
    } catch (err: any) {
      setUploadError(err?.message || 'Upload failed.');
    } finally {
      setIsUploading(false);
    }
  };

  // ============================================================
  // SECTION 04 — RENDER
  // ============================================================

  // ============================================================
  // SECTION 04.01 — PAGE SHELL
  // ============================================================


  return (
    <Flex as="main" direction="column" w="full" bg="greys.white" pb="24" minH="100vh">
      <BlueTitleBar title="AI Admin" />

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
              SECTION 04.02 — CREATE SESSION PANEL
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

          <Button
            colorScheme="blue"
            onClick={handleCreateNewSession}
            isLoading={isCreatingSession}
            loadingText="Creating..."
          >
            Create new session
          </Button>

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


          {/* ============================================================
              SECTION 04.03 — UPLOAD PANEL
          ============================================================ */}


          <Box>
            {/* hidden file input */}
            <input
              ref={fileInputRef}
              type="file"
              accept="application/pdf,.pdf"
              multiple
              style={{ display: 'none' }}
              onChange={handleFilesChosen}
            />

            <Button
              colorScheme="blue"
              onClick={openFileChooser}
              isLoading={isUploading}
              loadingText="Uploading..."
              isDisabled={isCreatingSession}
            >
              New upload
            </Button>

            {/* Selected files */}
            {selectedFiles.length > 0 && (
              <Box mt={3}>
                <Text fontSize="xs" opacity={0.7}>
                  Selected file(s)
                </Text>
                {selectedFiles.map((f) => (
                  <Text key={`${f.name}-${f.size}-${f.lastModified}`} fontFamily="mono" fontSize="sm">
                    {f.name} ({Math.round(f.size / 1024)} KB)
                  </Text>
                ))}
              </Box>
            )}

            {/* Messages */}
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
