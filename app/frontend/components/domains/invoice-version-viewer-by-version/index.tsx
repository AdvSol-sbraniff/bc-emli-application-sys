import {
  Accordion,
  AccordionButton,
  AccordionIcon,
  AccordionItem,
  AccordionPanel,
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
  IconButton,
  Spinner,
  Text,
  Tooltip,
  useDisclosure,
} from '@chakra-ui/react';
import { Question } from '@phosphor-icons/react';
import React, { useEffect, useMemo, useState } from 'react';
import { Document, Page, pdfjs } from 'react-pdf';
import { useParams } from 'react-router-dom';
import { ThinBlueTitleBar } from '../../shared/base/thin-blue-title-bar';
import { fmtDate, fmtMoney, fmtText } from '../invoice-versions/display';
//import workerSrc from 'pdfjs-dist/build/pdf.worker.min.mjs?url';
import 'react-pdf/dist/Page/AnnotationLayer.css';
import 'react-pdf/dist/Page/TextLayer.css';
pdfjs.GlobalWorkerOptions.workerSrc = `https://unpkg.com/pdfjs-dist@${pdfjs.version}/build/pdf.worker.min.mjs`;

//pdfjs.GlobalWorkerOptions.workerSrc = workerSrc;

type LineItem = {
  id: string;
  lineitem_seqno?: number | null;
  ocr_description?: string | null;
  ocr_quantity?: number | string | null;
  ocr_unit_price?: number | string | null;
  ocr_amount?: number | string | null;
};

type LocatedField = {
  id: string;
  field_key?: string | null;
  line_number?: number | null;
  value_text?: string | null;
  normalized_value?: string | null;
  confidence?: number | null;
};

type Rulecheck = {
  id: string;
  rule_number?: number | null;
  rule_name?: string | null;
  rule_pass_flag?: boolean | null;
  confidence?: number | null;
  expected_text?: string | null;
  observed_text?: string | null;
  reason_and_likely_causes?: string | null;
};

type ReadPayload = {
  read?: any;
  invoice?: any;
  lineitems?: LineItem[];
};

type GenaiPayload = {
  located_fields?: LocatedField[];
  code_located_fields?: LocatedField[];
  rulechecks?: Rulecheck[];
};

const headerFields = [
  { label: 'Invoice #', key: 'di_ocr_invoice_id', fmt: fmtText },
  { label: 'Invoice date', key: 'di_ocr_invoice_date', fmt: fmtDate },
  { label: 'Business name', key: 'di_ocr_vendor_name', fmt: fmtText },
  { label: 'Vendor address', key: 'di_ocr_vendor_address', fmt: fmtText },
  { label: 'Customer name', key: 'di_ocr_customer_name', fmt: fmtText },
  { label: 'Billing address', key: 'di_ocr_billing_address', fmt: fmtText },
  { label: 'Sub-total', key: 'di_ocr_sub_total', fmt: fmtMoney },
  { label: 'Total tax', key: 'di_ocr_total_tax', fmt: fmtMoney },
  { label: 'Invoice total', key: 'di_ocr_invoice_total', fmt: fmtMoney },
  { label: 'Amount due', key: 'di_ocr_amount_due', fmt: fmtMoney },
];

export const InvoiceVersionByVersionScreen = () => {
  const { invoiceVersionId } = useParams();

  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  const [readData, setReadData] = useState<any>(null);
  const [invoiceData, setInvoiceData] = useState<any>(null);
  const [lineitems, setLineitems] = useState<LineItem[]>([]);
  const [locatedFields, setLocatedFields] = useState<LocatedField[]>([]);
  const [codeFields, setCodeFields] = useState<LocatedField[]>([]);
  const [rulechecks, setRulechecks] = useState<Rulecheck[]>([]);

  const [pdfUrl, setPdfUrl] = useState<string | null>(null);
  const [pdfUrlError, setPdfUrlError] = useState('');
  const [numPages, setNumPages] = useState<number>(0);
  const [activePageNumber, setActivePageNumber] = useState<number>(1);

  const {
    isOpen: isHelpOpen,
    onOpen: onHelpOpen,
    onClose: onHelpClose,
  } = useDisclosure();

  useEffect(() => {
    const load = async () => {
      setLoading(true);
      setError('');
      setPdfUrlError('');
      setPdfUrl(null);
      setNumPages(0);
      setActivePageNumber(1);

      try {
        const id = (invoiceVersionId || '').trim();
        if (!id) throw new Error('Missing invoice version id.');

        const [readRes, genaiRes, pdfRes] = await Promise.all([
          fetch(`/api/claims/admin/invoice_versions/${encodeURIComponent(id)}/read`, {
            method: 'GET',
            headers: { Accept: 'application/json' },
            credentials: 'include',
          }),
          fetch(`/api/claims/admin/invoice_versions/${encodeURIComponent(id)}/read_genai`, {
            method: 'GET',
            headers: { Accept: 'application/json' },
            credentials: 'include',
          }),
          fetch(`/api/claims/admin/invoice_versions/${encodeURIComponent(id)}/pdf_url`, {
            method: 'GET',
            headers: { Accept: 'application/json' },
            credentials: 'include',
          }),
        ]);

        const readJson: ReadPayload = await readRes.json().catch(() => ({}));
        if (!readRes.ok) throw new Error((readJson as any)?.error || `Read failed (${readRes.status})`);

        const genaiJson: GenaiPayload = await genaiRes.json().catch(() => ({}));
        if (!genaiRes.ok) throw new Error((genaiJson as any)?.error || `GenAI read failed (${genaiRes.status})`);

        const pdfJson = await pdfRes.json().catch(() => ({}));
        if (!pdfRes.ok) {
          setPdfUrlError(pdfJson?.error || `PDF URL failed (${pdfRes.status})`);
        }

        setReadData(readJson?.read || null);
        setInvoiceData(readJson?.invoice || null);
        setLineitems(Array.isArray(readJson?.lineitems) ? readJson.lineitems : []);

        setLocatedFields(Array.isArray(genaiJson?.located_fields) ? genaiJson.located_fields : []);
        setCodeFields(Array.isArray(genaiJson?.code_located_fields) ? genaiJson.code_located_fields : []);
        setRulechecks(Array.isArray(genaiJson?.rulechecks) ? genaiJson.rulechecks : []);

        setPdfUrl(pdfJson?.sas_url || null);
      } catch (e: any) {
        setError(e?.message || 'Failed to load invoice version viewer.');
      } finally {
        setLoading(false);
      }
    };

    void load();
  }, [invoiceVersionId]);

  const overall = useMemo(() => {
    if (!readData) return null;
    return {
      confidence: readData.genai_overall_confidence,
      passFlag: readData.genai_all_rulechecks_pass_flag,
      advice: readData.genai_admin_advice,
    };
  }, [readData]);

  return (
    <Flex as="main" direction="column" w="full" bg="greys.white" pb="24" minH="100vh">
      <ThinBlueTitleBar title="Invoices Admin - PDF Viewer (By Version)" />

      <Container maxW="full" px={6} pb={4} flex="1" pt={6}>
        <Box display="flex" flexDirection="column" height="100%">
          <Box display="flex" alignItems="center" gap="8px" mb="12px" wrap="wrap">
            <Text fontSize="sm" opacity={0.8}>
              invoice_version_id: <Box as="span" fontFamily="mono">{invoiceVersionId || '—'}</Box>
            </Text>

            <Text fontSize="sm" opacity={0.8}>
              invoice_id: <Box as="span" fontFamily="mono">{readData?.invoice_id || '—'}</Box>
            </Text>

            <Text fontSize="sm" opacity={0.8}>
              session_id: <Box as="span" fontFamily="mono">{invoiceData?.session_id || '—'}</Box>
            </Text>

            <Box ml="auto">
              <Tooltip label="Help: comparing one version to another">
                <IconButton
                  aria-label="Open by-version PDF viewer help"
                  icon={<Question size={18} />}
                  size="sm"
                  variant="outline"
                  onClick={onHelpOpen}
                />
              </Tooltip>
            </Box>
          </Box>

          {error && (
            <Box mb={4} p={3} bg="red.50" borderWidth="1px" borderColor="red.200" borderRadius="md">
              <Text fontSize="sm" color="red.700">{error}</Text>
            </Box>
          )}

          <Box display="flex" gap="16px" flex="1" minH={0}>
            <Box
              borderWidth="1px"
              borderRadius="md"
              p="12px"
              sx={{ resize: 'horizontal', overflow: 'auto' }}
              minW="360px"
              maxW="820px"
              w="520px"
              flexShrink={0}
            >
              <Accordion allowMultiple defaultIndex={[0, 1, 2]}>
                <AccordionItem border="none">
                  <h2>
                    <AccordionButton px="0" py="6px" _hover={{ bg: 'transparent' }}>
                      <Box flex="1" textAlign="left"><Text size="sm">Invoice</Text></Box>
                      <AccordionIcon />
                    </AccordionButton>
                  </h2>
                  <AccordionPanel px="0" pt="8px">
                    <Box display="grid" gridTemplateColumns="1fr 1fr" gap="8px">
                      {headerFields.map((f) => (
                        <Box key={f.key} px="10px" py="8px" borderWidth="1px" borderColor="gray.100" borderRadius="md">
                          <Text fontSize="xs" opacity={0.7}>{f.label}</Text>
                          <Text fontSize="sm">{f.fmt(readData?.[f.key])}</Text>
                        </Box>
                      ))}
                    </Box>
                  </AccordionPanel>
                </AccordionItem>

                <AccordionItem borderTopWidth="1px" borderColor="gray.200">
                  <h2>
                    <AccordionButton px="0" py="6px" _hover={{ bg: 'transparent' }}>
                      <Box flex="1" textAlign="left"><Text size="sm">Line Items</Text></Box>
                      <AccordionIcon />
                    </AccordionButton>
                  </h2>
                  <AccordionPanel px="0" pt="8px">
                    {lineitems.length === 0 ? (
                      <Text fontSize="sm" opacity={0.7}>No line items found.</Text>
                    ) : (
                      <Box display="flex" flexDirection="column" gap="8px">
                        {lineitems.map((li) => (
                          <Box key={li.id} borderWidth="1px" borderColor="gray.100" borderRadius="md" p="8px">
                            <Text fontSize="xs" opacity={0.7}>Line {(li.lineitem_seqno ?? '—').toString()}</Text>
                            <Text fontSize="sm">{li.ocr_description || '—'}</Text>
                            <Text fontSize="xs" opacity={0.8}>
                              qty: {li.ocr_quantity ?? '—'} | unit: {li.ocr_unit_price ?? '—'} | amount: {li.ocr_amount ?? '—'}
                            </Text>
                          </Box>
                        ))}
                      </Box>
                    )}
                  </AccordionPanel>
                </AccordionItem>

                <AccordionItem borderTopWidth="1px" borderColor="gray.200">
                  <h2>
                    <AccordionButton px="0" py="6px" _hover={{ bg: 'transparent' }}>
                      <Box flex="1" textAlign="left"><Text size="sm">GenAI Located Fields</Text></Box>
                      <AccordionIcon />
                    </AccordionButton>
                  </h2>
                  <AccordionPanel px="0" pt="8px">
                    {locatedFields.length === 0 ? (
                      <Text fontSize="sm" opacity={0.7}>No GenAI located fields found.</Text>
                    ) : (
                      <Box display="flex" flexDirection="column" gap="8px">
                        {locatedFields.map((r) => (
                          <Box key={r.id} borderWidth="1px" borderColor="gray.100" borderRadius="md" p="8px">
                            <Text fontSize="xs" opacity={0.7}>{r.field_key || 'field'} (line {r.line_number ?? '—'})</Text>
                            <Text fontSize="sm">{r.value_text || r.normalized_value || '—'}</Text>
                            <Text fontSize="xs" opacity={0.8}>confidence: {r.confidence ?? '—'}</Text>
                          </Box>
                        ))}
                      </Box>
                    )}
                  </AccordionPanel>
                </AccordionItem>

                <AccordionItem borderTopWidth="1px" borderColor="gray.200">
                  <h2>
                    <AccordionButton px="0" py="6px" _hover={{ bg: 'transparent' }}>
                      <Box flex="1" textAlign="left"><Text size="sm">Pre-existing info on file</Text></Box>
                      <AccordionIcon />
                    </AccordionButton>
                  </h2>
                  <AccordionPanel px="0" pt="8px">
                    {codeFields.length === 0 ? (
                      <Text fontSize="sm" opacity={0.7}>No pre-existing fields found.</Text>
                    ) : (
                      <Box display="flex" flexDirection="column" gap="8px">
                        {codeFields.map((r) => (
                          <Box key={r.id} borderWidth="1px" borderColor="gray.100" borderRadius="md" p="8px">
                            <Text fontSize="xs" opacity={0.7}>{r.field_key || 'field'}</Text>
                            <Text fontSize="sm">{r.value_text || r.normalized_value || '—'}</Text>
                          </Box>
                        ))}
                      </Box>
                    )}
                  </AccordionPanel>
                </AccordionItem>

                <AccordionItem borderTopWidth="1px" borderColor="gray.200">
                  <h2>
                    <AccordionButton px="0" py="6px" _hover={{ bg: 'transparent' }}>
                      <Box flex="1" textAlign="left">
                        <Text size="sm">GenAI Rulechecks</Text>
                      </Box>
                      <AccordionIcon />
                    </AccordionButton>
                  </h2>
                  <AccordionPanel px="0" pt="8px">
                    <Box mb="8px" borderWidth="1px" borderColor="gray.200" borderRadius="md" p="8px" bg="gray.50">
                      <Text fontSize="xs" opacity={0.7}>Overall</Text>
                      <Text fontSize="sm">confidence: {overall?.confidence ?? '—'}</Text>
                      <Text fontSize="sm">pass: {overall?.passFlag == null ? '—' : overall.passFlag ? 'true' : 'false'}</Text>
                      <Text fontSize="sm" whiteSpace="pre-wrap">advice: {overall?.advice || '—'}</Text>
                    </Box>

                    {rulechecks.length === 0 ? (
                      <Text fontSize="sm" opacity={0.7}>No GenAI rulechecks found.</Text>
                    ) : (
                      <Box display="flex" flexDirection="column" gap="8px">
                        {rulechecks.map((r) => (
                          <Box key={r.id} borderWidth="1px" borderColor="gray.100" borderRadius="md" p="8px">
                            <Flex align="center" gap="8px" mb="4px">
                              <Text fontSize="sm" fontWeight="bold">Rule {r.rule_number ?? '—'}: {r.rule_name || ''}</Text>
                              {r.rule_pass_flag == null ? (
                                <Badge>Unknown</Badge>
                              ) : (
                                <Badge colorScheme={r.rule_pass_flag ? 'green' : 'red'}>{r.rule_pass_flag ? 'PASS' : 'FAIL'}</Badge>
                              )}
                            </Flex>
                            <Text fontSize="xs" opacity={0.8}>confidence: {r.confidence ?? '—'}</Text>
                            <Text fontSize="xs" mt="2px">expected: {r.expected_text || '—'}</Text>
                            <Text fontSize="xs" mt="2px">observed: {r.observed_text || '—'}</Text>
                            <Text fontSize="xs" mt="2px">reason: {r.reason_and_likely_causes || '—'}</Text>
                          </Box>
                        ))}
                      </Box>
                    )}
                  </AccordionPanel>
                </AccordionItem>
              </Accordion>
            </Box>

            <Box flex="1" minW={0} minH={0} borderWidth="1px" borderRadius="md" overflow="auto" p="8px" bg="gray.50">
              <Box
                display="flex"
                alignItems="center"
                justifyContent="space-between"
                gap="10px"
                mb="8px"
                p="8px"
                borderWidth="1px"
                borderRadius="md"
                bg="white"
              >
                <Box display="flex" alignItems="center" gap="8px">
                  <Button size="sm" onClick={() => setActivePageNumber((p) => Math.max(1, p - 1))} isDisabled={activePageNumber <= 1}>
                    Prev
                  </Button>
                  <Text fontSize="sm">Page {activePageNumber} / {numPages || '?'}</Text>
                  <Button
                    size="sm"
                    onClick={() => setActivePageNumber((p) => Math.min(numPages || p + 1, p + 1))}
                    isDisabled={!!numPages && activePageNumber >= numPages}
                  >
                    Next
                  </Button>
                </Box>
              </Box>

              {loading && (
                <Flex align="center" gap={2} mb={2}>
                  <Spinner size="sm" />
                  <Text fontSize="sm">Loading viewer...</Text>
                </Flex>
              )}

              {pdfUrlError && (
                <Text fontSize="sm" color="red.500" mb="8px">
                  PDF URL error: {pdfUrlError}
                </Text>
              )}

              {!pdfUrl && !pdfUrlError && !loading && (
                <Text fontSize="sm" opacity={0.7} mb="8px">No PDF URL found for this version.</Text>
              )}

              {pdfUrl && (
                <Document
                  key={pdfUrl}
                  file={pdfUrl}
                  onLoadSuccess={({ numPages: pages }) => setNumPages(pages)}
                  onLoadError={(err) => {
                    setPdfUrlError(String(err));
                  }}
                >
                  <Page pageNumber={activePageNumber} width={1000} />
                </Document>
              )}
            </Box>
          </Box>
        </Box>
      </Container>

      <Drawer isOpen={isHelpOpen} placement="left" onClose={onHelpClose} size="xl">
        <DrawerOverlay />
        <DrawerContent>
          <DrawerCloseButton />
          <DrawerHeader>By-Version Viewer Help</DrawerHeader>
          <DrawerBody>
            <Flex direction="column" gap={4}>
              <Box>
                <Heading size="sm" mb={2}>What This Screen Is</Heading>
                <Text as="div" fontSize="sm">
                  This screen shows one specific invoice version only.
                </Text>
                <Text as="div" fontSize="sm" mt={1}>
                  There is no invoice-to-invoice navigation here.
                </Text>
                <Text as="div" fontSize="sm" mt={1}>
                  It is made for deep inspection of one chosen version.
                </Text>
              </Box>

              <Box>
                <Heading size="sm" mb={2}>Best Way To Compare Versions</Heading>
                <Text as="div" fontSize="sm">
                  Open two browser tabs.
                </Text>
                <Text as="div" fontSize="sm" mt={1}>
                  In each tab, open a different invoice version.
                </Text>
                <Text as="div" fontSize="sm" mt={1}>
                  Then switch between tabs to compare PDF changes and how rule outcomes changed.
                </Text>
              </Box>

              <Box>
                <Heading size="sm" mb={2}>Fast Text-Only Compare</Heading>
                <Text as="div" fontSize="sm">
                  If you do not need to compare the PDF image itself, text-only compare is faster.
                </Text>
                <Text as="div" fontSize="sm" mt={1}>
                  Use the Versions History Inspection grid and switch between details drawers of two version rows.
                </Text>
                <Text as="div" fontSize="sm" mt={1}>
                  That is often the quickest way to compare JSON and rule details.
                </Text>
              </Box>

              <Box>
                <Heading size="sm" mb={2}>How Sections Relate To Rulesets</Heading>
                <Text as="div" fontSize="sm">
                  Invoice and Line Items are OCR-driven values from document reading.
                </Text>
                <Text as="div" fontSize="sm" mt={1}>
                  GenAI Located Fields and GenAI Rulechecks are affected by ruleset design and ruleset changes.
                </Text>
                <Text as="div" fontSize="sm" mt={1}>
                  Pre-existing info on file is known case data used during checking.
                </Text>
              </Box>
            </Flex>
          </DrawerBody>
        </DrawerContent>
      </Drawer>
    </Flex>
  );
};
