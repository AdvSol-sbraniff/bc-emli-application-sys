import {
  Badge,
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
  Heading,
  Input,
  Spinner,
  Text,
  Tooltip,
  useDisclosure,
  useToast,
} from '@chakra-ui/react';
import React, { useEffect, useRef, useState } from 'react';
import { Document, Page, pdfjs } from 'react-pdf';
import 'react-pdf/dist/Page/AnnotationLayer.css';
import 'react-pdf/dist/Page/TextLayer.css';
import { useNavigate, useParams } from 'react-router-dom';
import { BlueTitleBar } from '../../shared/base/blue-title-bar';

pdfjs.GlobalWorkerOptions.workerSrc = `https://unpkg.com/pdfjs-dist@${pdfjs.version}/build/pdf.worker.min.mjs`;

type RevisionRequestRow = {
  id: string;
  invoice_versionno?: number | null;
  revreq_seqno?: number | null;
  status?: string | null;
  request_text?: string | null;
  response_text?: string | null;
  created_at?: string | null;
  updated_at?: string | null;
};

const fmtDate = (value?: string | null) => {
  if (!value) return '-';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return String(value);
  return date.toLocaleString(undefined, {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  });
};

const statusColor = (status?: string | null) => {
  const value = String(status || '').toLowerCase();
  if (value === 'genai_complete') return 'blue';
  if (value === 'admin_review_inbox' || value === 'in_review') return 'yellow';
  if (value === 'contractor_revision_inbox') return 'orange';
  if (value === 'approved_pending' || value === 'approved_paid') return 'green';
  if (value === 'ineligible' || value.endsWith('_failed')) return 'red';
  return 'gray';
};

const statusLabel = (status?: string | null) => {
  const value = String(status || '').trim();
  if (value === 'genai_complete') return 'genai_complete - contractor reviewing';
  return value || 'unknown';
};

const fieldValue = (value: unknown) => {
  const text = String(value ?? '').trim();
  return text || '-';
};

export default function ContractorInvoiceReviewScreen() {
  const { sessionId, invoiceId } = useParams();
  const navigate = useNavigate();
  const toast = useToast();
  const fileInputRef = useRef<HTMLInputElement | null>(null);
  const { isOpen, onOpen, onClose } = useDisclosure();

  const [invoiceIds, setInvoiceIds] = useState<string[]>([]);
  const [readData, setReadData] = useState<any>(null);
  const [lineitems, setLineitems] = useState<any[]>([]);
  const [pdfUrl, setPdfUrl] = useState('');
  const [pdfError, setPdfError] = useState('');
  const [numPages, setNumPages] = useState(0);
  const [pageWidth, setPageWidth] = useState(760);
  const [revisionRows, setRevisionRows] = useState<RevisionRequestRow[]>([]);
  const [revisionLoading, setRevisionLoading] = useState(false);
  const [submitLoading, setSubmitLoading] = useState(false);
  const [uploadLoading, setUploadLoading] = useState(false);

  const currentStatus = String(readData?.invoice_status || '').trim();
  const currentInvoiceId = String(readData?.invoice_id || invoiceId || '').trim();
  const idx = invoiceIds.indexOf(String(invoiceId || ''));
  const canGoPrev = idx > 0;
  const canGoNext = idx >= 0 && idx < invoiceIds.length - 1;
  const canSubmit = currentStatus === 'genai_complete';
  const canViewChanges = currentStatus === 'contractor_revision_inbox';
  const canUploadFix = currentStatus === 'contractor_revision_inbox';

  useEffect(() => {
    const run = async () => {
      if (!sessionId) return;
      const resp = await fetch(`/api/claims/sessions/${encodeURIComponent(sessionId)}/current_invoices`, {
        headers: { Accept: 'application/json' },
        credentials: 'include',
      });
      const json = await resp.json().catch(() => ({}));
      setInvoiceIds(Array.isArray(json?.invoice_ids) ? json.invoice_ids : []);
    };
    run();
  }, [sessionId]);

  useEffect(() => {
    const run = async () => {
      if (!sessionId || !invoiceId) return;
      const [readResp, pdfResp] = await Promise.all([
        fetch(`/api/claims/sessions/${encodeURIComponent(sessionId)}/invoices/${encodeURIComponent(invoiceId)}/read`, {
          headers: { Accept: 'application/json' },
          credentials: 'include',
        }),
        fetch(
          `/api/claims/sessions/${encodeURIComponent(sessionId)}/invoices/${encodeURIComponent(invoiceId)}/pdf_url`,
          {
            headers: { Accept: 'application/json' },
            credentials: 'include',
          },
        ),
      ]);

      const readJson = await readResp.json().catch(() => ({}));
      setReadData(readJson?.read ?? null);
      setLineitems(Array.isArray(readJson?.lineitems) ? readJson.lineitems : []);

      const pdfJson = await pdfResp.json().catch(() => ({}));
      if (!pdfResp.ok || !pdfJson?.sas_url) {
        setPdfUrl('');
        setPdfError(pdfJson?.error || `Could not load PDF URL (${pdfResp.status}).`);
      } else {
        setPdfUrl(String(pdfJson.sas_url));
        setPdfError('');
      }
    };
    run();
  }, [sessionId, invoiceId]);

  useEffect(() => {
    const onResize = () => setPageWidth(Math.min(760, Math.max(320, window.innerWidth - 80)));
    onResize();
    window.addEventListener('resize', onResize);
    return () => window.removeEventListener('resize', onResize);
  }, []);

  const loadRevisionRequests = async () => {
    if (!currentInvoiceId) return;
    setRevisionLoading(true);
    try {
      const resp = await fetch(
        `/api/claims/contractor/invoices/${encodeURIComponent(currentInvoiceId)}/revision_requests`,
        {
          headers: { Accept: 'application/json' },
          credentials: 'include',
        },
      );
      const json = await resp.json().catch(() => ({}));
      if (!resp.ok) throw new Error(json?.error || `Could not load requested changes (${resp.status}).`);
      setRevisionRows(Array.isArray(json?.rows) ? json.rows : []);
    } catch (e: any) {
      toast({
        title: 'Could not load requested changes',
        description: e?.message || 'Please try again.',
        status: 'error',
        duration: 6000,
        isClosable: true,
      });
    } finally {
      setRevisionLoading(false);
    }
  };

  const openRequestedChanges = () => {
    onOpen();
    void loadRevisionRequests();
  };

  const submitToAdmin = async () => {
    if (!currentInvoiceId || !canSubmit) return;
    setSubmitLoading(true);
    try {
      const resp = await fetch(
        `/api/claims/contractor/invoices/${encodeURIComponent(currentInvoiceId)}/submit_to_admin`,
        {
          method: 'POST',
          headers: { Accept: 'application/json' },
          credentials: 'include',
        },
      );
      const json = await resp.json().catch(() => ({}));
      if (!resp.ok) throw new Error(json?.error || `Submit failed (${resp.status}).`);

      setReadData((prev: any) =>
        prev
          ? {
              ...prev,
              invoice_status: json?.invoice?.status || 'admin_review_inbox',
            }
          : prev,
      );
      toast({
        title: 'Invoice submitted',
        description: 'Status moved from genai_complete to admin_review_inbox.',
        status: 'success',
        duration: 5000,
        isClosable: true,
      });
    } catch (e: any) {
      toast({
        title: 'Submit failed',
        description: e?.message || 'Please try again.',
        status: 'error',
        duration: 6000,
        isClosable: true,
      });
    } finally {
      setSubmitLoading(false);
    }
  };

  const uploadCorrectedInvoice = async (file?: File) => {
    if (!file || !currentInvoiceId) return;
    setUploadLoading(true);
    try {
      const form = new FormData();
      form.append('pdfs[]', file);
      const resp = await fetch(`/api/claims/invoices/${encodeURIComponent(currentInvoiceId)}/upload_fix`, {
        method: 'POST',
        body: form,
        credentials: 'include',
      });
      const json = await resp.json().catch(() => ({}));
      if (!resp.ok || json?.ok === false) throw new Error(json?.error || `Upload failed (${resp.status}).`);

      toast({
        title: 'Corrected invoice uploaded',
        description: 'The corrected invoice was uploaded. OCR and AI processing may still need to run before resubmit.',
        status: 'success',
        duration: 7000,
        isClosable: true,
      });
    } catch (e: any) {
      toast({
        title: 'Upload failed',
        description: e?.message || 'Please try again.',
        status: 'error',
        duration: 6000,
        isClosable: true,
      });
    } finally {
      setUploadLoading(false);
      if (fileInputRef.current) fileInputRef.current.value = '';
    }
  };

  const goPrev = () => {
    if (!canGoPrev || !sessionId) return;
    navigate(
      `/contractor/sessions/${encodeURIComponent(sessionId)}/invoices/${encodeURIComponent(invoiceIds[idx - 1])}/review`,
    );
  };

  const goNext = () => {
    if (!canGoNext || !sessionId) return;
    navigate(
      `/contractor/sessions/${encodeURIComponent(sessionId)}/invoices/${encodeURIComponent(invoiceIds[idx + 1])}/review`,
    );
  };

  return (
    <Flex as="main" direction="column" w="full" bg="greys.white" minH="100vh" pb="24">
      <BlueTitleBar title="Invoice Review" />
      <Container maxW="container.xl" py={6}>
        <Flex direction="column" gap={4}>
          <Flex align="center" gap={3} wrap="wrap">
            <Button size="sm" variant="outline" isDisabled={!canGoPrev} onClick={goPrev}>
              Previous invoice
            </Button>
            <Text fontSize="sm" opacity={0.8}>
              Invoice {idx >= 0 ? idx + 1 : '-'} of {invoiceIds.length || '-'} in this session
            </Text>
            <Button size="sm" variant="outline" isDisabled={!canGoNext} onClick={goNext}>
              Next invoice
            </Button>
            <Badge colorScheme={statusColor(currentStatus)} ml={{ base: 0, md: 'auto' }}>
              {statusLabel(currentStatus)}
            </Badge>
          </Flex>

          <Flex gap={3} wrap="wrap">
            <Tooltip label="Submit this invoice for admin review (status: genai_complete -> admin_review_inbox).">
              <Button colorScheme="blue" isDisabled={!canSubmit} isLoading={submitLoading} onClick={submitToAdmin}>
                {currentStatus === 'contractor_revision_inbox' ? 'Resubmit to Admin' : 'Submit to Admin'}
              </Button>
            </Tooltip>
            <Tooltip label="Open requested changes without leaving this invoice (status: contractor_revision_inbox).">
              <Button variant="outline" isDisabled={!canViewChanges} onClick={openRequestedChanges}>
                View Requested Changes
              </Button>
            </Tooltip>
            <Tooltip label="Upload a corrected invoice PDF for this invoice (status: contractor_revision_inbox).">
              <Button
                variant="outline"
                isDisabled={!canUploadFix}
                isLoading={uploadLoading}
                onClick={() => fileInputRef.current?.click()}
              >
                Upload Corrected Invoice
              </Button>
            </Tooltip>
            <Input
              ref={fileInputRef}
              type="file"
              accept="application/pdf"
              display="none"
              onChange={(event) => uploadCorrectedInvoice(event.target.files?.[0])}
            />
          </Flex>

          <Flex gap={5} align="stretch" direction={{ base: 'column', lg: 'row' }}>
            <Box borderWidth="1px" borderRadius="lg" p={5} bg="white" w={{ base: 'full', lg: '360px' }} flexShrink={0}>
              <Heading size="sm" mb={4}>
                Invoice Information
              </Heading>
              <Flex direction="column" gap={3}>
                <Box>
                  <Text fontSize="xs" opacity={0.7}>
                    Invoice #
                  </Text>
                  <Text>{fieldValue(readData?.di_ocr_invoice_id)}</Text>
                </Box>
                <Box>
                  <Text fontSize="xs" opacity={0.7}>
                    Invoice date
                  </Text>
                  <Text>{fieldValue(readData?.di_ocr_invoice_date)}</Text>
                </Box>
                <Box>
                  <Text fontSize="xs" opacity={0.7}>
                    Vendor
                  </Text>
                  <Text>{fieldValue(readData?.di_ocr_vendor_name)}</Text>
                </Box>
                <Box>
                  <Text fontSize="xs" opacity={0.7}>
                    Customer
                  </Text>
                  <Text>{fieldValue(readData?.di_ocr_customer_name)}</Text>
                </Box>
                <Box>
                  <Text fontSize="xs" opacity={0.7}>
                    Invoice total
                  </Text>
                  <Text>{fieldValue(readData?.di_ocr_invoice_total)}</Text>
                </Box>
                <Box>
                  <Text fontSize="xs" opacity={0.7}>
                    Amount due
                  </Text>
                  <Text>{fieldValue(readData?.di_ocr_amount_due)}</Text>
                </Box>
              </Flex>

              {lineitems.length > 0 && (
                <Box mt={6}>
                  <Heading size="xs" mb={3}>
                    OCR line items
                  </Heading>
                  <Flex direction="column" gap={2}>
                    {lineitems.slice(0, 8).map((lineitem) => (
                      <Box key={lineitem.id} borderTopWidth="1px" pt={2}>
                        <Text fontSize="sm">{fieldValue(lineitem.ocr_description)}</Text>
                        <Text fontSize="xs" opacity={0.7}>
                          {fieldValue(lineitem.ocr_amount)}
                        </Text>
                      </Box>
                    ))}
                  </Flex>
                </Box>
              )}
            </Box>

            <Box borderWidth="1px" borderRadius="lg" p={4} bg="gray.50" flex="1" minH="780px" overflow="auto">
              {pdfError ? (
                <Text color="red.700">{pdfError}</Text>
              ) : pdfUrl ? (
                <Document file={pdfUrl} onLoadSuccess={({ numPages: pages }) => setNumPages(pages)}>
                  {Array.from({ length: numPages || 0 }, (_, index) => (
                    <Box key={`page-${index + 1}`} mb={6} display="flex" justifyContent="center">
                      <Page pageNumber={index + 1} width={pageWidth} renderAnnotationLayer renderTextLayer />
                    </Box>
                  ))}
                </Document>
              ) : (
                <Flex align="center" justify="center" minH="300px">
                  <Spinner />
                </Flex>
              )}
            </Box>
          </Flex>
        </Flex>
      </Container>

      <Drawer isOpen={isOpen} onClose={onClose} placement="right" size="lg">
        <DrawerOverlay />
        <DrawerContent>
          <DrawerCloseButton />
          <DrawerHeader>Requested Changes</DrawerHeader>
          <DrawerBody>
            <Text fontSize="sm" mb={4}>
              Please review the requested changes below, upload a corrected invoice if needed, then resubmit when the
              corrected invoice is ready.
            </Text>
            {revisionLoading ? (
              <Spinner />
            ) : revisionRows.length === 0 ? (
              <Text>No requested changes were found for this invoice.</Text>
            ) : (
              <Flex direction="column" gap={4}>
                {revisionRows.map((row) => (
                  <Box key={row.id} borderWidth="1px" borderRadius="md" p={4}>
                    <Flex align="center" justify="space-between" gap={3} mb={2}>
                      <Text fontWeight="bold">
                        Request {row.revreq_seqno ?? '-'} on version {row.invoice_versionno ?? '-'}
                      </Text>
                      <Badge>{row.status || 'OPEN'}</Badge>
                    </Flex>
                    <Text fontSize="xs" opacity={0.7} mb={3}>
                      Updated {fmtDate(row.updated_at || row.created_at)}
                    </Text>
                    <Text whiteSpace="pre-wrap">{row.request_text || 'No request text provided.'}</Text>
                    {row.response_text ? (
                      <Box mt={4} p={3} bg="gray.50" borderRadius="md">
                        <Text fontSize="xs" opacity={0.7} mb={1}>
                          Your response
                        </Text>
                        <Text whiteSpace="pre-wrap">{row.response_text}</Text>
                      </Box>
                    ) : null}
                  </Box>
                ))}
              </Flex>
            )}
          </DrawerBody>
        </DrawerContent>
      </Drawer>
    </Flex>
  );
}
