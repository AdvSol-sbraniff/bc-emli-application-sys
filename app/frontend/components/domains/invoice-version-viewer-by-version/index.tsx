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
import {
  getInvoiceUpgradeTypeMeta,
  INVOICE_UPGRADE_TYPE_FILTER_ORDER,
  InvoiceUpgradeTypeTile,
} from '../../shared/claims/invoice-upgrade-type-visual';
import { fmtDate, fmtMoney, fmtText } from '../invoice-versions/display';
//import workerSrc from 'pdfjs-dist/build/pdf.worker.min.mjs?url';
import 'react-pdf/dist/Page/AnnotationLayer.css';
import 'react-pdf/dist/Page/TextLayer.css';
pdfjs.GlobalWorkerOptions.workerSrc = `https://unpkg.com/pdfjs-dist@${pdfjs.version}/build/pdf.worker.min.mjs`;

//pdfjs.GlobalWorkerOptions.workerSrc = workerSrc;

type LineItem = {
  id: string;
  upgrade_type_description?: string | null;
  upgrade_type_key?: string | null;
  lineitem_seqno?: number | null;
  ocr_description?: string | null;
  ocr_quantity?: number | string | null;
  ocr_unit_price?: number | string | null;
  ocr_amount?: number | string | null;
};

type LocatedField = {
  id: string;
  source_engine?: string | null;
  upgrade_type_description?: string | null;
  upgrade_type_key?: string | null;
  field_key?: string | null;
  line_number?: number | null;
  page?: number | string | null;
  polygon?: unknown;
  value_text?: string | null;
  value_json?: unknown;
  evidence_text?: string | null;
  confidence?: number | null;
};

type Rulecheck = {
  id: string;
  upgrade_type_description?: string | null;
  upgrade_type_key?: string | null;
  source_engine?: string | null;
  rule_key?: string | null;
  source_requirement_id?: string | null;
  evidence_source?: string | null;
  rule_number?: number | null;
  rule_name?: string | null;
  rule_pass_flag?: boolean | null;
  confidence?: number | null;
  expected_text?: string | null;
  observed_text?: string | null;
  calculation?: string | null;
  reason_and_likely_causes?: string | null;
};

type UpgradeTypeResult = {
  id: string;
  source_engine?: string | null;
  call_status?: string | null;
  upgrade_type_description?: string | null;
  upgrade_type_key?: string | null;
  confidence?: number | null;
  evidence_text?: string | null;
  classifier_notes?: string | null;
  validationgenai_ruleset_id?: string | null;
  genai_overall_confidence?: number | null;
  genai_all_rulechecks_pass_flag?: boolean | null;
  genai_admin_advice?: string | null;
};

type ReadPayload = {
  read?: any;
  invoice?: any;
  lineitems?: LineItem[];
};

type GenaiPayload = {
  upgrade_type_results?: UpgradeTypeResult[];
  located_fields?: LocatedField[];
  code_located_fields?: LocatedField[];
  rulechecks?: Rulecheck[];
  code_rulechecks?: Rulecheck[];
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

const upgradeTypeSortValue = (upgradeTypeKey: string) => {
  if (upgradeTypeKey === 'common') return -1;
  const index = INVOICE_UPGRADE_TYPE_FILTER_ORDER.indexOf(upgradeTypeKey as any);
  return index === -1 ? Number.MAX_SAFE_INTEGER : index;
};

const upgradeTypeKeyFor = (row: any) => String(row?.upgrade_type_key || 'common');

const upgradeTypeDescriptionFor = (row: any) => {
  const upgradeTypeKey = upgradeTypeKeyFor(row);
  return row?.upgrade_type_description || getInvoiceUpgradeTypeMeta(upgradeTypeKey).label;
};

type ActiveHighlight = {
  id: string;
  fieldKey: string;
  pageNumber: number;
  polygon?: unknown;
};

const renderWidthPx = 1000;

const coercePageNumber = (value: unknown) => {
  const pageNumber = Number(value);
  return Number.isFinite(pageNumber) && pageNumber >= 1 ? pageNumber : null;
};

const normalizePolygon = (polygon: unknown) => {
  if (!polygon) return null;

  let parsed = polygon;
  if (typeof polygon === 'string') {
    try {
      parsed = JSON.parse(polygon);
    } catch {
      return null;
    }
  }

  if (!Array.isArray(parsed)) return null;
  const flat = parsed.flatMap((point) => (Array.isArray(point) ? point : [point])).map((n) => Number(n));
  return flat.length === 8 && flat.every((n) => Number.isFinite(n)) ? flat : null;
};

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
  const [upgradeTypeResults, setUpgradeTypeResults] = useState<UpgradeTypeResult[]>([]);

  const [pdfUrl, setPdfUrl] = useState<string | null>(null);
  const [pdfUrlError, setPdfUrlError] = useState('');
  const [numPages, setNumPages] = useState<number>(0);
  const [activePageNumber, setActivePageNumber] = useState<number>(1);
  const [activeHighlight, setActiveHighlight] = useState<ActiveHighlight | null>(null);

  const { isOpen: isHelpOpen, onOpen: onHelpOpen, onClose: onHelpClose } = useDisclosure();

  useEffect(() => {
    const load = async () => {
      setLoading(true);
      setError('');
      setPdfUrlError('');
      setPdfUrl(null);
      setNumPages(0);
      setActivePageNumber(1);
      setActiveHighlight(null);

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
        setUpgradeTypeResults(Array.isArray(genaiJson?.upgrade_type_results) ? genaiJson.upgrade_type_results : []);
        setRulechecks([
          ...(Array.isArray(genaiJson?.code_rulechecks) ? genaiJson.code_rulechecks : []),
          ...(Array.isArray(genaiJson?.rulechecks) ? genaiJson.rulechecks : []),
        ]);

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

  const upgradeTypeGroups = useMemo(() => {
    const groups = new Map<
      string,
      {
        description: string;
        fields: LocatedField[];
        lineitems: LineItem[];
        rulechecks: Rulecheck[];
        results: UpgradeTypeResult[];
        upgradeTypeKey: string;
      }
    >();

    const ensureGroup = (row: any) => {
      const upgradeTypeKey = upgradeTypeKeyFor(row);
      const existing = groups.get(upgradeTypeKey);
      if (existing) return existing;

      const group = {
        description: upgradeTypeDescriptionFor(row),
        fields: [] as LocatedField[],
        lineitems: [] as LineItem[],
        rulechecks: [] as Rulecheck[],
        results: [] as UpgradeTypeResult[],
        upgradeTypeKey,
      };
      groups.set(upgradeTypeKey, group);
      return group;
    };

    locatedFields.forEach((row) => ensureGroup(row).fields.push(row));
    lineitems.forEach((row) => ensureGroup(row).lineitems.push(row));
    rulechecks.forEach((row) => ensureGroup(row).rulechecks.push(row));
    upgradeTypeResults.forEach((row) => ensureGroup(row).results.push(row));

    return Array.from(groups.values()).sort((a, b) => {
      const sortA = upgradeTypeSortValue(a.upgradeTypeKey);
      const sortB = upgradeTypeSortValue(b.upgradeTypeKey);
      if (sortA !== sortB) return sortA - sortB;
      return a.description.localeCompare(b.description);
    });
  }, [lineitems, locatedFields, rulechecks, upgradeTypeResults]);

  const activePageMeta = useMemo(() => {
    const pages = readData?.di_page_map;
    if (!Array.isArray(pages)) return null;

    const found = pages.find((p: any) => Number(p.pageNumber) === Number(activePageNumber));
    if (!found) return null;

    return {
      width: Number(found.width),
      height: Number(found.height),
      unit: String(found.unit || ''),
    };
  }, [activePageNumber, readData?.di_page_map]);

  const overlayHeightPx = useMemo(() => {
    if (!activePageMeta?.width || !activePageMeta?.height) return 1294;
    return renderWidthPx * (activePageMeta.height / activePageMeta.width);
  }, [activePageMeta]);

  const svgPolygonPoints = useMemo(() => {
    if (!activeHighlight?.polygon || activeHighlight.pageNumber !== activePageNumber || !activePageMeta) return null;
    if (activePageMeta.unit !== 'inch' || !activePageMeta.width || !activePageMeta.height) return null;

    const flat = normalizePolygon(activeHighlight.polygon);
    if (!flat) return null;

    const xToPx = (xIn: number) => (xIn / activePageMeta.width) * renderWidthPx;
    const yToPx = (yIn: number) => (yIn / activePageMeta.height) * overlayHeightPx;
    const pts = [
      [xToPx(flat[0]), yToPx(flat[1])],
      [xToPx(flat[2]), yToPx(flat[3])],
      [xToPx(flat[4]), yToPx(flat[5])],
      [xToPx(flat[6]), yToPx(flat[7])],
    ];

    return pts.map(([x, y]) => `${x.toFixed(2)},${y.toFixed(2)}`).join(' ');
  }, [activeHighlight, activePageMeta, activePageNumber, overlayHeightPx]);

  const handleLocatedFieldClick = (row: LocatedField) => {
    const pageNumber = coercePageNumber(row.page);
    if (!pageNumber) return;

    setActivePageNumber(pageNumber);
    setActiveHighlight({
      id: row.id,
      fieldKey: row.field_key || 'field',
      pageNumber,
      polygon: row.polygon ?? null,
    });
  };

  return (
    <Flex as="main" direction="column" w="full" bg="greys.white" pb="24" minH="100vh">
      <ThinBlueTitleBar title="Invoices Admin - PDF Viewer (By Version)" />

      <Container maxW="full" px={6} pb={4} flex="1" pt={6}>
        <Box display="flex" flexDirection="column" height="100%">
          <Box display="flex" alignItems="center" gap="8px" mb="12px" flexWrap="wrap">
            <Text fontSize="sm" opacity={0.8}>
              invoice_version_id:{' '}
              <Box as="span" fontFamily="mono">
                {invoiceVersionId || '—'}
              </Box>
            </Text>

            <Text fontSize="sm" opacity={0.8}>
              invoice_id:{' '}
              <Box as="span" fontFamily="mono">
                {readData?.invoice_id || '—'}
              </Box>
            </Text>

            <Text fontSize="sm" opacity={0.8}>
              session_id:{' '}
              <Box as="span" fontFamily="mono">
                {invoiceData?.session_id || '—'}
              </Box>
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
              <Text fontSize="sm" color="red.700">
                {error}
              </Text>
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
                      <Box flex="1" textAlign="left">
                        <Text size="sm">Invoice</Text>
                      </Box>
                      <AccordionIcon />
                    </AccordionButton>
                  </h2>
                  <AccordionPanel px="0" pt="8px">
                    <Box display="grid" gridTemplateColumns="1fr 1fr" gap="8px">
                      {headerFields.map((f) => (
                        <Box key={f.key} px="10px" py="8px" borderWidth="1px" borderColor="gray.100" borderRadius="md">
                          <Text fontSize="xs" opacity={0.7}>
                            {f.label}
                          </Text>
                          <Text fontSize="sm">{f.fmt(readData?.[f.key])}</Text>
                        </Box>
                      ))}
                    </Box>
                  </AccordionPanel>
                </AccordionItem>

                <AccordionItem borderTopWidth="1px" borderColor="gray.200">
                  <h2>
                    <AccordionButton px="0" py="6px" _hover={{ bg: 'transparent' }}>
                      <Box flex="1" textAlign="left">
                        <Text size="sm">Information on record</Text>
                        <Text fontSize="xs" opacity={0.65}>
                          Local case facts used by the rules, separate from PDF evidence found by GenAI.
                        </Text>
                      </Box>
                      <AccordionIcon />
                    </AccordionButton>
                  </h2>
                  <AccordionPanel px="0" pt="8px">
                    {codeFields.length === 0 ? (
                      <Text fontSize="sm" opacity={0.7}>
                        No local case facts found.
                      </Text>
                    ) : (
                      <Box display="flex" flexDirection="column" gap="8px">
                        {codeFields.map((r) => (
                          <Box
                            key={r.id}
                            borderWidth="1px"
                            borderColor="blue.100"
                            borderRadius="md"
                            p="8px"
                            bg="blue.50"
                          >
                            <Flex align="center" gap="6px" mb="2px" wrap="wrap">
                              <Text fontSize="xs" opacity={0.7}>
                                {r.field_key || 'field'}
                              </Text>
                              <Badge colorScheme="blue">{r.source_engine || 'code'}</Badge>
                            </Flex>
                            <Text fontSize="sm">
                              {r.value_text || (r.value_json ? JSON.stringify(r.value_json) : 'â€”')}
                            </Text>
                          </Box>
                        ))}
                      </Box>
                    )}
                  </AccordionPanel>
                </AccordionItem>

                {upgradeTypeGroups.length === 0 ? (
                  <AccordionItem borderTopWidth="1px" borderColor="gray.200">
                    <h2>
                      <AccordionButton px="0" py="6px" _hover={{ bg: 'transparent' }}>
                        <Box flex="1" textAlign="left">
                          <Text size="sm">Energy Savings Program Review</Text>
                        </Box>
                        <AccordionIcon />
                      </AccordionButton>
                    </h2>
                    <AccordionPanel px="0" pt="8px">
                      <Text fontSize="sm" opacity={0.7}>
                        No upgrade-type review rows found.
                      </Text>
                    </AccordionPanel>
                  </AccordionItem>
                ) : (
                  upgradeTypeGroups.map((group) => {
                    const meta = getInvoiceUpgradeTypeMeta(group.upgradeTypeKey, group.description);

                    return (
                      <AccordionItem key={group.upgradeTypeKey} borderTopWidth="1px" borderColor="gray.200">
                        <h2>
                          <AccordionButton px="0" py="8px" _hover={{ bg: 'transparent' }}>
                            <Flex flex="1" align="center" gap="8px" textAlign="left" minW={0}>
                              <InvoiceUpgradeTypeTile
                                upgradeTypeKey={group.upgradeTypeKey}
                                description={group.description}
                                size={30}
                              />
                              <Box minW={0}>
                                <Text fontSize="sm" fontWeight="bold" noOfLines={1}>
                                  {meta.label}
                                </Text>
                                <Text fontSize="xs" opacity={0.65}>
                                  {group.results.length} calls | {group.fields.length} fields |{' '}
                                  {group.rulechecks.length} rules | {group.lineitems.length} line items
                                </Text>
                              </Box>
                            </Flex>
                            <AccordionIcon />
                          </AccordionButton>
                        </h2>
                        <AccordionPanel px="0" pt="8px">
                          <Box mb="14px">
                            <Text fontSize="xs" fontWeight="bold" textTransform="uppercase" opacity={0.7} mb="6px">
                              Call results
                            </Text>
                            {group.results.length === 0 ? (
                              <Text fontSize="sm" opacity={0.7}>
                                No call results for this upgrade type.
                              </Text>
                            ) : (
                              <Box display="flex" flexDirection="column" gap="8px">
                                {group.results.map((r) => (
                                  <Box key={r.id} borderWidth="1px" borderColor="gray.100" borderRadius="md" p="8px">
                                    <Flex align="center" gap="6px" mb="2px" wrap="wrap">
                                      <Badge colorScheme={r.source_engine === 'classifier' ? 'teal' : 'purple'}>
                                        {r.source_engine || 'genai'}
                                      </Badge>
                                      <Badge
                                        colorScheme={
                                          r.call_status === 'succeeded' || r.call_status === 'classified'
                                            ? 'green'
                                            : r.call_status === 'failed'
                                              ? 'red'
                                              : 'gray'
                                        }
                                      >
                                        {r.call_status || 'unknown'}
                                      </Badge>
                                      {r.genai_all_rulechecks_pass_flag != null && (
                                        <Badge colorScheme={r.genai_all_rulechecks_pass_flag ? 'green' : 'red'}>
                                          {r.genai_all_rulechecks_pass_flag ? 'PASS' : 'FAIL'}
                                        </Badge>
                                      )}
                                    </Flex>
                                    <Text fontSize="xs" opacity={0.8}>
                                      confidence: {r.genai_overall_confidence ?? r.confidence ?? '—'}
                                    </Text>
                                    {r.evidence_text && (
                                      <Text fontSize="xs" mt="2px">
                                        evidence: {r.evidence_text}
                                      </Text>
                                    )}
                                    {r.classifier_notes && (
                                      <Text fontSize="xs" mt="2px">
                                        notes: {r.classifier_notes}
                                      </Text>
                                    )}
                                    {r.genai_admin_advice && (
                                      <Text fontSize="xs" mt="2px" whiteSpace="pre-wrap">
                                        advice: {r.genai_admin_advice}
                                      </Text>
                                    )}
                                  </Box>
                                ))}
                              </Box>
                            )}
                          </Box>

                          <Box mb="14px">
                            <Text fontSize="xs" fontWeight="bold" textTransform="uppercase" opacity={0.7} mb="6px">
                              Found fields
                            </Text>
                            {group.fields.length === 0 ? (
                              <Text fontSize="sm" opacity={0.7}>
                                No found fields for this upgrade type.
                              </Text>
                            ) : (
                              <Box display="flex" flexDirection="column" gap="8px">
                                {group.fields.map((r) => {
                                  const pageNumber = coercePageNumber(r.page);
                                  const hasPolygon = !!normalizePolygon(r.polygon);
                                  const isActive = activeHighlight?.id === r.id;

                                  return (
                                    <Box
                                      key={r.id}
                                      as={pageNumber ? 'button' : 'div'}
                                      textAlign="left"
                                      borderWidth="1px"
                                      borderColor={isActive ? 'blue.400' : 'gray.100'}
                                      borderRadius="md"
                                      p="8px"
                                      bg={isActive ? 'blue.50' : 'white'}
                                      cursor={pageNumber ? 'pointer' : 'default'}
                                      onClick={pageNumber ? () => handleLocatedFieldClick(r) : undefined}
                                      _hover={
                                        pageNumber
                                          ? { bg: isActive ? 'blue.50' : 'gray.50', borderColor: 'blue.200' }
                                          : undefined
                                      }
                                    >
                                      <Flex align="center" gap="6px" mb="2px" wrap="wrap">
                                        <Text fontSize="xs" opacity={0.7}>
                                          {r.field_key || 'field'} (line {r.line_number ?? '—'})
                                        </Text>
                                        <Badge colorScheme="purple">{r.source_engine || 'genai'}</Badge>
                                        {pageNumber && <Badge colorScheme="cyan">page {pageNumber}</Badge>}
                                        {hasPolygon && <Badge colorScheme="green">polygon</Badge>}
                                      </Flex>
                                      <Text fontSize="sm">
                                        {r.value_text || (r.value_json ? JSON.stringify(r.value_json) : '—')}
                                      </Text>
                                      <Text fontSize="xs" opacity={0.8}>
                                        confidence: {r.confidence ?? '—'}
                                      </Text>
                                    </Box>
                                  );
                                })}
                              </Box>
                            )}
                          </Box>

                          <Box mb="14px">
                            <Text fontSize="xs" fontWeight="bold" textTransform="uppercase" opacity={0.7} mb="6px">
                              Rules
                            </Text>
                            {group.rulechecks.length === 0 ? (
                              <Text fontSize="sm" opacity={0.7}>
                                No rules for this upgrade type.
                              </Text>
                            ) : (
                              <Box display="flex" flexDirection="column" gap="8px">
                                {group.rulechecks.map((r) => (
                                  <Box key={r.id} borderWidth="1px" borderColor="gray.100" borderRadius="md" p="8px">
                                    <Flex align="center" gap="8px" mb="4px">
                                      <Text fontSize="sm" fontWeight="bold">
                                        Rule {r.rule_number ?? '—'}: {r.rule_name || ''}
                                      </Text>
                                      <Badge colorScheme={r.source_engine === 'code' ? 'blue' : 'purple'}>
                                        {r.source_engine || 'genai'}
                                      </Badge>
                                      <Badge colorScheme={r.rule_pass_flag ? 'green' : 'red'}>
                                        {r.rule_pass_flag ? 'PASS' : 'FAIL'}
                                      </Badge>
                                    </Flex>
                                    {(r.source_requirement_id || r.evidence_source) && (
                                      <Text fontSize="xs" opacity={0.7}>
                                        {[r.source_requirement_id, r.evidence_source].filter(Boolean).join(' • ')}
                                      </Text>
                                    )}
                                    <Text fontSize="xs" opacity={0.8}>
                                      confidence: {r.confidence ?? '—'}
                                    </Text>
                                    <Text fontSize="xs" mt="2px">
                                      expected: {r.expected_text || '—'}
                                    </Text>
                                    <Text fontSize="xs" mt="2px">
                                      observed: {r.observed_text || '—'}
                                    </Text>
                                    <Text fontSize="xs" mt="2px">
                                      calculation: {r.calculation || '—'}
                                    </Text>
                                    <Text fontSize="xs" mt="2px">
                                      reason: {r.reason_and_likely_causes || '—'}
                                    </Text>
                                  </Box>
                                ))}
                              </Box>
                            )}
                          </Box>

                          <Box>
                            <Text fontSize="xs" fontWeight="bold" textTransform="uppercase" opacity={0.7} mb="6px">
                              Line items
                            </Text>
                            {group.lineitems.length === 0 ? (
                              <Text fontSize="sm" opacity={0.7}>
                                No line items for this upgrade type.
                              </Text>
                            ) : (
                              <Box display="flex" flexDirection="column" gap="8px">
                                {group.lineitems.map((li) => (
                                  <Box key={li.id} borderWidth="1px" borderColor="gray.100" borderRadius="md" p="8px">
                                    <Text fontSize="xs" opacity={0.7}>
                                      Line {(li.lineitem_seqno ?? '—').toString()}
                                    </Text>
                                    <Text fontSize="sm">{li.ocr_description || '—'}</Text>
                                    <Text fontSize="xs" opacity={0.8}>
                                      qty: {li.ocr_quantity ?? '—'} | unit: {li.ocr_unit_price ?? '—'} | amount:{' '}
                                      {li.ocr_amount ?? '—'}
                                    </Text>
                                  </Box>
                                ))}
                              </Box>
                            )}
                          </Box>
                        </AccordionPanel>
                      </AccordionItem>
                    );
                  })
                )}

                {false && (
                  <>
                    <AccordionItem borderTopWidth="1px" borderColor="gray.200">
                      <h2>
                        <AccordionButton px="0" py="6px" _hover={{ bg: 'transparent' }}>
                          <Box flex="1" textAlign="left">
                            <Text size="sm">Line Items</Text>
                          </Box>
                          <AccordionIcon />
                        </AccordionButton>
                      </h2>
                      <AccordionPanel px="0" pt="8px">
                        {lineitems.length === 0 ? (
                          <Text fontSize="sm" opacity={0.7}>
                            No line items found.
                          </Text>
                        ) : (
                          <Box display="flex" flexDirection="column" gap="8px">
                            {lineitems.map((li) => (
                              <Box key={li.id} borderWidth="1px" borderColor="gray.100" borderRadius="md" p="8px">
                                <Text fontSize="xs" opacity={0.7}>
                                  Line {(li.lineitem_seqno ?? '—').toString()}
                                </Text>
                                <Text fontSize="sm">{li.ocr_description || '—'}</Text>
                                <Text fontSize="xs" opacity={0.8}>
                                  qty: {li.ocr_quantity ?? '—'} | unit: {li.ocr_unit_price ?? '—'} | amount:{' '}
                                  {li.ocr_amount ?? '—'}
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
                          <Box flex="1" textAlign="left">
                            <Text size="sm">GenAI Located Fields</Text>
                          </Box>
                          <AccordionIcon />
                        </AccordionButton>
                      </h2>
                      <AccordionPanel px="0" pt="8px">
                        {locatedFields.length === 0 ? (
                          <Text fontSize="sm" opacity={0.7}>
                            No GenAI located fields found.
                          </Text>
                        ) : (
                          <Box display="flex" flexDirection="column" gap="8px">
                            {locatedFields.map((r) => (
                              <Box key={r.id} borderWidth="1px" borderColor="gray.100" borderRadius="md" p="8px">
                                <Text fontSize="xs" opacity={0.7}>
                                  {r.field_key || 'field'} (line {r.line_number ?? '—'})
                                </Text>
                                <Text fontSize="sm">{r.value_text || '—'}</Text>
                                <Text fontSize="xs" opacity={0.8}>
                                  confidence: {r.confidence ?? '—'}
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
                          <Box flex="1" textAlign="left">
                            <Text size="sm">Pre-existing info on file</Text>
                          </Box>
                          <AccordionIcon />
                        </AccordionButton>
                      </h2>
                      <AccordionPanel px="0" pt="8px">
                        {codeFields.length === 0 ? (
                          <Text fontSize="sm" opacity={0.7}>
                            No pre-existing fields found.
                          </Text>
                        ) : (
                          <Box display="flex" flexDirection="column" gap="8px">
                            {codeFields.map((r) => (
                              <Box key={r.id} borderWidth="1px" borderColor="gray.100" borderRadius="md" p="8px">
                                <Text fontSize="xs" opacity={0.7}>
                                  {r.field_key || 'field'}
                                </Text>
                                <Text fontSize="sm">{r.value_text || '—'}</Text>
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
                            <Text size="sm">Validation Rulechecks</Text>
                          </Box>
                          <AccordionIcon />
                        </AccordionButton>
                      </h2>
                      <AccordionPanel px="0" pt="8px">
                        <Box mb="8px" borderWidth="1px" borderColor="gray.200" borderRadius="md" p="8px" bg="gray.50">
                          <Text fontSize="xs" opacity={0.7}>
                            Overall
                          </Text>
                          <Text fontSize="sm">confidence: {overall?.confidence ?? '—'}</Text>
                          <Text fontSize="sm">
                            pass: {overall?.passFlag == null ? '—' : overall.passFlag ? 'true' : 'false'}
                          </Text>
                          <Text fontSize="sm" whiteSpace="pre-wrap">
                            advice: {overall?.advice || '—'}
                          </Text>
                        </Box>

                        {rulechecks.length === 0 ? (
                          <Text fontSize="sm" opacity={0.7}>
                            No validation rulechecks found.
                          </Text>
                        ) : (
                          <Box display="flex" flexDirection="column" gap="8px">
                            {rulechecks.map((r) => (
                              <Box key={r.id} borderWidth="1px" borderColor="gray.100" borderRadius="md" p="8px">
                                <Flex align="center" gap="8px" mb="4px">
                                  <Text fontSize="sm" fontWeight="bold">
                                    Rule {r.rule_number ?? '—'}: {r.rule_name || ''}
                                  </Text>
                                  <Badge colorScheme={r.source_engine === 'code' ? 'blue' : 'purple'}>
                                    {r.source_engine || 'genai'}
                                  </Badge>
                                  <Badge colorScheme={r.rule_pass_flag ? 'green' : 'red'}>
                                    {r.rule_pass_flag ? 'PASS' : 'FAIL'}
                                  </Badge>
                                </Flex>
                                {(r.source_requirement_id || r.evidence_source) && (
                                  <Text fontSize="xs" opacity={0.7}>
                                    {[r.source_requirement_id, r.evidence_source].filter(Boolean).join(' • ')}
                                  </Text>
                                )}
                                <Text fontSize="xs" opacity={0.8}>
                                  confidence: {r.confidence ?? '—'}
                                </Text>
                                <Text fontSize="xs" mt="2px">
                                  expected: {r.expected_text || '—'}
                                </Text>
                                <Text fontSize="xs" mt="2px">
                                  observed: {r.observed_text || '—'}
                                </Text>
                                <Text fontSize="xs" mt="2px">
                                  reason: {r.reason_and_likely_causes || '—'}
                                </Text>
                              </Box>
                            ))}
                          </Box>
                        )}
                      </AccordionPanel>
                    </AccordionItem>
                  </>
                )}
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
                  <Button
                    size="sm"
                    onClick={() => setActivePageNumber((p) => Math.max(1, p - 1))}
                    isDisabled={activePageNumber <= 1}
                  >
                    Prev
                  </Button>
                  <Text fontSize="sm">
                    Page {activePageNumber} / {numPages || '?'}
                  </Text>
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
                <Text fontSize="sm" opacity={0.7} mb="8px">
                  No PDF URL found for this version.
                </Text>
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
                  <Box position="relative" width={`${renderWidthPx}px`} height={`${overlayHeightPx}px`}>
                    <svg
                      width={renderWidthPx}
                      height={overlayHeightPx}
                      style={{ position: 'absolute', top: 0, left: 0, zIndex: 10, pointerEvents: 'none' }}
                    >
                      {svgPolygonPoints && (
                        <polygon
                          points={svgPolygonPoints}
                          fill="rgba(229, 62, 62, 0.20)"
                          stroke="#e53e3e"
                          strokeWidth={2}
                        />
                      )}
                    </svg>
                    <Box position="absolute" top={0} left={0} zIndex={1}>
                      <Page pageNumber={activePageNumber} width={renderWidthPx} />
                    </Box>
                  </Box>
                </Document>
              )}
              <Text fontSize="xs" opacity={0.6} mt="8px">
                Active PDF evidence: {activeHighlight?.fieldKey || '-'} | page {activePageNumber} / {numPages || '?'}
                {activeHighlight?.polygon ? ' | polygon selected' : ''}
              </Text>
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
                <Heading size="sm" mb={2}>
                  What This Screen Is
                </Heading>
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
                <Heading size="sm" mb={2}>
                  Best Way To Compare Versions
                </Heading>
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
                <Heading size="sm" mb={2}>
                  Fast Text-Only Compare
                </Heading>
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
                <Heading size="sm" mb={2}>
                  How Sections Relate To Rulesets
                </Heading>
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
