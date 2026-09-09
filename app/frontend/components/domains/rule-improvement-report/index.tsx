import {
  Alert,
  AlertIcon,
  Badge,
  Box,
  Button,
  Container,
  Flex,
  HStack,
  Input,
  Select,
  Spinner,
  Table,
  Tbody,
  Td,
  Text,
  Th,
  Thead,
  Tr,
} from '@chakra-ui/react';
import { ArrowClockwise, CaretRight } from '@phosphor-icons/react';
import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { useLocation, useNavigate } from 'react-router-dom';
import { ThinBlueTitleBar } from '../../shared/base/thin-blue-title-bar';
import { RuleRow, shortDate } from './types';

const get = (search: string, key: string) => new URLSearchParams(search).get(key) ?? '';

export default function RuleImprovementReportScreen() {
  const location = useLocation();
  const navigate = useNavigate();
  const [rows, setRows] = useState<RuleRow[]>([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  const q = get(location.search, 'q');
  const sort = get(location.search, 'sort') || 'complaint_count:desc';
  const page = Math.max(1, Number(get(location.search, 'page')) || 1);
  const requestedPer = Number(get(location.search, 'per')) || 25;
  const per = [10, 25, 50, 100].includes(requestedPer) ? requestedPer : 25;

  const replaceParams = (patch: Record<string, string>) => {
    const params = new URLSearchParams(location.search);
    Object.entries(patch).forEach(([key, value]) => {
      if (value) params.set(key, value);
      else params.delete(key);
    });
    const query = params.toString();
    navigate(`${location.pathname}${query ? `?${query}` : ''}`, { replace: true });
  };

  const apiParams = useMemo(() => {
    const params = new URLSearchParams();
    if (q) params.set('q', q);
    params.set('page', String(page));
    params.set('per', String(per));
    params.set('sort', sort);
    return params;
  }, [page, per, q, sort]);

  const load = useCallback(async () => {
    setLoading(true);
    setError('');
    try {
      const response = await fetch(`/api/claims/admin/reports/rule_improvement?${apiParams}`, {
        credentials: 'include',
      });
      const data = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(data.error || 'Unable to load rule reporting.');
      setRows(data.rows ?? []);
      setTotal(data.meta?.total ?? 0);
    } catch (loadError: any) {
      setError(loadError?.message || 'Unable to load rule reporting.');
    } finally {
      setLoading(false);
    }
  }, [apiParams]);

  useEffect(() => {
    void load();
  }, [load]);

  const openRule = (row: RuleRow) => {
    const returnQuery = encodeURIComponent(location.search);
    navigate(
      `/reports-rule-improvement/${row.source_engine}/${encodeURIComponent(row.rule_key)}?return_query=${returnQuery}`,
    );
  };

  return (
    <>
      <ThinBlueTitleBar title="Rule Improvement Report" />
      <Container maxW="container.xl" py={6}>
        <Flex
          justify="space-between"
          align={{ base: 'start', md: 'center' }}
          direction={{ base: 'column', md: 'row' }}
          gap={3}
          mb={5}
        >
          <Box>
            <Text fontSize={{ base: 'xl', md: '2xl' }} fontWeight="bold">
              Which rule should I investigate next?
            </Text>
            <Text color="gray.600">
              GenAI rules are measured from their latest prompt version. Code rules are measured by their distinct
              implementation key and record.
            </Text>
          </Box>
          <Button leftIcon={<ArrowClockwise />} size="sm" variant="outline" onClick={() => void load()}>
            Refresh
          </Button>
        </Flex>

        {error && (
          <Alert status="error" mb={5}>
            <AlertIcon />
            {error}
          </Alert>
        )}

        <Box borderWidth="1px" borderRadius="md" overflow="hidden">
          <Flex
            p={4}
            bg="gray.50"
            justify="space-between"
            align={{ base: 'stretch', lg: 'center' }}
            direction={{ base: 'column', lg: 'row' }}
            gap={3}
          >
            <Box>
              <Text fontWeight="bold">Rule implementations</Text>
              <Text fontSize="sm" color="gray.600">
                {total} rules. GenAI metrics reset after a prompt change; code metrics remain with that code-rule key.
              </Text>
            </Box>
            <Flex gap={3} direction={{ base: 'column', md: 'row' }}>
              <Input
                aria-label="Search rules"
                placeholder="Search rule name or key"
                value={q}
                bg="white"
                width={{ base: 'full', md: '280px' }}
                onChange={(event) => replaceParams({ q: event.target.value, page: '1' })}
              />
              <Select
                aria-label="Sort rules"
                value={sort}
                bg="white"
                width={{ base: 'full', md: '250px' }}
                onChange={(event) => replaceParams({ sort: event.target.value, page: '1' })}
              >
                <option value="complaint_count:desc">Most complaints</option>
                <option value="candidate_false_positive_count:desc">Most false-positive candidates</option>
                <option value="candidate_false_negative_count:desc">Most false-negative candidates</option>
                <option value="total_round_count:desc">Most contractor rounds</option>
                <option value="invoice_count:desc">Most invoices assessed</option>
                <option value="last_changed_at:desc">Most recently changed</option>
                <option value="contractor_display_name:asc">Rule name A–Z</option>
              </Select>
            </Flex>
          </Flex>

          <Box overflowX="auto">
            <Table size="sm">
              <Thead>
                <Tr>
                  <Th>Rule</Th>
                  <Th>Type</Th>
                  <Th whiteSpace="nowrap">Metrics since</Th>
                  <Th isNumeric>Invoice versions assessed</Th>
                  <Th isNumeric>Complaints</Th>
                  <Th isNumeric>False-positive candidates</Th>
                  <Th isNumeric>False-negative candidates</Th>
                  <Th isNumeric>Contractor rounds</Th>
                  <Th aria-label="Open rule" />
                </Tr>
              </Thead>
              <Tbody>
                {rows.map((row) => (
                  <Tr
                    key={`${row.source_engine}:${row.rule_id}`}
                    cursor="pointer"
                    _hover={{ bg: 'blue.50' }}
                    onClick={() => openRule(row)}
                  >
                    <Td minW="300px">
                      <Text fontWeight="semibold">{row.contractor_display_name}</Text>
                      <HStack mt={1}>
                        {!row.enabled && <Badge colorScheme="gray">Disabled</Badge>}
                        <Text fontSize="xs" color="gray.500" noOfLines={1}>
                          {row.rule_key}
                        </Text>
                      </HStack>
                    </Td>
                    <Td>
                      <Badge colorScheme={row.source_engine === 'genai' ? 'blue' : 'purple'}>
                        {row.source_engine === 'genai' ? 'GenAI' : 'Code'}
                      </Badge>
                    </Td>
                    <Td whiteSpace="nowrap">{shortDate(row.current_effective_at)}</Td>
                    <Td isNumeric>{row.invoice_count}</Td>
                    <Td isNumeric>{row.complaint_count}</Td>
                    <Td isNumeric>{row.candidate_false_positive_count}</Td>
                    <Td isNumeric>{row.candidate_false_negative_count}</Td>
                    <Td isNumeric>
                      <Text fontWeight="semibold">{row.total_round_count}</Text>
                      <Text fontSize="xs" color="gray.500">
                        {row.average_rounds || '—'} average
                      </Text>
                    </Td>
                    <Td>
                      <CaretRight aria-hidden />
                    </Td>
                  </Tr>
                ))}
                {!loading && rows.length === 0 && (
                  <Tr>
                    <Td colSpan={9} py={10} textAlign="center" color="gray.500">
                      No rules match your search.
                    </Td>
                  </Tr>
                )}
              </Tbody>
            </Table>
          </Box>

          <Flex p={4} justify="space-between" align="center" borderTopWidth="1px">
            <Select
              aria-label="Rules per page"
              size="sm"
              width="110px"
              value={per}
              onChange={(event) => replaceParams({ per: event.target.value, page: '1' })}
            >
              {[10, 25, 50, 100].map((value) => (
                <option key={value} value={value}>
                  {value} rows
                </option>
              ))}
            </Select>
            <HStack>
              {loading && <Spinner size="sm" />}
              <Button size="sm" isDisabled={page <= 1} onClick={() => replaceParams({ page: String(page - 1) })}>
                Previous
              </Button>
              <Button
                size="sm"
                isDisabled={page * per >= total}
                onClick={() => replaceParams({ page: String(page + 1) })}
              >
                Next
              </Button>
            </HStack>
          </Flex>
        </Box>
      </Container>
    </>
  );
}
