import React, { useEffect, useMemo, useState } from 'react';
import {
  Box,
  Button,
  Container,
  Flex,
  FormControl,
  FormErrorMessage,
  FormLabel,
  Heading,
  Input,
  Spinner,
  Text,
} from '@chakra-ui/react';
import { useLocation, useNavigate } from 'react-router-dom';
import { BlueTitleBar } from '../../shared/base/blue-title-bar';

type EligibilityRecordDto = {
  id: string;
  user_id: string;
  eligibility_code: string;
  income_level?: number | null;
  applied_at: string;
  approved_at: string;
  expires_at: string;
  created_at?: string;
  updated_at?: string;
};

type FieldErrors = Partial<Record<'userId' | 'eligibilityCode' | 'appliedAt' | 'approvedAt' | 'expiresAt', string>>;

function useQueryParam(name: string): string | null {
  const { search } = useLocation();
  return useMemo(() => new URLSearchParams(search).get(name), [search, name]);
}

function deriveIncomeLevel(value: string): number | null {
  const token = value.trim().toUpperCase();
  if (token.startsWith('ESP1') || token.startsWith('ESPI')) return 1;
  if (token.startsWith('ESP2')) return 2;
  if (token.startsWith('ESP3')) return 3;
  return null;
}

function toDateInputValue(value?: string | null): string {
  if (!value) return '';
  return String(value).slice(0, 10);
}

export default function EligibilitycodeEditorScreen() {
  const navigate = useNavigate();

  const id = useQueryParam('id');
  const mode = useQueryParam('mode');
  const userIdFromQuery = useQueryParam('user_id');
  const emailFromQuery = useQueryParam('email');
  const nameFromQuery = useQueryParam('name');
  const isCreateMode = mode === 'create';

  const [isLoading, setIsLoading] = useState<boolean>(true);
  const [isSaving, setIsSaving] = useState<boolean>(false);
  const [error, setError] = useState<string | null>(null);
  const [fieldErrors, setFieldErrors] = useState<FieldErrors>({});

  const [record, setRecord] = useState<EligibilityRecordDto | null>(null);

  const [userId, setUserId] = useState<string>('');
  const [eligibilityCode, setEligibilityCode] = useState<string>('');
  const [appliedAt, setAppliedAt] = useState<string>('');
  const [approvedAt, setApprovedAt] = useState<string>('');
  const [expiresAt, setExpiresAt] = useState<string>('');

  const [initialValues, setInitialValues] = useState({
    userId: '',
    eligibilityCode: '',
    appliedAt: '',
    approvedAt: '',
    expiresAt: '',
  });

  const isDirty =
    userId !== initialValues.userId ||
    eligibilityCode !== initialValues.eligibilityCode ||
    appliedAt !== initialValues.appliedAt ||
    approvedAt !== initialValues.approvedAt ||
    expiresAt !== initialValues.expiresAt;
  const incomeLevel = deriveIncomeLevel(eligibilityCode) ?? record?.income_level ?? null;

  function updateField<K extends keyof FieldErrors>(key: K, value: string, setter: (next: string) => void) {
    setter(value);
    setFieldErrors((prev) => {
      if (!prev[key]) return prev;
      const next = { ...prev };
      delete next[key];
      return next;
    });
  }

  function validateForm(): boolean {
    const next: FieldErrors = {};

    if (isCreateMode && !userId.trim()) next.userId = 'user_id is required.';
    if (!eligibilityCode.trim()) {
      next.eligibilityCode = 'eligibility_code is required.';
    } else if (deriveIncomeLevel(eligibilityCode) === null) {
      next.eligibilityCode = 'eligibility_code must start with ESP1, ESPI, ESP2, or ESP3.';
    }
    if (!appliedAt.trim()) next.appliedAt = 'applied_at is required.';
    if (!approvedAt.trim()) next.approvedAt = 'approved_at is required.';
    if (!expiresAt.trim()) next.expiresAt = 'expires_at is required.';
    if (appliedAt && expiresAt && expiresAt <= appliedAt) {
      next.expiresAt = 'expires_at must be after applied_at.';
    }

    setFieldErrors(next);
    return Object.keys(next).length === 0;
  }

  async function load() {
    setIsLoading(true);
    setError(null);

    try {
      setFieldErrors({});
      if (isCreateMode) {
        const nextUserId = userIdFromQuery || '';
        setRecord(null);
        setUserId(nextUserId);
        setEligibilityCode('');
        setAppliedAt('');
        setApprovedAt('');
        setExpiresAt('');
        setFieldErrors({});
        setInitialValues({
          userId: nextUserId,
          eligibilityCode: '',
          appliedAt: '',
          approvedAt: '',
          expiresAt: '',
        });
        return;
      }

      if (!id) {
        setError('Missing query param: id');
        return;
      }

      const resp = await fetch(`/api/claims/admin/users_eligibilitycodes/${id}`, {
        method: 'GET',
        headers: { Accept: 'application/json' },
        credentials: 'include',
      });

      if (!resp.ok) {
        const txt = await resp.text();
        throw new Error(`GET failed (${resp.status}): ${txt}`);
      }

      const data: EligibilityRecordDto = await resp.json();
      setFieldErrors({});
      setRecord(data);
      setUserId(data.user_id || '');
      setEligibilityCode(data.eligibility_code || '');
      setAppliedAt(toDateInputValue(data.applied_at));
      setApprovedAt(toDateInputValue(data.approved_at));
      setExpiresAt(toDateInputValue(data.expires_at));
      setInitialValues({
        userId: data.user_id || '',
        eligibilityCode: data.eligibility_code || '',
        appliedAt: toDateInputValue(data.applied_at),
        approvedAt: toDateInputValue(data.approved_at),
        expiresAt: toDateInputValue(data.expires_at),
      });
    } catch (e: any) {
      setError(e?.message || 'Load failed');
    } finally {
      setIsLoading(false);
    }
  }

  async function save() {
    if (!isCreateMode && !id) return;
    if (!validateForm()) return;

    setIsSaving(true);
    setError(null);

    try {
      const endpoint = isCreateMode
        ? '/api/claims/admin/users_eligibilitycodes'
        : `/api/claims/admin/users_eligibilitycodes/${id}`;
      const method = isCreateMode ? 'POST' : 'PATCH';

      const body = isCreateMode
        ? {
            user_id: userId.trim(),
            eligibility_code: eligibilityCode.trim(),
            applied_at: appliedAt,
            approved_at: approvedAt,
            expires_at: expiresAt,
          }
        : {
            eligibility_code: eligibilityCode.trim(),
            applied_at: appliedAt,
            approved_at: approvedAt,
            expires_at: expiresAt,
          };

      const resp = await fetch(endpoint, {
        method,
        headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
        credentials: 'include',
        body: JSON.stringify(body),
      });

      if (!resp.ok) {
        const txt = await resp.text();
        throw new Error(`${method} failed (${resp.status}): ${txt}`);
      }

      const data: EligibilityRecordDto = await resp.json();
      setFieldErrors({});
      setRecord(data);
      setUserId(data.user_id || '');
      setEligibilityCode(data.eligibility_code || '');
      setAppliedAt(toDateInputValue(data.applied_at));
      setApprovedAt(toDateInputValue(data.approved_at));
      setExpiresAt(toDateInputValue(data.expires_at));
      setInitialValues({
        userId: data.user_id || '',
        eligibilityCode: data.eligibility_code || '',
        appliedAt: toDateInputValue(data.applied_at),
        approvedAt: toDateInputValue(data.approved_at),
        expiresAt: toDateInputValue(data.expires_at),
      });

      if (isCreateMode) {
        navigate(`/eligibilitycode-editor?id=${encodeURIComponent(data.id)}`, { replace: true });
      }
    } catch (e: any) {
      setError(e?.message || 'Save failed');
    } finally {
      setIsSaving(false);
    }
  }

  useEffect(() => {
    load();
  }, [id, mode, userIdFromQuery]);

  return (
    <Box>
      <BlueTitleBar title="Eligibility Code Editor" />

      <Container maxW="4xl" py={6}>
        {!id && !isCreateMode && (
          <Box p={4} borderWidth="1px" borderRadius="md">
            <Text fontWeight="bold">Missing id</Text>
            <Text>
              Use: /eligibilitycode-editor?id=&lt;uuid&gt; or /eligibilitycode-editor?mode=create&user_id=&lt;uuid&gt;
            </Text>
          </Box>
        )}

        {(id || isCreateMode) && (
          <Box borderWidth="1px" borderRadius="lg" p={5} bg="white">
            <Flex align="center" justify="space-between" mb={4}>
              <Heading size="md">{isCreateMode ? 'Insert Eligibility Code' : 'Update Eligibility Code'}</Heading>
              <Flex gap={2}>
                <Button onClick={load} variant="outline" isDisabled={isLoading || isSaving}>
                  Reload
                </Button>
                <Button onClick={save} colorScheme="blue" isLoading={isSaving} isDisabled={isLoading || !isDirty}>
                  Save
                </Button>
              </Flex>
            </Flex>

            {(nameFromQuery || emailFromQuery) && (
              <Box mb={4} p={3} borderWidth="1px" borderRadius="md" bg="gray.50">
                <Text fontSize="sm" fontWeight="bold">
                  User context
                </Text>
                {nameFromQuery && <Text fontSize="sm">name: {nameFromQuery}</Text>}
                {emailFromQuery && <Text fontSize="sm">email: {emailFromQuery}</Text>}
              </Box>
            )}

            {isLoading && (
              <Flex align="center" gap={3} p={3}>
                <Spinner size="sm" />
                <Text>Loading...</Text>
              </Flex>
            )}

            {error && (
              <Box p={3} borderWidth="1px" borderRadius="md" mb={4} borderColor="red.300" bg="red.50">
                <Text color="red.800" fontSize="sm">
                  {error}
                </Text>
              </Box>
            )}

            {!isLoading && !error && (
              <Flex direction="column" gap={4}>
                <FormControl isRequired isInvalid={Boolean(fieldErrors.userId)}>
                  <FormLabel fontSize="xs" opacity={0.7} mb={1}>
                    user_id
                  </FormLabel>
                  <Input
                    value={userId}
                    onChange={(e) => updateField('userId', e.target.value, setUserId)}
                    isDisabled={!isCreateMode}
                    fontFamily="mono"
                    required
                  />
                  <FormErrorMessage>{fieldErrors.userId}</FormErrorMessage>
                </FormControl>
                <FormControl isRequired isInvalid={Boolean(fieldErrors.eligibilityCode)}>
                  <FormLabel fontSize="xs" opacity={0.7} mb={1}>
                    eligibility_code
                  </FormLabel>
                  <Input
                    value={eligibilityCode}
                    onChange={(e) => updateField('eligibilityCode', e.target.value, setEligibilityCode)}
                    required
                  />
                  <FormErrorMessage>{fieldErrors.eligibilityCode}</FormErrorMessage>
                </FormControl>
                <Box>
                  <Text fontSize="xs" opacity={0.7} mb={1}>
                    income_level
                  </Text>
                  <Input value={incomeLevel === null ? '—' : String(incomeLevel)} isReadOnly bg="gray.50" />
                  <Text fontSize="xs" opacity={0.7} mt={1}>
                    Stored from the eligibility code prefix on save.
                  </Text>
                </Box>
                <FormControl isRequired isInvalid={Boolean(fieldErrors.appliedAt)}>
                  <FormLabel fontSize="xs" opacity={0.7} mb={1}>
                    applied_at
                  </FormLabel>
                  <Input
                    type="date"
                    value={appliedAt}
                    onChange={(e) => updateField('appliedAt', e.target.value, setAppliedAt)}
                    required
                  />
                  <FormErrorMessage>{fieldErrors.appliedAt}</FormErrorMessage>
                </FormControl>
                <FormControl isRequired isInvalid={Boolean(fieldErrors.approvedAt)}>
                  <FormLabel fontSize="xs" opacity={0.7} mb={1}>
                    approved_at
                  </FormLabel>
                  <Input
                    type="date"
                    value={approvedAt}
                    onChange={(e) => updateField('approvedAt', e.target.value, setApprovedAt)}
                    required
                  />
                  <FormErrorMessage>{fieldErrors.approvedAt}</FormErrorMessage>
                </FormControl>
                <FormControl isRequired isInvalid={Boolean(fieldErrors.expiresAt)}>
                  <FormLabel fontSize="xs" opacity={0.7} mb={1}>
                    expires_at
                  </FormLabel>
                  <Input
                    type="date"
                    value={expiresAt}
                    onChange={(e) => updateField('expiresAt', e.target.value, setExpiresAt)}
                    required
                  />
                  <FormErrorMessage>{fieldErrors.expiresAt}</FormErrorMessage>
                </FormControl>

                <Text fontSize="sm" opacity={0.8}>
                  {isDirty ? 'Unsaved changes' : 'Saved'}
                  {record?.updated_at ? ` • updated_at: ${record.updated_at}` : ''}
                </Text>
              </Flex>
            )}
          </Box>
        )}
      </Container>
    </Box>
  );
}
