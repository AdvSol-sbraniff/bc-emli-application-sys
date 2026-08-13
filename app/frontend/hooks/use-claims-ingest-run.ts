import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useMst } from '../setup/root';
import {
  ClaimsUploadRequestError,
  claimsUploadCaughtErrorMessage,
  claimsUploadRequestError,
} from '../components/shared/claims/upload-error';

export type ClaimsIngestPresentationState = 'processing' | 'ready' | 'needs_correction' | 'failed';

export type ClaimsIngestRun = {
  id: string;
  session_id: string;
  run_kind: 'initial_upload' | 'fix_upload' | 'rules_rerun';
  status: string;
  presentation_state: ClaimsIngestPresentationState;
  failure_category?: string | null;
  failure_code?: string | null;
  failure_message?: string | null;
  retry_guidance?: string | null;
  invoice_id?: string | null;
  invoice_status?: string | null;
  invoice_version_id?: string | null;
  invoice_versionno?: number | null;
  original_filename?: string | null;
  can_continue?: boolean;
  upgrade_type_scope_change?: unknown;
};

export function useClaimsIngestRun(runId: string, errorFallback: string) {
  const { sessionStore } = useMst();
  const [run, setRun] = useState<ClaimsIngestRun | null>(null);
  const [error, setError] = useState('');
  const [errorStatus, setErrorStatus] = useState<number | null>(null);
  const [errorFailureStatus, setErrorFailureStatus] = useState('');
  const transientFailureCount = useRef(0);

  const refresh = useCallback(async () => {
    if (!runId) return;
    try {
      const response = await fetch(`/api/claims/contractor/ingest/runs/${encodeURIComponent(runId)}`, {
        method: 'GET',
        headers: { Accept: 'application/json' },
        credentials: 'include',
        cache: 'no-store',
      });
      const data = await response.json().catch(() => ({}));
      if (!response.ok) throw claimsUploadRequestError(response, data, errorFallback);

      transientFailureCount.current = 0;
      setRun(data as ClaimsIngestRun);
      setError('');
      setErrorStatus(null);
      setErrorFailureStatus('');
    } catch (caught: unknown) {
      const status = caught instanceof ClaimsUploadRequestError ? caught.status : null;
      const retryable = status === null || status === 429 || status >= 500;

      if (retryable) {
        transientFailureCount.current += 1;
        if (transientFailureCount.current >= 3) {
          setError(claimsUploadCaughtErrorMessage(caught, errorFallback));
          setErrorStatus(status);
          setErrorFailureStatus(caught instanceof ClaimsUploadRequestError ? caught.failureStatus : '');
        }
      } else {
        setError(claimsUploadCaughtErrorMessage(caught, errorFallback));
        setErrorStatus(status);
        setErrorFailureStatus(caught instanceof ClaimsUploadRequestError ? caught.failureStatus : '');
        setRun(null);
        if (status === 401) sessionStore.setTokenExpired(true);
      }
    }
  }, [errorFallback, runId, sessionStore]);

  useEffect(() => {
    setRun(null);
    setError('');
    setErrorStatus(null);
    setErrorFailureStatus('');
    transientFailureCount.current = 0;
    if (runId) void refresh();
  }, [refresh, runId]);

  const nonRetryableError = errorStatus !== null && errorStatus >= 400 && errorStatus < 500 && errorStatus !== 429;
  const presentationState = run?.presentation_state ?? (runId && !nonRetryableError ? 'processing' : null);
  const isPolling = useMemo(
    () => !!runId && !nonRetryableError && presentationState === 'processing',
    [nonRetryableError, presentationState, runId],
  );

  useEffect(() => {
    if (!isPolling) return;
    const intervalId = window.setInterval(() => void refresh(), 3000);
    return () => window.clearInterval(intervalId);
  }, [isPolling, refresh]);

  const clearError = useCallback(() => {
    transientFailureCount.current = 0;
    setError('');
    setErrorStatus(null);
    setErrorFailureStatus('');
  }, []);

  return {
    run,
    presentationState,
    isPolling,
    error,
    errorStatus,
    errorFailureStatus,
    clearError,
    refresh,
  };
}
