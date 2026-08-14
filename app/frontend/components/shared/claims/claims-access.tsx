import React, { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react';
import { observer } from 'mobx-react-lite';
import { useMst } from '../../../setup/root';

type ClaimsAccessContextValue = {
  can: (functionKey: string) => boolean;
  error: string;
  functionKeys: string[];
  loading: boolean;
  refresh: () => Promise<void>;
};

const ClaimsAccessContext = createContext<ClaimsAccessContextValue>({
  can: () => false,
  error: '',
  functionKeys: [],
  loading: false,
  refresh: async () => undefined,
});

export const ClaimsAccessProvider = observer(({ children }: { children: React.ReactNode }) => {
  const { sessionStore, userStore } = useMst();
  const currentUserId = userStore.currentUser?.id || '';
  const [functionKeys, setFunctionKeys] = useState<string[]>([]);
  const [loading, setLoading] = useState(Boolean(sessionStore.loggedIn && currentUserId));
  const [error, setError] = useState('');

  const refresh = useCallback(async () => {
    if (!sessionStore.loggedIn || !currentUserId) {
      setFunctionKeys([]);
      setError('');
      setLoading(false);
      return;
    }

    setLoading(true);
    setError('');
    try {
      const response = await fetch('/api/claims/access', {
        credentials: 'include',
        headers: { Accept: 'application/json' },
      });
      const body = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(body?.error || `HTTP ${response.status}`);
      setFunctionKeys(Array.isArray(body?.function_keys) ? body.function_keys.map(String) : []);
    } catch (requestError: any) {
      setFunctionKeys([]);
      setError(requestError?.message || 'Claims access could not be loaded.');
    } finally {
      setLoading(false);
    }
  }, [currentUserId, sessionStore.loggedIn]);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  const value = useMemo<ClaimsAccessContextValue>(
    () => ({
      can: (functionKey: string) => functionKeys.includes(functionKey),
      error,
      functionKeys,
      loading,
      refresh,
    }),
    [error, functionKeys, loading, refresh],
  );

  return <ClaimsAccessContext.Provider value={value}>{children}</ClaimsAccessContext.Provider>;
});

export const useClaimsAccess = () => useContext(ClaimsAccessContext);
