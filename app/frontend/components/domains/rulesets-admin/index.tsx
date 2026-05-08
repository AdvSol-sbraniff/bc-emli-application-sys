import React, { useEffect, useMemo, useRef, useState } from 'react';
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
  Input,
  Select,
  Spinner,
  Table,
  Tbody,
  Tooltip,
  Td,
  Text,
  Th,
  Thead,
  Tr,
  useDisclosure,
} from '@chakra-ui/react';
import { ArrowsClockwise, CaretLeft, CaretRight, PencilSimple, Question, XCircle } from '@phosphor-icons/react';
import { useLocation, useNavigate } from 'react-router-dom';
import { ThinBlueTitleBar } from '../../shared/base/thin-blue-title-bar';

type RulesetRow = {
  id: string;
  invoice_upgrade_type_id?: string | null;
  upgrade_type_key?: string | null;
  upgrade_type_description?: string | null;
  ruleset_shortname: string;
  created_at?: string | null;
  updated_at?: string | null;
};

type RulesetApiResp = {
  rows: RulesetRow[];
  meta?: {
    total?: number;
    page?: number;
    per?: number;
    sort?: string;
  };
};

const fmtDate = (s?: string | null) => {
  if (!s) return '';
  const str = String(s);
  return str.includes('T') ? str.split('T')[0] : str.slice(0, 10);
};

function buildSearchParams(obj: Record<string, string | undefined>) {
  const p = new URLSearchParams();
  Object.entries(obj).forEach(([k, v]) => {
    if (v === undefined) return;
    const vv = v.toString().trim();
    if (!vv) return;
    p.set(k, vv);
  });
  return p;
}

export default function RulesetsAdminScreen() {
  const location = useLocation();
  const navigate = useNavigate();

  const [q, setQ] = useState<string>('');
  const [sort, setSort] = useState<string>('updated_at:desc');
  const [page, setPage] = useState<number>(1);
  const [per, setPer] = useState<number>(25);

  const [loading, setLoading] = useState<boolean>(false);
  const [error, setError] = useState<string>('');
  const [rows, setRows] = useState<RulesetRow[]>([]);
  const [total, setTotal] = useState<number>(0);

  const { isOpen: isHelpOpen, onOpen: onHelpOpen, onClose: onHelpClose } = useDisclosure();

  const didInitFromUrl = useRef(false);

  useEffect(() => {
    const params = new URLSearchParams(location.search);

    const next = {
      q: params.get('q') || '',
      sort: params.get('sort') || 'updated_at:desc',
      page: Number(params.get('page') || '1') || 1,
      per: Number(params.get('per') || '25') || 25,
    };

    if (!didInitFromUrl.current) {
      didInitFromUrl.current = true;
      setQ(next.q);
      setSort(next.sort);
      setPage(next.page);
      setPer(next.per);
      return;
    }

    setQ(next.q);
    setSort(next.sort);
    setPage(next.page);
    setPer(next.per);
  }, [location.search]);

  const pushUrl = (next: Partial<{ q: string; sort: string; page: number; per: number }>) => {
    const merged = {
      q,
      sort,
      page,
      per,
      ...next,
    };

    const params = buildSearchParams({
      q: merged.q || undefined,
      sort: merged.sort || undefined,
      page: String(merged.page || 1),
      per: String(merged.per || 25),
    });

    navigate({ pathname: location.pathname, search: `?${params.toString()}` }, { replace: true });
  };

  const fetchRows = async () => {
    setLoading(true);
    setError('');

    try {
      const params = buildSearchParams({
        q: q || undefined,
        sort: sort || undefined,
        page: String(page || 1),
        per: String(per || 25),
      });

      const res = await fetch(`/api/claims/admin/validationgenai_rulesets?${params.toString()}`, {
        method: 'GET',
        headers: { Accept: 'application/json' },
        credentials: 'include',
      });

      const data: RulesetApiResp = await res.json().catch(() => ({ rows: [] }) as RulesetApiResp);

      if (!res.ok) {
        throw new Error((data as any)?.error || (data as any)?.message || `HTTP ${res.status}`);
      }

      setRows(Array.isArray(data?.rows) ? data.rows : []);
      setTotal(Number(data?.meta?.total || 0));
    } catch (e: any) {
      setRows([]);
      setTotal(0);
      setError(e?.message || 'Failed to load rulesets.');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    if (didInitFromUrl.current) fetchRows();
  }, [q, sort, page, per]);

  const totalPages = useMemo(() => {
    const p = Math.max(1, per || 25);
    return Math.max(1, Math.ceil((total || 0) / p));
  }, [total, per]);

  const openEditor = (id: string) => {
    window.open(`/ruleset-editor?id=${encodeURIComponent(id)}`, '_blank', 'noopener,noreferrer');
  };

  const duplicateRuleset = (id: string) => {
    const url = `/ruleset-editor?mode=create&duplicate_from=${encodeURIComponent(id)}`;
    window.open(url, '_blank', 'noopener,noreferrer');
  };

  const openConfigEditor = () => {
    window.open('/ruleset-config-editor', '_blank', 'noopener,noreferrer');
  };

  return (
    <Flex as="main" direction="column" w="full" bg="greys.white" pb="24" minH="100vh">
      <ThinBlueTitleBar title="Rulesets Admin" />

      <Container maxW="container.xl" pb={4} flex="1" pt={6}>
        <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="lg" p={5} bg="white">
          <Flex gap={3} align="end" wrap="wrap" mb={4}>
            <Box flex="1" minW="280px">
              <Text fontSize="xs" opacity={0.7} mb={1}>
                Search (id, shortname, upgrade type, user_record1)
              </Text>
              <Input
                value={q}
                onChange={(e) => {
                  setQ(e.target.value);
                  setPage(1);
                }}
                onBlur={() => pushUrl({ q, page: 1 })}
                placeholder="Search rulesets..."
                bg="white"
              />
            </Box>

            <Box w="240px">
              <Text fontSize="xs" opacity={0.7} mb={1}>
                Sort
              </Text>
              <Select
                value={sort}
                onChange={(e) => {
                  const v = e.target.value;
                  setSort(v);
                  setPage(1);
                  pushUrl({ sort: v, page: 1 });
                }}
                bg="white"
              >
                <option value="updated_at:desc">updated_at desc</option>
                <option value="updated_at:asc">updated_at asc</option>
                <option value="created_at:desc">created_at desc</option>
                <option value="created_at:asc">created_at asc</option>
                <option value="upgrade_type_key:asc">upgrade type asc</option>
                <option value="upgrade_type_key:desc">upgrade type desc</option>
                <option value="ruleset_shortname:asc">shortname asc</option>
                <option value="ruleset_shortname:desc">shortname desc</option>
              </Select>
            </Box>

            <Box w="120px">
              <Text fontSize="xs" opacity={0.7} mb={1}>
                Per page
              </Text>
              <Select
                value={String(per)}
                onChange={(e) => {
                  const v = Number(e.target.value) || 25;
                  setPer(v);
                  setPage(1);
                  pushUrl({ per: v, page: 1 });
                }}
                bg="white"
              >
                <option value="25">25</option>
                <option value="50">50</option>
                <option value="100">100</option>
              </Select>
            </Box>

            <HStack spacing={2} pb={1}>
              <Button size="sm" variant="outline" onClick={openConfigEditor}>
                Edit AI system config
              </Button>
              <Button
                size="sm"
                colorScheme="blue"
                onClick={() => window.open('/ruleset-editor?mode=create', '_blank', 'noopener,noreferrer')}
              >
                Create ruleset
              </Button>
              <Tooltip label="Help: ruleset strategy and governance">
                <IconButton
                  aria-label="Open ruleset help"
                  icon={<Question size={18} />}
                  variant="outline"
                  onClick={onHelpOpen}
                />
              </Tooltip>

              <Tooltip label="Clear filters">
                <IconButton
                  aria-label="Clear filters"
                  icon={<XCircle size={18} />}
                  variant="outline"
                  onClick={() => {
                    setQ('');
                    setSort('updated_at:desc');
                    setPage(1);
                    setPer(25);
                    pushUrl({ q: '', sort: 'updated_at:desc', page: 1, per: 25 });
                  }}
                  isDisabled={!q.trim() && sort === 'updated_at:desc' && per === 25 && page === 1}
                />
              </Tooltip>

              <Tooltip label="Refresh grid">
                <IconButton
                  aria-label="Refresh grid"
                  icon={<ArrowsClockwise size={18} />}
                  variant="outline"
                  onClick={fetchRows}
                  isLoading={loading}
                />
              </Tooltip>
            </HStack>
          </Flex>

          {error && (
            <Box mb={4} p={3} borderWidth="1px" borderRadius="md" borderColor="red.300" bg="red.50">
              <Text color="red.800" fontSize="sm">
                {error}
              </Text>
            </Box>
          )}

          <Box borderWidth="1px" borderRadius="md" overflow="auto">
            <Table size="sm" minW="900px">
              <Thead bg="gray.50">
                <Tr>
                  <Th>Upgrade type</Th>
                  <Th>ruleset_shortname</Th>
                  <Th>updated_at</Th>
                  <Th>created_at</Th>
                  <Th>Actions</Th>
                </Tr>
              </Thead>
              <Tbody>
                {loading ? (
                  <Tr>
                    <Td colSpan={5}>
                      <Flex align="center" gap={2} py={3}>
                        <Spinner size="sm" />
                        <Text>Loading rulesets...</Text>
                      </Flex>
                    </Td>
                  </Tr>
                ) : rows.length === 0 ? (
                  <Tr>
                    <Td colSpan={5}>
                      <Text py={3} opacity={0.8}>
                        No rulesets found.
                      </Text>
                    </Td>
                  </Tr>
                ) : (
                  rows.map((row) => (
                    <Tr key={row.id}>
                      <Td>
                        <Text fontWeight="semibold">{row.upgrade_type_key || ''}</Text>
                        <Text fontSize="xs" opacity={0.7}>
                          {row.upgrade_type_description || ''}
                        </Text>
                      </Td>
                      <Td>{row.ruleset_shortname}</Td>
                      <Td>{fmtDate(row.updated_at)}</Td>
                      <Td>{fmtDate(row.created_at)}</Td>
                      <Td>
                        <Flex gap={2}>
                          <Tooltip label="view or edit details">
                            <IconButton
                              aria-label="view or edit details"
                              size="xs"
                              variant="outline"
                              icon={<PencilSimple size={14} />}
                              onClick={() => openEditor(row.id)}
                            />
                          </Tooltip>
                          <Button size="xs" variant="outline" onClick={() => duplicateRuleset(row.id)}>
                            Duplicate
                          </Button>
                        </Flex>
                      </Td>
                    </Tr>
                  ))
                )}
              </Tbody>
            </Table>
          </Box>

          <Flex mt={4} justify="space-between" align="center" wrap="wrap" gap={3}>
            <Text fontSize="sm" opacity={0.8}>
              Total: {total}
            </Text>

            <Flex gap={2} align="center">
              <Tooltip label="Previous page">
                <IconButton
                  aria-label="Previous page"
                  size="sm"
                  variant="outline"
                  icon={<CaretLeft size={16} />}
                  isDisabled={page <= 1 || loading}
                  onClick={() => {
                    const next = Math.max(1, page - 1);
                    setPage(next);
                    pushUrl({ page: next });
                  }}
                />
              </Tooltip>

              <Text fontSize="sm">
                Page {page} of {totalPages}
              </Text>

              <Tooltip label="Next page">
                <IconButton
                  aria-label="Next page"
                  size="sm"
                  variant="outline"
                  icon={<CaretRight size={16} />}
                  isDisabled={page >= totalPages || loading}
                  onClick={() => {
                    const next = Math.min(totalPages, page + 1);
                    setPage(next);
                    pushUrl({ page: next });
                  }}
                />
              </Tooltip>
            </Flex>
          </Flex>
        </Box>
      </Container>

      <Drawer isOpen={isHelpOpen} placement="left" onClose={onHelpClose} size="xl">
        <DrawerOverlay />
        <DrawerContent>
          <DrawerCloseButton />
          <DrawerHeader>Rulesets Admin Help</DrawerHeader>
          <DrawerBody>
            <Text fontSize="sm" mb={3}>
              Think of a ruleset as a recipe card for how the system checks invoices. Different upgrade types need
              different recipe cards.
            </Text>

            <Text fontSize="sm" fontWeight="bold" mb={1}>
              One ruleset per upgrade type
            </Text>
            <Text fontSize="sm" mb={3}>
              Keep separate rulesets for separate upgrade types. For example, heat pumps and windows should not share
              the same ruleset because they follow different rebate requirements. Use the CleanBC Better Homes Energy
              Savings Program Rebate Eligibility Requirements website as the source of truth for current upgrade
              categories and requirements.
            </Text>

            <Text fontSize="sm" fontWeight="bold" mb={1}>
              Shortname naming
            </Text>
            <Text fontSize="sm" mb={3}>
              Use shortnames that clearly show both upgrade type and version. Example pattern: upgradeType_vYYYY_Qn or
              upgradeType_v###. This makes it easy for staff to know what rule set is active and what changed over time.
            </Text>

            <Text fontSize="sm" fontWeight="bold" mb={1}>
              Change strategy
            </Text>
            <Text fontSize="sm" mb={3}>
              Do not edit an existing ruleset unless it is an emergency. In normal operations, duplicate the ruleset,
              make changes in the copy, test, then promote the new version. This protects history and avoids breaking
              prior results unexpectedly.
            </Text>

            <Text fontSize="sm" fontWeight="bold" mb={1}>
              Testing discipline
            </Text>
            <Text fontSize="sm" mb={3}>
              Always run a well-defined system integration test suite before rollout. Test against older known cases and
              current concern cases. The goal is to confirm the change fixes the target issue without causing
              regressions in other scenarios.
            </Text>

            <Text fontSize="sm" fontWeight="bold" mb={1}>
              Update cadence
            </Text>
            <Text fontSize="sm" mb={3}>
              As a governance guideline, avoid changing rules more than quarterly unless policy changes or a critical
              issue requires faster action.
            </Text>

            <Text fontSize="sm" fontWeight="bold" mb={1}>
              Keep aligned with published program rules
            </Text>
            <Text fontSize="sm" mb={3}>
              Rulesets should stay consistent with the published program requirements on the CleanBC website. Internal
              rule logic should reflect external policy, not drift away from it.
            </Text>

            <Text fontSize="sm" fontWeight="bold" mb={1}>
              Why location and rules are separated
            </Text>
            <Text fontSize="sm" mb={3}>
              The system first finds information (located fields), then applies checks (rule checks). This helps AI work
              better because rules can reuse the same found values instead of re-searching the document each time.
            </Text>

            <Text fontSize="sm" fontWeight="bold" mb={1}>
              What you see in the PDF viewer
            </Text>
            <Text fontSize="sm" mb={3}>
              In the PDF viewer, there are separate accordion sections for found values and rule results. This split
              makes it easier to understand whether a failure happened because data could not be found or because a rule
              comparison failed.
            </Text>

            <Text fontSize="sm" fontWeight="bold" mb={1}>
              Dynamic growth over time
            </Text>
            <Text fontSize="sm">
              Different upgrade types can have different fields and different rules. Also, new rules can be added over
              time. The stored data is designed to grow flexibly so the viewer can expand naturally without redesigning
              the page each time a ruleset evolves.
            </Text>
          </DrawerBody>
        </DrawerContent>
      </Drawer>
    </Flex>
  );
}
