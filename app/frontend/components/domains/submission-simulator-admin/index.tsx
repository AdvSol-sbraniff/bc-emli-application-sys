import React, { useCallback, useEffect, useRef, useState } from 'react';
import {
  Box,
  Button,
  Container,
  Drawer,
  DrawerBody,
  DrawerCloseButton,
  DrawerContent,
  DrawerHeader,
  DrawerOverlay,
  Flex,
  HStack,
  IconButton,
  Select,
  Table,
  Tbody,
  Td,
  Text,
  Th,
  Thead,
  Tooltip,
  Tr,
  useDisclosure,
  VStack,
} from '@chakra-ui/react';
import { ArrowsClockwise, Question, XCircle } from '@phosphor-icons/react';
import { useLocation, useNavigate } from 'react-router-dom';
import { ThinBlueTitleBar } from '../../shared/base/thin-blue-title-bar';
import { IngestRunMonitorTabs } from '../../shared/claims/ingest-run-monitor-tabs';

type ContractorRow = {
  id: string;
  business_name?: string | null;
};

function getParam(search: string, key: string): string {
  return new URLSearchParams(search).get(key) ?? '';
}

const contractorOptionLabel = (contractor: ContractorRow): string => {
  return contractor.business_name?.trim() || 'Unnamed contractor';
};

function setParams(
  navigate: ReturnType<typeof useNavigate>,
  location: ReturnType<typeof useLocation>,
  patch: Record<string, string>,
) {
  const params = new URLSearchParams(location.search);
  Object.entries(patch).forEach(([k, v]) => {
    if (!v) params.delete(k);
    else params.set(k, v);
  });
  const qs = params.toString();
  navigate(`${location.pathname}${qs ? `?${qs}` : ''}`, { replace: true });
}

function fileSizeMb(bytes: number) {
  return `${(bytes / (1024 * 1024)).toFixed(2)} MB`;
}

export default function SubmissionSimulatorAdminScreen() {
  const location = useLocation();
  const navigate = useNavigate();

  const contractorIdFromUrl = getParam(location.search, 'contractor_id');
  const runIdFromUrl = getParam(location.search, 'ingest_run_id');

  const [contractorId, setContractorId] = useState(contractorIdFromUrl);
  const [runId, setRunId] = useState(runIdFromUrl);

  const [contractors, setContractors] = useState<ContractorRow[]>([]);

  const [selectedFiles, setSelectedFiles] = useState<File[]>([]);
  const fileInputRef = useRef<HTMLInputElement | null>(null);
  const [isDragActive, setIsDragActive] = useState(false);
  const [submitLoading, setSubmitLoading] = useState(false);
  const [submitError, setSubmitError] = useState('');
  const [submitOk, setSubmitOk] = useState('');
  const [monitorRefreshToken, setMonitorRefreshToken] = useState(0);
  const { isOpen: isHelpOpen, onOpen: onHelpOpen, onClose: onHelpClose } = useDisclosure();

  useEffect(() => setContractorId(contractorIdFromUrl), [contractorIdFromUrl]);
  useEffect(() => setRunId(runIdFromUrl), [runIdFromUrl]);

  const loadContractors = useCallback(async () => {
    try {
      const params = new URLSearchParams({ page: '1', per: '200', sort: 'business_name:asc' });
      const res = await fetch(`/api/claims/admin/contractors?${params.toString()}`, {
        method: 'GET',
        headers: { Accept: 'application/json' },
        credentials: 'include',
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data?.error || data?.message || `HTTP ${res.status}`);
      setContractors(Array.isArray(data?.rows) ? data.rows : []);
    } catch {
      setContractors([]);
    }
  }, []);

  useEffect(() => {
    void loadContractors();
  }, [loadContractors]);

  const handleRunSubmission = async () => {
    setSubmitLoading(true);
    setSubmitError('');
    setSubmitOk('');
    try {
      if (!contractorId.trim()) throw new Error('Select a contractor first.');
      if (!selectedFiles.length) throw new Error('Select one or more evidence files.');

      const form = new FormData();
      if (contractorId.trim()) form.append('contractor_id', contractorId.trim());
      selectedFiles.forEach((f) => form.append('files[]', f, f.name));

      const res = await fetch('/api/claims/ingest/admin_submit_batch', {
        method: 'POST',
        credentials: 'include',
        body: form,
      });

      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data?.error || data?.message || `HTTP ${res.status}`);

      const nextRunId = String(data?.ingest_run_id || '').trim();
      const nextSessionId = String(data?.session_id || '').trim();
      if (!nextRunId) throw new Error('Run started but no ingest_run_id returned.');

      setRunId(nextRunId);

      setParams(navigate, location, {
        ingest_run_id: nextRunId,
        session_id: nextSessionId,
        contractor_id: contractorId,
      });

      setSubmitOk(`Contractor draft simulation started. Run ${nextRunId}.`);
      setSelectedFiles([]);
    } catch (e: any) {
      setSubmitError(e?.message || 'Failed to start contractor draft simulation.');
    } finally {
      setSubmitLoading(false);
    }
  };

  const openFilePicker = () => {
    fileInputRef.current?.click();
  };

  const mergeStagedFiles = (files: File[]) => {
    const supportedEvidenceFiles = files.filter((f) => {
      const type = String(f.type || '').toLowerCase();
      const name = String(f.name || '').toLowerCase();
      const byType = type === 'application/pdf' || type === 'image/jpeg' || type === 'image/png';
      const byExt = name.endsWith('.pdf') || name.endsWith('.jpg') || name.endsWith('.jpeg') || name.endsWith('.png');
      return byType || byExt;
    });

    if (!supportedEvidenceFiles.length) return;

    setSelectedFiles((prev: File[]) => {
      const next = [...prev];
      supportedEvidenceFiles.forEach((f: File) => {
        const alreadyStaged = next.some(
          (p) => p.name === f.name && p.size === f.size && p.lastModified === f.lastModified,
        );
        if (!alreadyStaged) next.push(f);
      });
      return next;
    });
  };

  const handleFilesPicked = (e: React.ChangeEvent<HTMLInputElement>) => {
    const files = Array.from(e.target.files || []) as File[];
    if (!files.length) return;

    mergeStagedFiles(files);

    e.target.value = '';
  };

  const handleDropZoneDragOver = (e: React.DragEvent<HTMLDivElement>) => {
    e.preventDefault();
    e.stopPropagation();
    if (!isDragActive) setIsDragActive(true);
  };

  const handleDropZoneDragLeave = (e: React.DragEvent<HTMLDivElement>) => {
    e.preventDefault();
    e.stopPropagation();
    setIsDragActive(false);
  };

  const handleDropZoneDrop = (e: React.DragEvent<HTMLDivElement>) => {
    e.preventDefault();
    e.stopPropagation();
    setIsDragActive(false);
    const files = Array.from(e.dataTransfer?.files || []) as File[];
    if (!files.length) return;
    mergeStagedFiles(files);
  };

  const removeStagedFile = (index: number) => {
    setSelectedFiles((prev) => prev.filter((_, i) => i !== index));
  };

  const clearStagedFiles = () => setSelectedFiles([]);

  return (
    <Flex as="main" direction="column" w="full" bg="greys.white" pb="24" minH="100vh">
      <ThinBlueTitleBar title="Contractor Draft Simulator" />

      <Container maxW="container.xl" pb={4} flex="1" pt={6}>
        <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="lg" p={5} bg="white">
          <Flex justify="flex-end" mb={3}>
            <HStack spacing={2}>
              <Tooltip label="Help: staged contractor draft processing and run tracking">
                <IconButton
                  aria-label="Open contractor draft simulator help"
                  icon={<Question size={18} />}
                  variant="outline"
                  onClick={onHelpOpen}
                />
              </Tooltip>
            </HStack>
          </Flex>

          <input
            ref={fileInputRef}
            type="file"
            multiple
            accept="application/pdf,image/jpeg,image/png,.pdf,.jpg,.jpeg,.png"
            style={{ display: 'none' }}
            onChange={handleFilesPicked}
          />

          <VStack spacing={4} align="stretch" mb={5}>
            <Box p={4} borderWidth="1px" borderColor="greys.grey20" borderRadius="md" bg="gray.50">
              <Text fontSize="sm" fontWeight="bold" mb={3}>
                Step 1: Run Context
              </Text>
              <Text fontSize="xs" opacity={0.75} mb={3}>
                A fresh session id is created automatically when the staged batch is submitted.
              </Text>
              <HStack spacing={3} wrap="wrap" align="end">
                <Box>
                  <Text fontSize="xs" opacity={0.7} mb={1}>
                    Contractor
                  </Text>
                  <Select value={contractorId} onChange={(e) => setContractorId(e.target.value)} w="330px">
                    <option value="">Select contractor...</option>
                    {contractors.map((c) => (
                      <option key={c.id} value={c.id}>
                        {contractorOptionLabel(c)}
                      </option>
                    ))}
                  </Select>
                </Box>
              </HStack>
            </Box>

            <Box p={4} borderWidth="1px" borderColor="greys.grey20" borderRadius="md" bg="white">
              <Flex justify="space-between" align="center" mb={3} wrap="wrap" gap={2}>
                <Text fontSize="sm" fontWeight="bold">
                  Step 2: Stage Evidence Files
                </Text>
                <HStack spacing={2}>
                  <Button variant="outline" onClick={openFilePicker}>
                    Add Files
                  </Button>
                  <Tooltip label="Clear all staged files">
                    <IconButton
                      aria-label="Clear all staged files"
                      icon={<XCircle size={18} />}
                      variant="ghost"
                      colorScheme="red"
                      onClick={clearStagedFiles}
                      isDisabled={!selectedFiles.length}
                    />
                  </Tooltip>
                </HStack>
              </Flex>

              <Box
                mb={3}
                p={6}
                borderWidth="2px"
                borderStyle="dashed"
                borderColor={isDragActive ? 'blue.400' : 'gray.300'}
                bg={isDragActive ? 'blue.50' : 'gray.50'}
                borderRadius="md"
                textAlign="center"
                transition="all 0.15s ease"
                onDragOver={handleDropZoneDragOver}
                onDragEnter={handleDropZoneDragOver}
                onDragLeave={handleDropZoneDragLeave}
                onDrop={handleDropZoneDrop}
              >
                <Text fontSize="sm" fontWeight="bold">
                  Drag and drop PDF, JPG, JPEG, or PNG files here
                </Text>
                <Text fontSize="xs" opacity={0.75} mt={1}>
                  or use Add Files to browse from your device
                </Text>
              </Box>

              <Box borderWidth="1px" borderRadius="md" overflow="auto">
                <Table size="sm" minW="760px">
                  <Thead bg="gray.50">
                    <Tr>
                      <Th>#</Th>
                      <Th>filename</Th>
                      <Th>size</Th>
                      <Th>type</Th>
                      <Th>action</Th>
                    </Tr>
                  </Thead>
                  <Tbody>
                    {selectedFiles.map((file, index) => (
                      <Tr key={`${file.name}-${file.size}-${file.lastModified}`}>
                        <Td fontSize="xs">{index + 1}</Td>
                        <Td fontSize="xs">{file.name}</Td>
                        <Td fontSize="xs">{fileSizeMb(file.size)}</Td>
                        <Td fontSize="xs">{file.type || 'application/octet-stream'}</Td>
                        <Td>
                          <Button size="xs" variant="ghost" colorScheme="red" onClick={() => removeStagedFile(index)}>
                            Remove
                          </Button>
                        </Td>
                      </Tr>
                    ))}
                    {selectedFiles.length === 0 && (
                      <Tr>
                        <Td colSpan={5}>
                          <Text fontSize="sm" opacity={0.7}>
                            No staged files yet. Click Add Files to build the batch.
                          </Text>
                        </Td>
                      </Tr>
                    )}
                  </Tbody>
                </Table>
              </Box>
            </Box>

            <Box p={4} borderWidth="1px" borderColor="greys.grey20" borderRadius="md" bg="gray.50">
              <Flex justify="space-between" align="center" wrap="wrap" gap={2} mb={3}>
                <Text fontSize="sm" fontWeight="bold">
                  Step 3: Submit and Monitor
                </Text>
                <HStack>
                  <Button
                    colorScheme="blue"
                    onClick={() => void handleRunSubmission()}
                    isLoading={submitLoading}
                    loadingText="Starting..."
                    isDisabled={!selectedFiles.length || !contractorId}
                  >
                    Create Contractor Drafts
                  </Button>
                  <Tooltip label="Refresh run context and grids">
                    <IconButton
                      aria-label="Refresh"
                      icon={<ArrowsClockwise size={18} />}
                      onClick={() => setMonitorRefreshToken((value) => value + 1)}
                      isDisabled={!runId}
                    />
                  </Tooltip>
                </HStack>
              </Flex>

              {submitError && (
                <Text fontSize="sm" color="red.700" mt={2}>
                  {submitError}
                </Text>
              )}
              {submitOk && (
                <Text fontSize="sm" color="green.700" mt={2}>
                  {submitOk}
                </Text>
              )}
            </Box>
          </VStack>

          <IngestRunMonitorTabs runId={runId} refreshToken={monitorRefreshToken} />
        </Box>
      </Container>

      <Drawer isOpen={isHelpOpen} placement="left" onClose={onHelpClose} size="xl">
        <DrawerOverlay />
        <DrawerContent>
          <DrawerCloseButton />
          <DrawerHeader>Contractor Draft Simulator Help</DrawerHeader>
          <DrawerBody>
            <VStack align="stretch" spacing={4}>
              <Box>
                <Text fontSize="sm" fontWeight="bold" mb={1}>
                  How this screen works
                </Text>
                <Text fontSize="sm">
                  Step 1 sets the contractor, Step 2 stages evidence files, and Step 3 creates contractor draft
                  invoices.
                </Text>
                <Text fontSize="sm" mt={1}>
                  Files are staged in browser memory until you click Create Contractor Drafts.
                </Text>
                <Text fontSize="sm" mt={1}>
                  Created invoices stop at genai_complete after OCR and GenAI. They do not get a submitter_id or
                  submitted_at until the contractor submits them to admin.
                </Text>
              </Box>

              <Box>
                <Text fontSize="sm" fontWeight="bold" mb={1}>
                  Overall tab
                </Text>
                <Text fontSize="sm">
                  One row per ingest bundle shell invoice in the selected run. Click it to inspect both staged-file and
                  resolved invoice step history.
                </Text>
                <Text fontSize="sm" mt={1}>
                  Progress indicator: spinner means active, green means complete, red means failed.
                </Text>
              </Box>

              <Box>
                <Text fontSize="sm" fontWeight="bold" mb={1}>
                  Step History tab
                </Text>
                <Text fontSize="sm">
                  Shows both staged-file steps and the later resolved invoice steps for the selected bundle invoice.
                </Text>
                <Text fontSize="sm" mt={1}>
                  State values: queued, in progress, succeeded, failed.
                </Text>
              </Box>

              <Box>
                <Text fontSize="sm" fontWeight="bold" mb={1}>
                  Troubleshooting
                </Text>
                <Text fontSize="sm">
                  If rows stay queued, verify Sidekiq claims worker is running and consuming claims queues.
                </Text>
                <Text fontSize="sm" mt={1}>
                  Use /sidekiq to inspect queue depth, busy jobs, retries, and active processes.
                </Text>
              </Box>
            </VStack>
          </DrawerBody>
        </DrawerContent>
      </Drawer>
    </Flex>
  );
}
